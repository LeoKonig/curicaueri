{-# LANGUAGE OverloadedStrings #-}
-- | La cáscara: lo único imperativo del núcleo (documento funcional, sección 1).
--
-- Abre un socket TCP local, lee una línea JSON por mensaje, sella los comandos
-- con el tick siguiente, lleva el reloj real con cinco velocidades y la pausa,
-- llama a 'pasoDetallado' cuando toca y envía al cliente lo que cambió.
-- No decide nada del estado del juego: la pausa y la velocidad cambian cuándo
-- se llama a 'paso', nunca lo que devuelve.
--
-- Atiende a un cliente a la vez. La partida sigue viva entre conexiones: si el
-- cliente se desconecta y vuelve, recibe una instantánea y continúa.
--
-- Agentes externos (ver Agente.hs):
--   --agente "programa args"    lanza un agente que decide por una facción
--   --agente-faccion N          su facción (1 por omisión: en el prototipo solo
--                               hay una, así que el agente gobierna el reino)
--   --agente-espera MS          tiempo límite por respuesta (500 por omisión)
--   --registro-agente ARCHIVO   anota cada respuesta (JSON Lines)
--   --reproducir-agente ARCHIVO responde con lo anotado, sin programa
--
-- Sin cliente (para el arnés y las pruebas):
--   --sin-cliente --ticks N [--volcar ARCHIVO] [--metricas]
--
-- Guion del escenario (actos, situaciones, director; ver Motor.Guion):
--   --guion ARCHIVO
--
-- Ejes de poder (ver Motor.Autoridad; sin esta opción, el catálogo no trae ejes):
--   --ejes ARCHIVO           por ejemplo datos/ejes.json
module Main (main) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Exception (IOException, bracket, finally, try)
import Control.Monad (forM, forM_, unless, when)
import qualified Data.Aeson as A
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import Data.IORef
import Data.Int (Int64)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import GHC.Clock (getMonotonicTimeNSec)
import Network.Socket
import System.Environment (getArgs)
import System.IO
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>), (<.>))
import Data.Char (isAlphaNum)
import qualified Data.Aeson.Types as A
import Motor.Guardado (guardar, cargar)

import Motor.Base
import Motor.Estado
import Motor.Hechos (Hecho)
import Motor.Juego
import Motor.Mapa
import Motor.Proyeccion
import Motor.Protocolo
import Motor.Vista (Vista)

import Motor.Calendario (esInicioDePeriodo)
import qualified Data.Map.Strict as Map
import Motor.Guion
import Motor.Director (metricas, cumpleVariedad, Metricas (..))
import Motor.Carga (Validacion (..), ErrorCarga (..))
import Motor.Autoridad
import Agente

import Reglas.Comando
import Reglas.Constantes (constantesDefault)
import Reglas.Escenario
import Reglas.Estado (Purepecha)
import qualified Reglas.Juego as RJ

-- | Milisegundos por día, de la velocidad 1 (más lenta) a la 5 (más rápida).
-- V5: a velocidad normal una veintena tarda unos 20 s; a la más rápida unos 3;
-- a la más lenta alrededor de un minuto. Se calibran en el hito 2.
velocidadesPorOmision :: [Int]
velocidadesPorOmision = [3000, 1500, 1000, 500, 150]

palabras :: String -> [String]
palabras t = case break (== ',') t of
  (a, _ : r) -> a : palabras r
  (a, [])    -> [a | not (null a)]

velocidadNormal :: Int
velocidadNormal = 3

-- | La facción del jugador en el prototipo.
faccionJugador :: FaccionId
faccionJugador = FaccionId 1

data Partida = Partida
  { pEstado    :: Estado Purepecha
  , pSiguiente :: Int64                       -- ^ tick que correrá a continuación
  , pPendientes :: [Sellado Comando]          -- ^ comandos para el tick siguiente
  , pVelocidad :: Int
  , pPausado   :: Bool
  , pVista     :: Vista                       -- ^ la última vista enviada
  , pRespuestas :: [Respuesta]                -- ^ respuestas a decisiones para el tick siguiente
  , pDecisionesEnviadas :: [Int]              -- ^ decisiones que el cliente ya conoce
  }

main :: IO ()
main = do
  args <- getArgs
  let opcion n d = case dropWhile (/= n) args of
                     (_ : v : _) -> v
                     _           -> d
      puerto = opcion "--puerto" "4646"
      -- --mapa 60x45 da unos 2 700 hexágonos (prueba de rendimiento del hito 2)
      (ancho, alto) = case break (== 'x') (opcion "--mapa" "") of
                        (a, _ : b) | [(x, "")] <- reads a, [(y, "")] <- reads b -> (x, y)
                        _ -> (hexAncho datosMapa1475, hexAlto datosMapa1475)
      carpeta = opcion "--partidas" "partidas"
      -- --velocidades 3000,1500,1000,500,150: milisegundos por día, para
      -- calibrar jugando sin recompilar.
      vels = case mapM (\x -> case reads x of [(n, "")] | n > 0 -> Just n; _ -> Nothing)
                       (palabras (opcion "--velocidades" "")) of
               Just vs | length vs == 5 -> vs
               _ -> velocidadesPorOmision
  hSetBuffering stderr LineBuffering
  -- El registro lleva acentos: sin esto, con una configuración regional que no
  -- sea UTF-8, el núcleo se cae al escribir su primera línea.
  hSetEncoding stderr utf8
  mapaR <- either (fail . show) pure (proveedorHexagonal datosMapa1475 { hexAncho = ancho, hexAlto = alto })
  createDirectoryIfMissing True carpeta
  let juego = RJ.juego constantesDefault
      e0    = reubicar ancho alto estadoInicial1475
  agente <- case opcion "--agente" "" of
    "" -> case opcion "--reproducir-agente" "" of
      "" -> pure Nothing
      r  -> Just <$> reproducirAgente r
    comando -> Just <$> lanzarAgente comando (read (opcion "--agente-espera" "500"))
  mregistro <- case opcion "--registro-agente" "" of
    "" -> pure Nothing
    r  -> Just <$> openFile r WriteMode
  guion <- case opcion "--guion" "" of
    "" -> pure guionVacio
    ruta -> do
      bs <- BL.readFile ruta
      case A.eitherDecode bs of
        Left err -> fail ("guion ilegible (" <> ruta <> "): " <> err)
        Right v -> case cargarGuion (T.pack ruta) inicio1475 v of
          Validacion [] (Just g) -> do
            registro ("guion " <> T.pack ruta <> ": " <> T.pack (show (length (guFases g))) <> " fases, "
                      <> T.pack (show (length (guSituaciones g))) <> " situaciones")
            pure g
          Validacion errs _ -> do
            mapM_ (\e -> registro ("guion: " <> errArchivo e <> " " <> errRuta e <> ": " <> errMensaje e)) errs
            fail "el guion tiene errores"
  ejesTodos <- case opcion "--ejes" "" of
    "" -> pure []
    ruta -> do
      bs <- BL.readFile ruta
      case A.eitherDecode bs of
        Left err -> fail ("ejes ilegibles (" <> ruta <> "): " <> err)
        Right v -> validado (cargarEjes (T.pack ruta) v)
  ejes <- validado (ejesActivos "escenario 1475" ejesTodos ejesActivos1475)
  validado (validarRequisitos "catálogo de comandos" ejesTodos [ (dcTipo d, dcRequiere d) | d <- catalogoComandos ])
  unless (null ejes) $ registro ("ejes activos: " <> T.intercalate ", " (map ejId ejes))
  let faccionAgente = FaccionId (read (opcion "--agente-faccion" "1"))
      conf = Config ancho alto carpeta vels (fmap (\a -> (faccionAgente, a, mregistro)) agente) (Entorno mapaR guion) ejes
  forM_ agente $ \_ -> registro ("agente externo para la facción " <> T.pack (opcion "--agente-faccion" "1"))
  ref <- newIORef Partida
    { pEstado = e0, pSiguiente = 0, pPendientes = [], pRespuestas = [], pDecisionesEnviadas = []
    , pVelocidad = velocidadNormal, pPausado = True
    , pVista = proyeccion juego e0 }
  if "--sin-cliente" `elem` args
    then sinCliente conf juego mapaR ref (read (opcion "--ticks" "360")) (opcion "--volcar" "") ("--metricas" `elem` args)
    else conCliente conf juego mapaR ref puerto
  forM_ mregistro hClose
  forM_ agente cerrarAgente

-- | Corre la partida sin cliente ni reloj real y, si se pide, vuelca la vista
-- final como una instantánea del protocolo.
sinCliente :: Config -> RJ.JuegoPurepecha -> Mapa -> IORef Partida -> Int -> FilePath -> Bool -> IO ()
sinCliente conf juego mapaR ref n volcar conMetricas = do
  forM_ [1 .. n] $ \_ -> avanzar conf juego mapaR ref
  p <- readIORef ref
  registro ("sin cliente: " <> T.pack (show n) <> " ticks, el estado está en el tick " <> T.pack (show (pSiguiente p - 1)))
  unless (null volcar) $ BL.writeFile volcar (aLinea (NInstantanea (relojDePartida p) (pVista p)) <> "\n")
  -- Las métricas del hito 0 sobre lo que presentó el director (V5, criterio del hito 0).
  when conMetricas $ do
    let dir = comunDirector (persistenteComun (estadoPersistente (pEstado p)))
        m = metricas (pdDiasDecada (guDirector (entGuion (cEntorno conf)))) n dir
    BL.putStr (A.encode (A.object
      [ "situaciones" A..= mTotal m, "por_tipo" A..= mPorTipo m
      , "parte_maxima" A..= mParteMaxima m, "novedades_por_decada" A..= mNovedades m
      , "cumple_criterio" A..= cumpleVariedad 0.25 2 m ]) <> "\n")

conCliente :: Config -> RJ.JuegoPurepecha -> Mapa -> IORef Partida -> String -> IO ()
conCliente conf juego mapaR ref puerto =
  bracket (abrir puerto) close $ \sock -> do
    registro ("núcleo escuchando en 127.0.0.1:" <> T.pack puerto
              <> " (protocolo v" <> T.pack (show versionProtocolo) <> ")")
    let aceptar = do
          (conn, _) <- accept sock
          registro "cliente conectado"
          sesion conf juego mapaR ref conn `finally` close conn
          registro "cliente desconectado; esperando otro"
          aceptar
    aceptar

abrir :: String -> IO Socket
abrir puerto = do
  let pistas = defaultHints { addrFlags = [AI_NUMERICHOST, AI_NUMERICSERV], addrSocketType = Stream }
  addr : _ <- getAddrInfo (Just pistas) (Just "127.0.0.1") (Just puerto)
  sock <- socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
  setSocketOption sock ReuseAddr 1
  bind sock (addrAddress addr)
  listen sock 1
  pure sock

registro :: T.Text -> IO ()
registro = TIO.hPutStrLn stderr . ("[núcleo] " <>)

-- ---------------------------------------------------------------------------
-- Sesión con un cliente
-- ---------------------------------------------------------------------------

data Config = Config
  { cAncho :: Int, cAlto :: Int, cPartidas :: FilePath, cVelocidades :: [Int]
  , cAgente :: Maybe (FaccionId, FuenteAgente, Maybe Handle)    -- ^ facción, fuente y registro
  , cEntorno :: Entorno
  , cEjes :: [Eje] }                                              -- ^ ejes activos del escenario

-- | Los comandos de un agente se numeran desde aquí, para distinguir sus
-- rechazos de los del jugador (que van al cliente).
secuenciaAgente :: Int
secuenciaAgente = 1000000

relojDePartida :: Partida -> Reloj
relojDePartida p = relojDe visible1475 inicio1475 (comunCalendario (persistenteComun (estadoPersistente (pEstado p))))
                     (pVelocidad p) (pPausado p) (Tick (max 0 (pSiguiente p - 1)))

-- | Un tick de la partida: si empieza un periodo, primero el turno del agente
-- externo (lo único con efectos), y después el paso puro. Devuelve la partida
-- de antes, la de después, los hechos y los rechazos.
avanzar :: Config -> RJ.JuegoPurepecha -> Mapa -> IORef Partida
        -> IO (Partida, Partida, [Hecho], [(Sellado Comando, Rechazo)], [(Respuesta, Rechazo)])
avanzar conf juego _mapa ref = do
  p <- readIORef ref
  let t = pSiguiente p
      cal = comunCalendario (persistenteComun (estadoPersistente (pEstado p)))
  deAgente <- if esInicioDePeriodo cal (Tick t) then turnoDelAgente conf juego p t else pure []
  let (e', hs, rechazos, rechazosR) = pasoCompleto juego (cEntorno conf) (Semilla 1475) (Tick t) (pPendientes p ++ deAgente) (pRespuestas p) (pEstado p)
      p' = p { pEstado = e', pSiguiente = t + 1, pPendientes = [], pRespuestas = [], pVista = proyeccion juego e' }
  writeIORef ref p'
  forM_ [ (s, m) | (s, Rechazo m) <- rechazos, sellSecuencia s >= secuenciaAgente ] $ \(_, m) ->
    registro ("agente: comando rechazado en el tick " <> T.pack (show t) <> ": " <> m)
  pure (p, p', hs, rechazos, rechazosR)

turnoDelAgente :: Config -> RJ.JuegoPurepecha -> Partida -> Int64 -> IO [Sellado Comando]
turnoDelAgente conf juego p t = case cAgente conf of
  Nothing -> pure []
  Just (f@(FaccionId n), fuente, mregistro) -> do
    -- En el prototipo el agente ve todo; en el juego completo, la vista de su facción.
    let turno = turnoAgente (Semilla 1475) f (Tick t) (relojDePartida p) (proyeccion juego (pEstado p))
    r <- pedirPlan fuente t turno
    forM_ mregistro $ \h -> BL.hPut h (lineaDeRegistro t n r) >> hFlush h
    forM_ (rMotivo r) $ \m -> registro ("agente, tick " <> T.pack (show t) <> ": " <> m)
    let crudos = maybe [] paComandos (rPlan r)
    fmap concat $ forM (zip [0 ..] crudos) $ \(i, v) -> case A.fromJSON v of
      A.Success c -> pure [Sellado (Tick t) f (secuenciaAgente + i) c]
      A.Error err -> do
        registro ("agente, tick " <> T.pack (show t) <> ": comando ilegible: " <> T.pack err)
        pure []

sesion :: Config -> RJ.JuegoPurepecha -> Mapa -> IORef Partida -> Socket -> IO ()
sesion conf juego mapaR ref conn = do
  h <- socketToHandle conn ReadWriteMode
  hSetBuffering h LineBuffering
  hSetBinaryMode h True
  entrada <- newIORef ([] :: [BC.ByteString])
  cerrado <- newIORef False
  -- Un hilo solo lee; el hilo principal es el único que escribe y el único que
  -- toca la partida.
  _ <- forkIO $ do
    let leer = do
          r <- try (BC.hGetLine h) :: IO (Either IOException BC.ByteString)
          case r of
            Left _  -> writeIORef cerrado True
            Right l -> atomicModifyIORef' entrada (\ls -> (ls ++ [l], ())) >> leer
    leer
  let enviar :: MensajeNucleo -> IO ()
      enviar m = do
        r <- try (BL.hPut h (aLinea m <> "\n") >> hFlush h) :: IO (Either IOException ())
        either (const (writeIORef cerrado True)) pure r
      -- Antes del primer tick, el reloj muestra el día 0 (1 de enero de 1475).
      reloj = relojDePartida
      bucle proximo = do
        fin <- readIORef cerrado
        unless fin $ do
          lineas <- atomicModifyIORef' entrada (\ls -> ([], ls))
          forM_ lineas (atender enviar reloj)
          ahora <- getMonotonicTimeNSec
          p <- readIORef ref
          let intervalo = fromIntegral (cVelocidades conf !! (pVelocidad p - 1)) * 1000000
          if pPausado p
            then threadDelay 10000 >> bucle (ahora + intervalo)
            else if ahora >= proximo
              then tick enviar reloj >> bucle (max (proximo + intervalo) ahora)
              else threadDelay 5000 >> bucle proximo
  t0 <- getMonotonicTimeNSec
  bucle t0
  where
    atender :: (MensajeNucleo -> IO ()) -> (Partida -> Reloj) -> BC.ByteString -> IO ()
    atender enviar reloj linea = case deLinea (BL.fromStrict linea) of
      Left err -> enviar (NError Nothing ("mensaje inválido: " <> err))
      Right (CHola v) -> case verificarVersion v of
        Left err -> enviar (NError Nothing err)
        Right () -> do
          p <- readIORef ref
          let v' = proyeccion juego (pEstado p)
          writeIORef ref p { pVista = v' }
          enviar (NHola versionProtocolo)
          enviar (NCatalogo (CatalogoCliente (declMagnitudes RJ.catalogoMag) catalogoComandos (cVelocidades conf)
                       (comunCalendario (persistenteComun (estadoPersistente (pEstado p)))) (cEjes conf)))
          enviar (NMapa (mapaCliente (cAncho conf) (cAlto conf) mapaR))
          enviar (NInstantanea (reloj p) v')
          modifyIORef' ref (\q -> q { pDecisionesEnviadas = [] })
          sincronizarDecisiones enviar
      Right (CComando sec v) -> case A.fromJSON v of
        A.Error err -> enviar (NError (Just sec) ("comando inválido: " <> T.pack err))
        A.Success c -> modifyIORef' ref $ \p ->
          -- Un comando dado en pausa durante el tick T se aplica en el tick T+1.
          p { pPendientes = pPendientes p ++ [Sellado (Tick (pSiguiente p)) faccionJugador sec c] }
      Right (CConsulta sec v) -> case A.fromJSON v of
        A.Error err -> enviar (NError (Just sec) ("comando inválido: " <> T.pack err))
        A.Success c -> do
          p <- readIORef ref
          let t = Tick (pSiguiente p)
          case consultar juego (cEntorno conf) (Semilla 1475) t (pPendientes p) (Sellado t faccionJugador sec c) (pEstado p) of
            Left (Rechazo motivo) -> enviar (NError (Just sec) motivo)
            Right (h, sinC, conC) ->
              enviar (NPrediccion sec h (diferencias (proyeccion juego sinC) (proyeccion juego conC)))
      Right (CControl (Guardar nombre)) -> case rutaPartida nombre of
        Nothing -> enviar (NError Nothing ("nombre de partida inválido: " <> nombre))
        Just r -> do
          p <- readIORef ref
          BL.writeFile r (A.encode (A.object
            [ "version_guardado" A..= (1 :: Int)
            , "siguiente" A..= pSiguiente p
            , "estado" A..= (A.decode (guardar (pEstado p)) :: Maybe A.Value) ]))
          registro ("partida guardada en " <> T.pack r)
          enviar (NAviso ("partida guardada: " <> nombre))
      Right (CControl (Cargar nombre)) -> case rutaPartida nombre of
        Nothing -> enviar (NError Nothing ("nombre de partida inválido: " <> nombre))
        Just r -> do
          existe <- doesFileExist r
          if not existe then enviar (NError Nothing ("no existe la partida: " <> nombre)) else do
            bs <- BL.readFile r
            let leido = do
                  o <- maybe (Left "archivo ilegible") Right (A.decode bs)
                  (sig, est) <- maybe (Left "faltan campos") Right (A.parseMaybe (\x -> A.withObject "partida" (\m -> (,) <$> m A..: "siguiente" <*> m A..: "estado") x) o)
                  e <- either (Left . T.pack . show) Right (cargar juego mapaR (A.encode (est :: A.Value)))
                  pure (sig, e)
            case leido of
              Left err -> enviar (NError Nothing ("no se pudo cargar " <> nombre <> ": " <> err))
              Right (sig, e) -> do
                -- La partida cargada empieza en pausa y sin comandos pendientes.
                modifyIORef' ref (\p -> p { pEstado = e, pSiguiente = sig, pPendientes = [], pPausado = True, pVista = proyeccion juego e })
                p <- readIORef ref
                enviar (NInstantanea (reloj p) (pVista p))
                sincronizarDecisiones enviar
                enviar (NAviso ("partida cargada: " <> nombre))
      Right (CResponder sec dec valor) ->
        modifyIORef' ref (\p -> p { pRespuestas = pRespuestas p ++ [Respuesta sec dec valor] })
      Right (CControl (Pausa b)) -> do
        modifyIORef' ref (\p -> p { pPausado = b })
        readIORef ref >>= enviar . NReloj . reloj
      Right (CControl (Velocidad n)) -> do
        modifyIORef' ref (\p -> p { pVelocidad = max 1 (min 5 n) })
        readIORef ref >>= enviar . NReloj . reloj

    -- Avisa al cliente de las decisiones nuevas y de las que ya no esperan
    -- respuesta (respondidas o vencidas), comparando con lo ya enviado.
    sincronizarDecisiones :: (MensajeNucleo -> IO ()) -> IO ()
    sincronizarDecisiones enviar = do
      p <- readIORef ref
      let com = persistenteComun (estadoPersistente (pEstado p))
          pendientes = comunDecisiones com
          plazos = edPlazos (comunDirector com)
          tipoDe sid = case [ siTipo x | x <- guSituaciones (entGuion (cEntorno conf)), siId x == sid ] of
                         (tp : _) -> tp
                         []       -> ""
          nuevas = [ dp | dp <- Map.elems pendientes, dpId dp `notElem` pDecisionesEnviadas p ]
          cerradas = [ i | i <- pDecisionesEnviadas p, not (Map.member i pendientes) ]
      forM_ nuevas $ \dp -> let sid = rnEvento (dpReanudacion dp) in
        enviar (NDecision (dpId dp) sid (tipoDe sid) (dpPregunta dp) (Map.lookup (dpId dp) plazos))
      forM_ cerradas (enviar . NDecisionCerrada)
      writeIORef ref p { pDecisionesEnviadas = Map.keys pendientes }

    -- Solo letras, dígitos, guion y guion bajo: el nombre no puede salir de la carpeta.
    rutaPartida nombre
      | not (T.null nombre) && T.all (\ch -> isAlphaNum ch || ch == '-' || ch == '_') nombre && T.length nombre <= 64
        = Just (cPartidas conf </> T.unpack nombre <.> "json")
      | otherwise = Nothing

    tick :: (MensajeNucleo -> IO ()) -> (Partida -> Reloj) -> IO ()
    tick enviar reloj = do
      (p, p', hs, rechazos, rechazosR) <- avanzar conf juego mapaR ref
      let t = pSiguiente p
      forM_ [ (s, m) | (s, Rechazo m) <- rechazos, sellSecuencia s < secuenciaAgente ] $ \(s, motivo) ->
        enviar (NError (Just (sellSecuencia s)) motivo)
      forM_ rechazosR $ \(r, Rechazo motivo) -> enviar (NError (Just (reSecuencia r)) motivo)
      enviar (NCambios (reloj p') (cambios (pVista p) (pVista p')) (hs :: [Hecho]))
      sincronizarDecisiones enviar
      when (t `mod` 20 == 0) $ registro ("tick " <> T.pack (show t))


-- | Termina con todos los errores de carga a la vista, o devuelve el valor.
validado :: Validacion a -> IO a
validado (Validacion [] (Just x)) = pure x
validado (Validacion errs _) = do
  mapM_ (\e -> registro (errArchivo e <> " " <> errRuta e <> ": " <> errMensaje e)) errs
  fail "error de carga"
