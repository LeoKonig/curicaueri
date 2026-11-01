{-# LANGUAGE StrictData, TypeFamilies, OverloadedStrings, LambdaCase, DeriveGeneric, DeriveAnyClass, DerivingStrategies #-}
module Main where

import Control.Monad (forM_, when)
import Data.Aeson (Value)
import qualified Data.Aeson as A
import Data.List (foldl', sort)
import Test.Hspec
import Test.QuickCheck
import qualified Data.IntMap.Strict as IntMap
import qualified Data.IntSet as IntSet
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Sequence as Seq

import Motor.Base
import Motor.Azar
import Motor.Magnitudes
import Motor.Estado
import Motor.Sistema
import Motor.Juego
import Motor.Hechos
import Motor.Vista
import Motor.Proyeccion
import Motor.Carga
import Motor.Efectos
import Motor.Agentes
import Motor.Mapa
import Motor.Guion
import Motor.Director
import Motor.Poblacion
import Motor.Protocolo
import Motor.Calendario
import Motor.Autoridad
import qualified Data.Aeson.Encode.Pretty as AP
import System.Environment (lookupEnv)
import System.IO.Unsafe (unsafePerformIO)
import Motor.Guardado
import Motor.Moneda
import Motor.Terrenos
import qualified Data.Aeson.KeyMap as KM
import GHC.Generics (Generic)
import qualified Data.ByteString.Lazy as BL
import Data.Set (Set)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Int (Int64)

fi :: Int -> Fijo
fi = Fijo . (* 10000) . fromIntegral

-- ---------------------------------------------------------------------------
-- Toy
-- ---------------------------------------------------------------------------

-- Los restos de migración son del juego, no del motor (documento funcional, sección 4).
data Aldeas = Aldeas { alIds :: [Int], alRestoMig :: Map.Map Int Fijo }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (A.ToJSON, A.FromJSON)

-- El derivado del juguete depende del estado (descontento total), para que
-- la ley del derivado reproducible no se cumpla por trivialidad.
type instance DerivadoDe Aldeas = Fijo
type instance PlanDe     Aldeas = ()

data ComandoJuguete
  = SubirImpuesto Int Fijo
  | ResponderSequia Int Int
  | CelebrarFiesta Int        -- −10 de descontento en esa aldea durante 3 veintenas
  | DesignarMonedaJ (Maybe Text)   -- la facción 1 designa (o retira) su moneda
  deriving (Eq, Show)

catalogoToy :: Map.Map Magnitud DefMagnitud
catalogoToy = Map.fromList
  [ (Magnitud "poblacion",
     DefMagnitud "poblacion" (RangoMag (Fijo 0) (fi 100000)) "m.poblacion" Nothing True)   -- cosecha y migración la escriben a propósito
  , (Magnitud "presion",
     DefMagnitud "presion" (RangoMag (Fijo 0) (fi 100)) "m.presion" Nothing False)
  , (Magnitud "descontento",
     DefMagnitud "descontento" (RangoMag (Fijo 0) (fi 100)) "m.descontento" Nothing False)
  ]

cosechaSistema :: Sistema Aldeas
cosechaSistema = Sistema
  { sisNombre   = NombreSistema "cosecha"
  , sisCadencia = Periodo
  , sisLee      = Set.empty
  , sisEscribe  = Set.singleton (Magnitud "poblacion")
  , sisEjecutar = \_ est ->
      let ids = alIds (persistenteJuego (estadoPersistente est))
          alm = comunMagnitudes (persistenteComun (estadoPersistente est))
          alm' = foldl' (\m i ->
                    sumarBase (EntRef "aldea" i) (Magnitud "poblacion") (fi 1) m)
                  alm ids
          com  = persistenteComun (estadoPersistente est)
          com' = com { comunMagnitudes = alm' }
      in (est { estadoPersistente = (estadoPersistente est)
                  { persistenteComun = com' } }, [])
  }

impuestoSistema :: Sistema Aldeas
impuestoSistema = Sistema
  { sisNombre   = NombreSistema "impuesto"
  , sisCadencia = Periodo
  , sisLee      = Set.empty
  , sisEscribe  = Set.singleton (Magnitud "descontento")
  , sisEjecutar = \_ est ->
      let ids = alIds (persistenteJuego (estadoPersistente est))
          alm = comunMagnitudes (persistenteComun (estadoPersistente est))
          alm' = foldl' (\m i ->
                    sumarBase (EntRef "aldea" i) (Magnitud "descontento") (fi 1) m)
                  alm ids
          com  = persistenteComun (estadoPersistente est)
          com' = com { comunMagnitudes = alm' }
      in (est { estadoPersistente = (estadoPersistente est)
                  { persistenteComun = com' } }, [])
  }

-- | Migración entre aldeas: la gente se va hacia donde hay menos descontento
-- (valor efectivo, así que una fiesta también atrae). Con κ pequeño el flujo
-- por veintena es menor que una persona: sin restos, nadie se movería nunca.
kappaMig :: Fijo
kappaMig = Fijo 5      -- 0,0005

migracionSistema :: Sistema Aldeas
migracionSistema = Sistema
  { sisNombre   = NombreSistema "migracion"
  , sisCadencia = Periodo
  , sisLee      = Set.fromList [Magnitud "poblacion", Magnitud "descontento"]
  , sisEscribe  = Set.singleton (Magnitud "poblacion")
  , sisEjecutar = \_ est ->
      let t    = estadoTick est
          jue  = persistenteJuego (estadoPersistente est)
          com  = persistenteComun (estadoPersistente est)
          alm  = comunMagnitudes com
          ids  = alIds jue
          mag i m = maybe (Fijo 0) id (Map.lookup (EntRef "aldea" i, Magnitud m) alm >>= \x ->
                      fmap (\dm -> valorEn (derivadoVigentes (estadoDerivado est)) t (dmRango dm) x) (Map.lookup (Magnitud m) catalogoToy))
          pob  = Map.fromList [ (i, parteEntera (mag i "poblacion")) | i <- ids ]
          desc i = mag i "descontento"
          flujos = Map.fromList
            [ (i, [ (j, kappaMig .*. max (Fijo 0) (desc i .-. desc j) .*. desdeEntero (pob Map.! i))
                  | j <- ids, j /= i ])
            | i <- ids ]
          (pob', restos') = migrar 1 pob (alRestoMig jue) flujos
          alm' = foldl' (\m (i, n) -> fijarBase (EntRef "aldea" i) (Magnitud "poblacion") (desdeEntero n) m)
                        alm (Map.toList pob')
      in ( est { estadoPersistente = Persistente com { comunMagnitudes = alm' }
                                                 jue { alRestoMig = restos' } }
         , [] )
  }

-- | Fuente de presión de ejemplo: cada veintena añade a la presión de la
-- frontera un modificador temporal (+intensidad durante 3 veintenas). Solo
-- corre en las fases que la activan. Al apagarse, sus modificadores expiran
-- solos y la presión vuelve a la base sin saltos.
fronteraSistema :: Sistema Aldeas
fronteraSistema = Sistema
  { sisNombre   = NombreSistema "frontera"
  , sisCadencia = Periodo
  , sisLee      = Set.empty
  , sisEscribe  = Set.singleton (Magnitud "presion")
  , sisEjecutar = \_ est ->
      let Tick t = estadoTick est
          m = Modificador 0 (Magnitud "presion") (EntRef "frontera" 1)
                (Aporte (intensidad "frontera" est) (Fijo 0)) (Fuente "frontera" "")
                (Just (Tick t)) (Just (Tick (t + 60))) Nothing AlcancePropia
          com = persistenteComun (estadoPersistente est)
          (alm', _) = agregarModificador m (comunMagnitudes com)
      in (est { estadoPersistente = (estadoPersistente est) { persistenteComun = com { comunMagnitudes = alm' } } }, [])
  }

proyectarAldeas :: Estado Aldeas -> [EntidadJuego]
proyectarAldeas est =
  let ids = alIds (persistenteJuego (estadoPersistente est))
  in [EntidadJuego (EntRef "aldea" i) Map.empty | i <- ids]

-- Efectos del evento Sequía: pide cuánto grano repartir, luego resta ese
-- grano del descontento de la aldea 1.

-- | Se compila igual que al cargar los datos: si el JSON de la sequía estuviera
-- mal escrito, las pruebas fallarían aquí y no a mitad de una partida.
sequiaPrograma :: Programa
sequiaPrograma = either (error . show) id (compilarPrograma efectosSequia)

-- | Guion mínimo para probar el vencimiento de una pregunta de cantidad. La
-- situación no se presenta sola: solo importa que la reanudación encuentre su
-- opción "" en el guion al vencer el plazo.
guionSequia :: Guion
guionSequia = guionVacio
  { guSituaciones = [ Situacion "sequia" "sequia" uno 0 0 [] Siempre [("", sequiaPrograma)] ]
  , guDirector = (guDirector guionVacio) { pdProbBase = Fijo 0 }
  }

descontentoTotal :: Persistente Aldeas -> Fijo
descontentoTotal p = foldl' (.+.) (Fijo 0)
  [ almacenBase x | ((_, m), x) <- Map.toList (comunMagnitudes (persistenteComun p))
                  , m == Magnitud "descontento" ]

avanzar :: [Int64] -> Estado Aldeas -> Estado Aldeas
avanzar ts s0 = foldl' (\e t -> fst (paso juguete entornoPrueba (Semilla 1) (Tick t) [] e)) s0 ts


-- ---------------------------------------------------------------------------
-- Archivos dorados del protocolo y del espejo
-- ---------------------------------------------------------------------------

-- | Compara un valor con su archivo dorado en pruebas_compartidas/. Con la
-- variable REGENERAR_DORADOS definida, en vez de comparar, lo escribe: así se
-- actualizan a propósito, nunca por accidente.
dorado :: FilePath -> A.Value -> Expectation
dorado nombre v = do
  regenerar <- lookupEnv "REGENERAR_DORADOS"
  let ruta = "../pruebas_compartidas/" ++ nombre
  case regenerar of
    Just _  -> BL.writeFile ruta (AP.encodePretty' AP.defConfig { AP.confCompare = compare } v <> "\n")
    Nothing -> do
      bs <- BL.readFile ruta
      A.decode bs `shouldBe` Just v

inicioJuguete :: Fecha
inicioJuguete = Fecha 1475 1 1

relojJuguete :: Estado Aldeas -> Reloj
relojJuguete e = relojDe SoloJuliano inicioJuguete (calendarioVeintenas 0) 3 False (estadoTick e)

comandosJuguete :: [DeclComando]
comandosJuguete =
  [ DeclComando "subir_impuesto" "c.subir_impuesto"
      [DeclParametro "aldea" (PEntero 1 2), DeclParametro "valor" (PEntero 0 20)] True requisitoPorOmision
  , DeclComando "celebrar_fiesta" "c.celebrar_fiesta" [DeclParametro "aldea" (PEntero 1 2)] True
      (Requisito "fe" Concurrente)
  , DeclComando "responder_sequia" "c.responder_sequia"
      [DeclParametro "decision" (PEntero 1 99), DeclParametro "grano" (PEntero 0 100)] True requisitoPorOmision
  , DeclComando "elegir_politica" "c.elegir_politica"
      [DeclParametro "politica" (POpcion ["tributo", "comercio"])] False requisitoPorOmision
  ]

-- | Ejes del juguete: dos, para que se note que el número de ejes es un dato.
ejesJugueteJSON :: Value
ejesJugueteJSON = A.object [ "ejes" A..=
  [ A.object ["id" A..= ("fuerza" :: Text), "magnitud" A..= ("aldea.fuerza" :: Text), "referencia" A..= ("100" :: Text)]
  , A.object ["id" A..= ("fe" :: Text), "magnitud" A..= ("aldea.fe" :: Text), "referencia" A..= ("50" :: Text), "base" A..= ("50" :: Text)] ] ]

ejesJuguete :: [Eje]
ejesJuguete = case cargarEjes "ejes_juguete" ejesJugueteJSON of
  Validacion [] (Just es) -> es
  v -> error ("los ejes del juguete no cargan: " <> show (valErrores v))

conFiesta :: Estado Aldeas
conFiesta = case aplicarCola juguete [Sellado (Tick 5) (FaccionId 1) 0 (CelebrarFiesta 1)] (avanzar [0..4] estadoInicial) of
  (e, _, _) -> e

sinAldea2 :: Estado Aldeas -> Estado Aldeas
sinAldea2 e = e { estadoPersistente = (estadoPersistente e)
                    { persistenteJuego = (persistenteJuego (estadoPersistente e)) { alIds = [1] } } }

-- | Un caso del espejo: instantánea antes, cambios, instantánea esperada después.
casoEspejo :: Text -> Estado Aldeas -> Estado Aldeas -> [Hecho] -> A.Value
casoEspejo nombre a b hs =
  let va = proyeccion juguete a
      vb = proyeccion juguete b
  in A.object [ "nombre" A..= nombre
              , "instantanea" A..= NInstantanea (relojJuguete a) va
              , "cambios" A..= NCambios (relojJuguete b) (cambios va vb) hs
              , "esperado" A..= NInstantanea (relojJuguete b) vb ]

pasoConHechos :: Int64 -> Estado Aldeas -> (Estado Aldeas, [Hecho])
pasoConHechos t = paso juguete entornoPrueba (Semilla 1) (Tick t) []


-- ---------------------------------------------------------------------------
-- Guion del juguete: tres fases (consolidación, frontera, crisis)
-- ---------------------------------------------------------------------------

guionJuguete :: Guion
guionJuguete = unsafeGuion

{-# NOINLINE unsafeGuion #-}
unsafeGuion :: Guion
unsafeGuion = case A.decode guionBytes >>= \v -> valValor (cargarGuion "guion_juguete.json" inicioJuguete v) of
  Just g  -> g
  Nothing -> error "test/guion_juguete.json no carga"

guionBytes :: BL.ByteString
guionBytes = unsafePerformIO (BL.readFile "test/guion_juguete.json")
{-# NOINLINE guionBytes #-}

entornoGuion :: Entorno
entornoGuion = Entorno mapaPrueba guionJuguete economiaVacia

avanzarCon :: Entorno -> [Int64] -> Estado Aldeas -> (Estado Aldeas, [Hecho])
avanzarCon ent ts s0 = foldl' (\(e, hs) t -> let (e', h) = paso juguete ent (Semilla 1) (Tick t) [] e in (e', hs ++ h)) (s0, []) ts

presionEn :: Estado Aldeas -> Fijo
presionEn e = maybe (Fijo 0) (valorEn (derivadoVigentes (estadoDerivado e)) (estadoTick e) (RangoMag (Fijo 0) (fi 100)))
  (Map.lookup (EntRef "frontera" 1, Magnitud "presion") (comunMagnitudes (persistenteComun (estadoPersistente e))))

directorDe :: Estado Aldeas -> EstadoDirector
directorDe = comunDirector . persistenteComun . estadoPersistente

conPlazo :: Int -> Tick -> Estado Aldeas -> Estado Aldeas
conPlazo i t e =
  let p = estadoPersistente e
      c = persistenteComun p
      d = comunDirector c
  in e { estadoPersistente = p { persistenteComun = c { comunDirector = d { edPlazos = Map.singleton i t } } } }

efectosSequia :: [Value]
efectosSequia =
  [ A.object
      [ "tipo"     A..= ("elegir_cantidad" :: String)
      , "variable" A..= ("grano" :: String)
      , "min"      A..= (0 :: Int)
      , "max"      A..= (100 :: Int) ]
  , A.object
      [ "tipo"      A..= ("restar_mag_var" :: String)
      , "entidad"   A..= A.object
          [ "clase" A..= ("aldea" :: String)
          , "id"    A..= (1 :: Int) ]
      , "magnitud"  A..= ("descontento" :: String)
      , "var"       A..= ("grano" :: String) ]
  ]

aplicarCmdJuguete :: Estado Aldeas -> Sellado ComandoJuguete
                  -> Either Rechazo (Estado Aldeas, [Hecho])
aplicarCmdJuguete est sell = case sellCmd sell of
  SubirImpuesto _ f
    | f < Fijo 0 -> Left (Rechazo "impuesto negativo")
    | otherwise  ->
        let alm = comunMagnitudes (persistenteComun (estadoPersistente est))
            alm' = sumarBase (EntRef "aldea" 1)
                             (Magnitud "descontento") f alm   -- subir el impuesto sube el descontento
            com  = persistenteComun (estadoPersistente est)
            com' = com { comunMagnitudes = alm' }
        in Right (est { estadoPersistente = (estadoPersistente est)
                          { persistenteComun = com' } }, [])

  ResponderSequia d n
    | n < 0 -> Left (Rechazo "respuesta negativa")
    | otherwise ->
        case Map.lookup d (comunDecisiones (persistenteComun (estadoPersistente est))) of
          Nothing -> Left (Rechazo "decisión no encontrada")
          Just dp ->
            let est0 = quitarDecision d est
                r    = reanudar (CEntero n) dp sequiaPrograma est0
            in case r of
                 Completado (_, e, hs)     -> Right (e, hs)
                 Suspendido _ _ (e, hs)    -> Right (e, hs)
                 Fallo msg                 -> Left (Rechazo msg)

  CelebrarFiesta i
    | i `notElem` alIds (persistenteJuego (estadoPersistente est)) -> Left (Rechazo "aldea inexistente")
    | otherwise ->
        let Tick t = sellTick sell
            m = Modificador 0 (Magnitud "descontento") (EntRef "aldea" i)
                  (Aporte (fi (-10)) (Fijo 0)) (Fuente "fiesta" "")
                  (Just (Tick t)) (Just (Tick (t + 60))) Nothing AlcancePropia
            com = persistenteComun (estadoPersistente est)
            (alm', _) = agregarModificador m (comunMagnitudes com)
        in Right (est { estadoPersistente = (estadoPersistente est)
                          { persistenteComun = com { comunMagnitudes = alm' } } }, [])

  DesignarMonedaJ m -> case designarMoneda economiaJuguete faccionJ m (sellTick sell) est of
    Left motivo -> Left (Rechazo motivo)
    Right r     -> Right r

juguete :: Juego Aldeas ComandoJuguete
juguete = Juego
  { juegoSistemas    = [cosechaSistema, impuestoSistema, migracionSistema, fronteraSistema]
  , juegoAplicarCmd  = aplicarCmdJuguete
  , juegoDerivar     = \_ _ p -> descontentoTotal p
  , juegoProyectar   = proyectarAldeas
  , juegoAgentes     = Map.empty
  , juegoCatalogoMag = catalogoToy
  }

estadoInicial :: Estado Aldeas
estadoInicial = Estado
  { estadoTick        = Tick 0
  , estadoPersistente = persist
  , estadoOrigen      = Origen (Tick 0) persist
  , estadoDerivado    = Derivado mempty (descontentoTotal persist)
  }
  where
    aldeas = Aldeas [1, 2] Map.empty
    mags = Map.fromList
      [ ((EntRef "aldea" 1, Magnitud "poblacion"),   AlmacenMag (fi 100) [])
      , ((EntRef "aldea" 2, Magnitud "poblacion"),   AlmacenMag (fi 200) [])
      , ((EntRef "aldea" 1, Magnitud "descontento"), AlmacenMag (fi 50)  [])
      , ((EntRef "aldea" 2, Magnitud "descontento"), AlmacenMag (fi 50)  [])
      , ((EntRef "frontera" 1, Magnitud "presion"),  AlmacenMag (fi 0)   [])
      ]
    persist = Persistente
      { persistenteComun = Comun
          { comunMagnitudes = mags
          , comunDecisiones = Map.empty
          , comunPlanes     = Map.empty
          , comunCronica    = Seq.empty
          , comunCalendario = calendarioVeintenas 0
          , comunDirector   = directorInicial
          , comunMonedas    = Map.empty
          }
      , persistenteJuego = aldeas
      }

baseMag :: Int -> Magnitud -> Estado Aldeas -> Maybe Fijo
baseMag i m est =
  almacenBase <$> Map.lookup (EntRef "aldea" i, m)
    (comunMagnitudes (persistenteComun (estadoPersistente est)))

-- ---------------------------------------------------------------------------
-- Generador para el agente aleatorio
-- ---------------------------------------------------------------------------

genCmd :: Rng -> ComandoJuguete
genCmd r =
  let (u, _) = uniforme r
      n = fromIntegral (unFijo u) :: Int
  in if even n
       then SubirImpuesto 1 (fi (n `mod` 5 - 2))    -- puede ser negativo
       else ResponderSequia (n `mod` 3) (n `mod` 100)  -- puede no encontrar decisión

-- ---------------------------------------------------------------------------
-- main
-- ---------------------------------------------------------------------------

main :: IO ()
main = hspec $ do
  describe "Fijo" $ do
    it "suma"            $ (Fijo 10000 .+. Fijo 10000) `shouldBe` Fijo 20000
    it "resta"           $ (Fijo 30000 .-. Fijo 10000) `shouldBe` Fijo 20000
    it "multiplicación"  $ (Fijo 20000 .*. Fijo 30000) `shouldBe` Fijo 60000
    it "división"        $ (Fijo 20000 ./. Fijo 40000) `shouldBe` Fijo 5000
    it "precedencia: 1 + 2 · 3 = 7, como con + y *" $
      (fi 1 .+. fi 2 .*. fi 3) `shouldBe` fi 7
    it "desdeDecimal 3"  $ desdeDecimal "3"     `shouldBe` Right (Fijo 30000)
    it "desdeDecimal 1.5" $ desdeDecimal "1.5"  `shouldBe` Right (Fijo 15000)
    it "desdeDecimal -2.25" $ desdeDecimal "-2.25" `shouldBe` Right (Fijo (-22500))
    it "rechaza 5 decimales" $
      isLeft (desdeDecimal "1.55555") `shouldBe` True

  describe "Aporte (monoide)" $ do
    it "conmutativo" $ property $ \(Small a1) (Small p1) (Small a2) (Small p2) ->
      let x = Aporte (Fijo a1) (Fijo p1)
          y = Aporte (Fijo a2) (Fijo p2)
      in (x <> y) == (y <> x)
    it "identidad" $
      let a = Aporte (Fijo 100) (Fijo 200)
      in (a <> mempty) `shouldBe` a

  describe "valorEfectivo" $ do
    it "sin mods = base" $
      valorEfectivo (RangoMag (Fijo 0) (Fijo 100000)) (Fijo 5000) []
        `shouldBe` Fijo 5000
    it "con sumando + porcentaje" $ do
      let m = Modificador 1 (Magnitud "x") (EntRef "e" 1)
                          (Aporte (Fijo 1000) (Fijo 1000))
                          (Fuente "t" "r") Nothing Nothing Nothing AlcancePropia
      -- (5000 + 1000) * (1 + 0.1) = 6600
      valorEfectivo (RangoMag (Fijo 0) (Fijo 100000)) (Fijo 5000) [m]
        `shouldBe` Fijo 6600
    it "clamp al techo" $ do
      let m = Modificador 1 (Magnitud "x") (EntRef "e" 1)
                          (Aporte (Fijo 100000) (Fijo 0))
                          (Fuente "t" "r") Nothing Nothing Nothing AlcancePropia
      valorEfectivo (RangoMag (Fijo 0) (Fijo 10000)) (Fijo 5000) [m]
        `shouldBe` Fijo 10000

  describe "rng" $ do
    it "determinista" $ do
      let (u1, _) = uniforme (rng (Semilla 42) "x" (Tick 0))
          (u2, _) = uniforme (rng (Semilla 42) "x" (Tick 0))
      u1 `shouldBe` u2
    it "semilla distinta da distinto" $ do
      let (u1, _) = uniforme (rng (Semilla 42) "x" (Tick 0))
          (u2, _) = uniforme (rng (Semilla 43) "x" (Tick 0))
      u1 `shouldNotBe` u2

  describe "calendario" $ do
    it "veintena / nemontemi / año" $ do
      esInicioDePeriodo cv (Tick 0)    `shouldBe` True
      esInicioDePeriodo cv (Tick 20)   `shouldBe` True
      esInicioDePeriodo cv (Tick 360)  `shouldBe` False
      ipFuera (infoPeriodo cv (Tick 360)) `shouldBe` True
      esInicioDeAnio cv (Tick 365)       `shouldBe` True

  describe "exp y ln" $ do
    it "exp 0 = 1"     $ expFijo (Fijo 0)       `shouldBe` Fijo 10000
    it "exp 1 ≈ e"     $ cerca 2 (expFijo (Fijo 10000))   27183 `shouldBe` True
    it "exp 0,5"       $ cerca 2 (expFijo (Fijo 5000))    16487 `shouldBe` True
    it "exp (-1)"      $ cerca 2 (expFijo (Fijo (-10000))) 3679 `shouldBe` True
    it "ln 2"          $ lnFijo (Fijo 20000) `shouldBe` Right (Fijo 6931)
    -- tolerancia: 5 unidades más el error de cuantizar e^x (10000 / e^x unidades de ln)
    it "ln (exp x) ≈ x" $ property $ \(Small k) ->
      let x = (k `mod` 50000) - 25000 :: Int
          Fijo e = expFijo (Fijo (fromIntegral x))
      in e > 0 ==> either (const False) (\(Fijo l) -> abs (l - fromIntegral x) <= 5 + 10000 `div` e) (lnFijo (Fijo e))

  describe "mapa" $ do
    it "el proveedor hexagonal produce un mapa válido" $
      validarMapa mapaPrueba `shouldBe` []
    it "validarMapa detecta una conexión asimétrica" $ do
      let m = mapaPrueba { mapaVecinos = IntMap.adjust (const []) 0 (mapaVecinos mapaPrueba) }
      any esAsimetrica (validarMapa m) `shouldBe` True

  describe "asignación de celdas" $ do
    -- mapaPrueba es hexagonal de 5 × 4 con 1,0 km por celda: dos celdas vecinas están a 1 km.
    let km n = Fijo (n * 10000)
        asig r fs = IntMap.toList (asignarCeldas r mapaPrueba [ (AsentId a, CeldaId c) | (a, c) <- fs ])
        -- Reasigna a cada conexión una longitud de 0 a 3 km, la misma en los dos sentidos
        -- (depende solo del par de celdas), para que haya empates y conexiones de longitud 0.
        reponderar sem m = m { mapaVecinos = IntMap.mapWithKey (\a vs ->
          [ (CeldaId b, con { connCosto = Fijo (fromIntegral ((min a b * 7 + max a b * 13 + sem) `mod` 4) * 10000) })
          | (CeldaId b, con) <- vs ]) (mapaVecinos m) }
        -- La definición, sin Dijkstra: la distancia de cada fuente a cada celda por
        -- relajación repetida, y para cada celda el mínimo de (distancia, id) dentro del radio.
        fuerzaBruta radio m fs = IntMap.fromList
          [ (c, AsentId a)
          | c <- IntMap.keys (mapaCeldas m)
          , let cands = [ (d, a) | (AsentId a, CeldaId f) <- fs
                                 , Just d <- [IntMap.lookup c (distDesde m f)], d <= radio ]
          , not (null cands)
          , let (_, a) = minimum cands ]
        distDesde m f = iterate (relajar m) (IntMap.singleton f (Fijo 0)) !! IntMap.size (mapaCeldas m)
        relajar m ds = IntMap.unionWith min ds (IntMap.fromListWith min
          [ (b, d .+. connCosto con) | (a, d) <- IntMap.toList ds
                                        , (CeldaId b, con) <- IntMap.findWithDefault [] a (mapaVecinos m) ])
        casoAzar = do
          w <- choose (1, 5); h <- choose (1, 4); sem <- choose (0, 1000)
          let m = either (error . show) (reponderar sem) (proveedorHexagonal (DatosHex w h (km 1) 1))
              n = w * h
          k <- choose (1, min 4 n)
          celdas <- vectorOf k (choose (0, n - 1))
          ids <- vectorOf k (choose (1, 50))
          radio <- Fijo . (* 5000) <$> choose (0, 16)
          pure (m, zip ids celdas, radio)
    it "el proveedor hexagonal pone a cada conexión la escala como longitud y como costo" $
      all (\con -> connLongitud con == mapaEscala mapaPrueba && connCosto con == mapaEscala mapaPrueba)
          [ con | vs <- IntMap.elems (mapaVecinos mapaPrueba), (_, con) <- vs ]
        `shouldBe` True
    it "ley: coincide con el mínimo por fuerza bruta en mapas pequeños, con empates y conexiones de longitud 0" $
      property $ forAll casoAzar $ \(m, fs, radio) ->
        asignarCeldas radio m [ (AsentId a, CeldaId c) | (a, c) <- fs ]
          == fuerzaBruta radio m [ (AsentId a, CeldaId c) | (a, c) <- fs ]
    it "con radio 0, solo la celda del asentamiento" $
      asig (km 0) [(1, 7)] `shouldBe` [(7, AsentId 1)]
    it "con radio de un paso, la celda y sus vecinas" $
      map fst (asig (km 1) [(1, 0)]) `shouldBe` [0, 1, 5]
    it "las celdas a más de R km de todo asentamiento no se asignan" $
      (lookup 19 (asig (km 1) [(1, 0)]), lookup 19 (asig (km 100) [(1, 0)]))
        `shouldBe` (Nothing, Just (AsentId 1))
    it "el empate lo rompe el id menor, sin importar el orden de la lista" $ do
      lookup 1 (asig (km 1) [(9, 0), (3, 2)]) `shouldBe` Just (AsentId 3)
      lookup 1 (asig (km 1) [(3, 2), (9, 0)]) `shouldBe` Just (AsentId 3)
    it "dos asentamientos en la misma celda: gana el id menor" $
      lookup 4 (asig (km 1) [(8, 4), (2, 4)]) `shouldBe` Just (AsentId 2)
    it "un asentamiento cuya celda no existe se ignora" $
      asig (km 1) [(1, 999)] `shouldBe` []
    it "cada celda va al más cercano, no al primero que llega" $
      -- celda 3 está a 1 km de la 2 y a 3 km de la 0
      lookup 3 (asig (km 3) [(1, 0), (2, 2)]) `shouldBe` Just (AsentId 2)

  describe "tabla de terrenos" $ do
    let archivoReal = unsafePerformIO (BL.readFile "../datos/terrenos.json")
        tablaReal = case A.decode archivoReal of
          Just v -> cargarTerrenos "terrenos.json" v
          Nothing -> error "datos/terrenos.json no es JSON"
        terrenosMalos = A.object [ "terrenos" A..=
          [ A.object ["id" A..= ("llano" :: Text), "capacidad" A..= ("10" :: Text), "erosion" A..= ("0.5" :: Text)]
          , A.object ["id" A..= ("llano" :: Text), "capacidad" A..= ("3" :: Text), "erosion" A..= ("0" :: Text)]
          , A.object ["id" A..= ("bosque" :: Text), "capacidad" A..= ("-1" :: Text), "erosion" A..= ("0" :: Text)]
          , A.object ["id" A..= ("sierra" :: Text), "capacidad" A..= ("4" :: Text), "erosion" A..= ("-0.2" :: Text)]
          , A.object ["id" A..= ("lago" :: Text), "capacidad" A..= ("6" :: Text), "erosion" A..= ("0" :: Text)
                     , "recursos" A..= (["pescado", "pescado"] :: [Text])] ] ]
    it "el archivo del repositorio carga sin errores" $
      valErrores tablaReal `shouldBe` []
    it "declara los cuatro terrenos que genera el proveedor hexagonal" $
      fmap Map.keys (valValor tablaReal)
        `shouldBe` Just [Terreno "bosque", Terreno "lago", Terreno "llano", Terreno "sierra"]
    it "cubre todos los terrenos de un mapa hexagonal, también uno grande" $ do
      let Just t = valValor tablaReal
          grande = either (error . show) id (proveedorHexagonal (DatosHex 60 45 (fi 5) 1))
      (valErrores (validarTerrenosDelMapa "terrenos.json" t mapaPrueba), valErrores (validarTerrenosDelMapa "terrenos.json" t grande))
        `shouldBe` ([], [])
    it "capacidad y erosión salen de la tabla, con valores no negativos" $ do
      let Just t = valValor tablaReal
      all (\d -> dtCapacidad d >= Fijo 0 && dtErosion d >= Fijo 0) (Map.elems t) `shouldBe` True
      fmap dtCapacidad (Map.lookup (Terreno "llano") t) `shouldBe` Just (fi 10)
    it "acumula todos los errores: terreno repetido, capacidad y erosión negativas, recurso repetido" $
      map errMensaje (valErrores (cargarTerrenos "malo.json" terrenosMalos))
        `shouldBe` [ "terreno repetido", "la capacidad no puede ser negativa"
                   , "la erosión no puede ser negativa", "recurso repetido" ]
    it "un terreno del mapa que la tabla no declara se rechaza al cargar, con su nombre" $ do
      let Just t = valValor tablaReal
          sinLago = Map.delete (Terreno "lago") t
      map (\e -> (errCategoria e, errRuta e)) (valErrores (validarTerrenosDelMapa "terrenos.json" sinLago mapaPrueba))
        `shouldBe` [(ErrorReferencia, "terrenos.lago")]

  describe "azar estable" $
    it "valor dorado: si cambia, cambió el generador y se rompen las repeticiones guardadas" $
      fst (uniforme (rng (Semilla 42) "cosecha" (Tick 7))) `shouldBe` Fijo 1255


  describe "sistemas escriben magnitudes" $ do
    it "cosecha sube poblacion en veintena" $ do
      let s = fst (paso juguete entornoPrueba (Semilla 1) (Tick 0) [] estadoInicial)
      baseMag 1 (Magnitud "poblacion") s `shouldBe` Just (fi 101)
    it "nemontemi no corre veintena" $ do
      let s = foldl' (\s t -> fst (paso juguete entornoPrueba (Semilla 1) (Tick t) [] s))
                    estadoInicial [0..19]
      -- solo el tick 0 corrió cosecha; el 20 no se ha ejecutado
      baseMag 1 (Magnitud "poblacion") s `shouldBe` Just (fi 101)

  describe "agente nulo" $ do
    it "no emite comandos y la partida avanza" $ do
      let j = juguete { juegoAgentes =
                          Map.singleton (FaccionId 1) (agenteNulo ()) }
          s = foldl' (\s t -> fst (paso j entornoPrueba (Semilla 1) (Tick t) [] s))
                    estadoInicial [0..9]
      baseMag 1 (Magnitud "poblacion") s `shouldBe` Just (fi 101)

  describe "agente aleatorio" $ do
    it "misma semilla, misma traza" $ do
      let j = juguete { juegoAgentes =
                          Map.singleton (FaccionId 1)
                            (agenteAleatorio () 3 genCmd) }
          traza s0 = foldl' (\s t -> fst (paso j entornoPrueba (Semilla 7) (Tick t) [] s))
                            s0 [0..20]
          a = traza estadoInicial
          b = traza estadoInicial
      comunMagnitudes (persistenteComun (estadoPersistente a))
        `shouldBe` comunMagnitudes (persistenteComun (estadoPersistente b))

    it "rechazos no dañan el estado" $ do
      let sell = Sellado (Tick 0) (FaccionId 1) 0 (SubirImpuesto 1 (Fijo (-1000)))
          (s', _, rs) = aplicarCola juguete [sell] estadoInicial
      case rs of
        [Rechazo _] -> pure ()
        _           -> expectationFailure "se esperaba un rechazo"
      comunMagnitudes (persistenteComun (estadoPersistente s'))
        `shouldBe` comunMagnitudes (persistenteComun (estadoPersistente estadoInicial))

  describe "suspensión y reanudación" $ do
    let estadoSuspendido =
          let r = interpretar "sequia" "" sequiaPrograma 0 Map.empty estadoInicial
              id' = siguienteId estadoInicial
          in aplicarResultado id' r estadoInicial

    it "el evento seca el estado en Suspendido con una decisión" $ do
      Map.size (comunDecisiones (persistenteComun (estadoPersistente estadoSuspendido)))
        `shouldBe` 1

    it "reanudar con 40 resta 40 al descontento" $ do
      let Just dp = Map.lookup 1
                      (comunDecisiones (persistenteComun (estadoPersistente estadoSuspendido)))
          est'   = quitarDecision 1 estadoSuspendido
          r      = reanudar (CEntero 40) dp sequiaPrograma est'
      case r of
        Completado (_, e, _) ->
          baseMag 1 (Magnitud "descontento") e `shouldBe` Just (fi 10)
        _ -> expectationFailure "se esperaba Completado"

    it "responde por comando como cualquier otro" $ do
      let Just dpId = Map.lookupMin
                        (comunDecisiones (persistenteComun (estadoPersistente estadoSuspendido)))
                        >>= \(k, _) -> Just k
          sell = Sellado (Tick 0) (FaccionId 1) 0 (ResponderSequia dpId 30)
      case aplicarCmdJuguete estadoSuspendido sell of
        Right (e, _) ->
          baseMag 1 (Magnitud "descontento") e `shouldBe` Just (fi 20)
        Left r -> expectationFailure ("rechazo inesperado: " ++ show r)

    it "al vencer una pregunta de cantidad se aplica el mínimo y no queda pendiente" $ do
      let Just dpId = Map.lookupMin
                        (comunDecisiones (persistenteComun (estadoPersistente estadoSuspendido)))
                        >>= \(k, _) -> Just k
          e0 = conPlazo dpId (Tick 0) estadoSuspendido
          (e', hs) = pasoDirector catalogoToy guionSequia (Rng 1) (Tick 0) e0
      Map.member dpId (comunDecisiones (persistenteComun (estadoPersistente e'))) `shouldBe` False
      [ v | h <- hs, hechoTipo h == "plazo_vencido", Just v <- [Map.lookup "opcion" (hechoParams h)] ]
        `shouldBe` ["0"]
      baseMag 1 (Magnitud "descontento") e' `shouldBe` Just (fi 50)

  describe "rechazo de comando invalido" $ do
    it "impuesto negativo" $ do
      let sell = Sellado (Tick 0) (FaccionId 1) 0 (SubirImpuesto 1 (fi (-1)))
      isLeft (aplicarCmdJuguete estadoInicial sell) `shouldBe` True
  describe "proyeccion" $ do
    it "una entidad por aldea" $ do
      let v = proyeccion juguete estadoInicial
      Map.size (vEntidades v) `shouldBe` 2
    it "tick refleja el del estado" $ do
      let v = proyeccion juguete estadoInicial
      vTick v `shouldBe` Tick 0

  describe "espejo" $ do
    let s1 = fst (paso juguete entornoPrueba (Semilla 1) (Tick 20) [] estadoInicial)
        v0 = proyeccion juguete estadoInicial
        v1 = proyeccion juguete s1

    it "conmutación: aplicar v (cambios v v') == v'" $
      aplicar v0 (cambios v0 v1) `shouldBe` v1

    it "completitud: toda entidad cambiada aparece" $ do
      let c = cambios v0 v1
          actualizadas = Set.fromList (map evRef (cActualizadas c))
          eliminadas   = Set.fromList (cEliminadas c)
          cambia r = Map.lookup r (vEntidades v0)
                     /= Map.lookup r (vEntidades v1)
          refs = Map.keys (vEntidades v0) ++ Map.keys (vEntidades v1)
      forM_ refs $ \r ->
        when (cambia r) $
          (Set.member r actualizadas || Set.member r eliminadas)
            `shouldBe` True

    it "las dos aldearon su población" $ do
      let al = persistenteJuego (estadoPersistente s1)
      baseMag 1 (Magnitud "poblacion") s1 `shouldBe` Just (fi 101)
      baseMag 2 (Magnitud "poblacion") s1 `shouldBe` Just (fi 201)

  describe "carga" $ do
    it "versión futura se rechaza" $ do
      let v = A.object ["version_esquema" A..= (99 :: Int)]
          r = cargarDatos [("f.json", v)]
      null (valErrores r) `shouldBe` False
      valValor r `shouldBe` Nothing

    it "versión actual se acepta" $ do
      let v = A.object ["version_esquema" A..= (1 :: Int)]
          r = cargarDatos [("f.json", v)]
      valErrores r `shouldBe` []
      (valValor r :: Maybe Catalogo) `shouldSatisfy` (/= Nothing)

    it "campo version_esquema ausente es error" $ do
      let v = A.object ["otra" A..= (1 :: Int)]
          r = cargarDatos [("f.json", v)]
      null (valErrores r) `shouldBe` False

    it "personalidad fuera de rango se rechaza" $ do
      let p = Personalidad "x" 200 (Fijo 0)
          r = validarPersonalidad p
      null (valErrores r) `shouldBe` False
  describe "FromJSON Fijo" $ do
    it "entero en string"       $ (A.decode "\"3\"" :: Maybe Fijo) `shouldBe` Just (Fijo 30000)
    it "decimal en string"      $ (A.decode "\"1.5\"" :: Maybe Fijo) `shouldBe` Just (Fijo 15000)
    it "número JSON entero"     $ (A.decode "3" :: Maybe Fijo) `shouldBe` Just (Fijo 30000)
    it "número JSON decimal"    $ (A.decode "1.5" :: Maybe Fijo) `shouldBe` Just (Fijo 15000)
    it "rechaza 5 decimales"    $ (A.decode "\"1.55555\"" :: Maybe Fijo) `shouldBe` Nothing

  describe "FromJSON RangoMag" $ do
    it "objeto con min y max" $
      (A.decode "{\"min\":\"0\",\"max\":\"100\"}" :: Maybe RangoMag)
        `shouldBe` Just (RangoMag (Fijo 0) (Fijo 1000000))

  describe "FromJSON DefMagnitud" $ do
    it "con defaults" $ do
      let j = A.object
            [ "id"    A..= ("tesoro"    :: Text)
            , "rango" A..= A.object
                [ "min" A..= ("0"     :: Text)
                , "max" A..= ("10000" :: Text) ]
            , "clave" A..= ("m.tesoro" :: Text) ]
          r = A.decode (A.encode j) :: Maybe DefMagnitud
      r `shouldBe` Just
        (DefMagnitud "tesoro"
                     (RangoMag (Fijo 0) (Fijo 100000000))
                     "m.tesoro" Nothing False)

  describe "FromJSON Personalidad" $ do
    it "acepta" $
      (A.decode
        "{\"id\":\"triple_alianza\",\"agresividad\":70,\"umbral_ataque\":\"1.3\"}"
        :: Maybe Personalidad)
        `shouldBe` Just (Personalidad "triple_alianza" 70 (Fijo 13000))

  describe "validarOrdenSistemas" $ do
    let mX   = Magnitud "x"
        sysA = mkSys (NombreSistema "a") Diario   Set.empty (Set.singleton mX)
        sysB = mkSys (NombreSistema "b") Periodo Set.empty (Set.singleton mX)
        sysC = mkSys (NombreSistema "c") Diario   (Set.singleton mX) Set.empty

    it "dos escritores = error" $
      validarOrdenSistemas Map.empty [sysA, sysB]
        `shouldBe` [EscrituraDuplicada (NombreSistema "a") (NombreSistema "b") mX]

    it "lector antes que escritor = warning" $
      validarOrdenSistemas Map.empty [sysC, sysA]
        `shouldBe` [LecturaDeTicAnterior (NombreSistema "c") (NombreSistema "a") mX]

    it "lector después del escritor = sin aviso" $
      validarOrdenSistemas Map.empty [sysA, sysC]
        `shouldBe` []

    it "magnitud multi-escritor no es error" $ do
      let cat = Map.singleton mX
                  (DefMagnitud "x" (RangoMag (Fijo 0) (Fijo 1))
                                "m.x" Nothing True)
      validarOrdenSistemas cat [sysA, sysB] `shouldBe` []

    it "tres escritores = tres avisos dos a dos" $ do
      let sysD = mkSys (NombreSistema "d") Anual Set.empty (Set.singleton mX)
          r    = validarOrdenSistemas Map.empty [sysA, sysB, sysD]
      length r `shouldBe` 3

  describe "cambiosOpt ≡ cambiosRef" $ do
    -- Pares de estados que cubren: sin cambio, cambio en una entidad,
    -- cambio en varias, eliminación y reaparición (tick vuelve a un
    -- estado con la aldea de nuevo).
    let paso1  = fst (paso juguete entornoPrueba (Semilla 1) (Tick 1)  [] estadoInicial)
        paso20 = fst (paso juguete entornoPrueba (Semilla 1) (Tick 20) [] estadoInicial)
        paso40 = fst (paso juguete entornoPrueba (Semilla 1) (Tick 20) []
                      paso20)
        sElim  = estadoInicial
          { estadoPersistente = (estadoPersistente estadoInicial)
              { persistenteJuego = Aldeas [1] Map.empty } }
        pares =
          [ ("s0 → s0",             estadoInicial, estadoInicial)
          , ("s0 → tick 1",         estadoInicial, paso1)
          , ("s0 → tick 20",        estadoInicial, paso20)
          , ("s20 → s40",           paso20,       paso40)
          , ("s0 → s con aldea 2 eliminada", estadoInicial, sElim)
          , ("s con aldea 2 eliminada → s0", sElim,  estadoInicial)
          ]

    forM_ pares $ \(nombre, s0, s1) -> it ("coinciden · " ++ nombre) $ do
      let v0 = proyeccion juguete s0
          v1 = proyeccion juguete s1
          cOpt = cambiosOpt (todasLasEntidades v1) v0 v1
          cRef = cambiosRef v0 v1
      cOpt `shouldBe` cRef

    it "óptima con sucias = cambiadas: aplicar da v1" $ do
      let s0 = estadoInicial
          s1 = fst (paso juguete entornoPrueba (Semilla 1) (Tick 20) [] estadoInicial)
          v0 = proyeccion juguete s0
          v1 = proyeccion juguete s1
          cambiadas = Set.fromList
            [evRef e | e <- cActualizadas (cambiosRef v0 v1)]
          cOpt = cambiosOpt cambiadas v0 v1
      aplicar v0 cOpt `shouldBe` v1

    it "óptima con sucias = eliminadas también funciona" $ do
      let s0 = estadoInicial
          s1 = estadoInicial
            { estadoPersistente = (estadoPersistente estadoInicial)
                { persistenteJuego = Aldeas [1] Map.empty } }
          v0 = proyeccion juguete s0
          v1 = proyeccion juguete s1
          -- El registro de sucias en este caso solo tiene a la aldea 1
          -- (la que cambió), y la eliminación de la 2 se detecta por
          -- iteración de claves viejas.
          sucias = Set.singleton (EntRef "aldea" 1)
          c = cambiosOpt sucias v0 v1
      cEliminadas c `shouldBe` [EntRef "aldea" 2]
      aplicar v0 c `shouldBe` v1

  describe "carga: secciones" $ do
    let archivo cs = A.object ["version_esquema" A..= (1 :: Int), "constantes" A..= A.object cs]
    it "las constantes válidas se cargan" $
      fmap catConstantes (valValor (cargarDatos [("c.json", archivo ["TASA" A..= ("0.02" :: String)])]))
        `shouldBe` Just (Map.fromList [("TASA", Fijo 200)])
    it "dos constantes inválidas dan dos errores, no una sección vacía en silencio" $
      length (valErrores (cargarDatos [("c.json", archivo
        [ "TASA" A..= ("0.02" :: String), "MAL1" A..= ("0.123456" :: String), "MAL2" A..= True ])]))
        `shouldBe` 2
    it "con dos archivos, el último gana" $
      fmap catConstantes (valValor (cargarDatos
        [ ("a.json", archivo ["TASA" A..= ("0.02" :: String)])
        , ("b.json", archivo ["TASA" A..= ("0.05" :: String)]) ]))
        `shouldBe` Just (Map.fromList [("TASA", Fijo 500)])

  describe "calendario en el ciclo" $
    it "un año: 18 veintenas y ningún paso de veintena en nemontemi" $ do
      let s = foldl' (\e t -> fst (paso juguete entornoPrueba (Semilla 1) (Tick t) [] e)) estadoInicial [0..364]
      baseMag 1 (Magnitud "poblacion") s `shouldBe` Just (fi 118)

  describe "comandos del juguete" $
    it "subir el impuesto sube el descontento" $ do
      let sell = Sellado (Tick 0) (FaccionId 1) 0 (SubirImpuesto 1 (fi 5))
      fmap (baseMag 1 (Magnitud "descontento") . fst) (aplicarCmdJuguete estadoInicial sell)
        `shouldBe` Right (Just (fi 55))


  describe "efectos compilados al cargar" $ do
    it "un evento bien escrito se compila en el catálogo" $ do
      let f = A.object [ "version_esquema" A..= (1 :: Int)
                       , "eventos" A..= [A.object [ "id" A..= ("sequia" :: Text)
                           , "opciones" A..= [A.object ["id" A..= ("repartir" :: Text), "efectos" A..= efectosSequia]] ]] ]
      fmap (Map.lookup ("sequia", "repartir") . catProgramas) (valValor (cargarDatos [("e.json", f)]))
        `shouldBe` Just (Just sequiaPrograma)
    it "un efecto desconocido detiene la carga con su ruta" $ do
      let f = A.object [ "version_esquema" A..= (1 :: Int)
                       , "eventos" A..= [A.object [ "id" A..= ("sequia" :: Text)
                           , "opciones" A..= [A.object ["id" A..= ("x" :: Text), "efectos" A..= [A.object ["tipo" A..= ("inventado" :: Text)]]]] ]] ]
      map errRuta (valErrores (cargarDatos [("e.json", f)])) `shouldBe` ["eventos.sequia.opciones.x"]

  describe "guardar y cargar" $ do
    let estSusp = aplicarResultado (siguienteId estadoInicial)
                    (interpretar "sequia" "" sequiaPrograma 0 Map.empty estadoInicial) estadoInicial
    it "ida y vuelta con una decisión pendiente" $ do
      let Right e' = cargar juguete mapaPrueba (guardar estSusp)
      comunDecisiones (persistenteComun (estadoPersistente e'))
        `shouldBe` comunDecisiones (persistenteComun (estadoPersistente estSusp))
      comunMagnitudes (persistenteComun (estadoPersistente e'))
        `shouldBe` comunMagnitudes (persistenteComun (estadoPersistente estSusp))
    it "responder después de cargar da lo mismo que sin guardar" $ do
      let sell = Sellado (Tick 0) (FaccionId 1) 0 (ResponderSequia 1 40)
          Right e' = cargar juguete mapaPrueba (guardar estSusp)
      fmap (baseMag 1 (Magnitud "descontento") . fst) (aplicarCmdJuguete e' sell)
        `shouldBe` fmap (baseMag 1 (Magnitud "descontento") . fst) (aplicarCmdJuguete estSusp sell)
    it "un guardado corrupto falla con ErrorEstructura" $
      fmap (const ()) (cargar juguete mapaPrueba (BL.pack [0xff, 0x00]))
        `shouldSatisfy` either ((== ErrorEstructura) . errCategoria) (const False)
    -- La misma partida con otra versión escrita en el guardado.
    let conVersion n bs = case A.decode bs of
          Just (A.Object o) -> A.encode (A.Object (KM.insert "version" (A.toJSON (n :: Int)) o))
          _                 -> bs
        errorDe = either Just (const Nothing) . cargar juguete mapaPrueba
    it "un guardado de la versión anterior se rechaza con ErrorVersion y dice qué hacer" $ do
      let Just e = errorDe (conVersion (versionGuardado - 1) (guardar estSusp))
      errCategoria e `shouldBe` ErrorVersion
      errMensaje e `shouldSatisfy` T.isInfixOf ("versión " <> T.pack (show (versionGuardado - 1)))
      errMensaje e `shouldSatisfy` T.isInfixOf "No hay migración"
      errMensaje e `shouldSatisfy` T.isInfixOf "empieza una nueva"
    it "un guardado de una versión posterior se rechaza y pide actualizar el juego" $ do
      let Just e = errorDe (conVersion (versionGuardado + 1) (guardar estSusp))
      errCategoria e `shouldBe` ErrorVersion
      errMensaje e `shouldSatisfy` T.isInfixOf "actualiza el juego"
    it "un guardado sin versión falla con ErrorEstructura, no con ErrorVersion" $ do
      let sinVersion bs = case A.decode bs of
            Just (A.Object o) -> A.encode (A.Object (KM.delete "version" o))
            _                 -> bs
          Just e = errorDe (sinVersion (guardar estSusp))
      errCategoria e `shouldBe` ErrorEstructura
    it "el guardado de ahora lleva la versión que lee" $
      fmap (const ()) (cargar juguete mapaPrueba (conVersion versionGuardado (guardar estSusp)))
        `shouldBe` Right ()

  describe "ley del derivado a mitad de veintena" $ do
    -- Paso 16 en el día 20; un comando en el día 23 cambia el descontento;
    -- se guarda el día 25, a mitad de la veintena.
    let s20  = avanzar [0..20] estadoInicial
        s23  = case aplicarCola juguete [Sellado (Tick 23) (FaccionId 1) 0 (SubirImpuesto 1 (fi 7))] (avanzar [21..22] s20) of
                 (e, _, _) -> e
        s25  = avanzar [23..25] s23
        Right cargado = cargar juguete mapaPrueba (guardar s25)
    it "el derivado cargado es el que tenía la partida" $
      derivadoJuego (estadoDerivado cargado) `shouldBe` derivadoJuego (estadoDerivado s25)
    it "recalcularlo desde el persistente actual daría otro valor (lo que el origen evita)" $
      descontentoTotal (estadoPersistente s25) `shouldNotBe` derivadoJuego (estadoDerivado s25)
    it "la partida cargada sigue igual que la original hasta la siguiente veintena y después" $
      comunMagnitudes (persistenteComun (estadoPersistente (avanzar [26..60] cargado)))
        `shouldBe` comunMagnitudes (persistenteComun (estadoPersistente (avanzar [26..60] s25)))


  describe "ruta: modificador que expira" $ do
    let s5   = case aplicarCola juguete [Sellado (Tick 5) (FaccionId 1) 0 (CelebrarFiesta 1)] (avanzar [0..4] estadoInicial) of
                 (e, _, _) -> e
        efectivo t e = (\x -> valorEn (derivadoVigentes (estadoDerivado e)) (Tick t) (RangoMag (Fijo 0) (fi 100)) x) <$>
                         Map.lookup (EntRef "aldea" 1, Magnitud "descontento") (comunMagnitudes (persistenteComun (estadoPersistente e)))
        base e = baseMag 1 (Magnitud "descontento") e
        correrConHechos ts e0 = foldl' (\(e, hs) t -> let (e', h) = paso juguete entornoPrueba (Semilla 1) (Tick t) [] e in (e', hs ++ h)) (e0, []) ts
        (s64, _)   = correrConHechos [5..64] s5
        (s65, h65) = correrConHechos [65] s64
    it "mientras dura, el valor efectivo es la base menos 10" $
      ((.-.) <$> base s64 <*> efectivo 64 s64) `shouldBe` Just (fi 10)
    it "la vista muestra el aporte y cuándo vence" $
      fmap (map avVence . mvAportes) (Map.lookup (Magnitud "descontento")
        . evMagnitudes =<< Map.lookup (EntRef "aldea" 1) (vEntidades (proyeccion juguete s64)))
        `shouldBe` Just [Just (Tick 65)]
    it "al vencer emite modificador_terminado con su entidad" $
      [ (hechoTipo h, hechoEntidades h) | h <- h65, hechoTipo h == "modificador_terminado" ]
        `shouldBe` [("modificador_terminado", [EntRef "aldea" 1])]
    it "y el valor vuelve solo a su base, sin regla de decaimiento" $
      efectivo 65 s65 `shouldBe` base s65
    it "el modificador ya no está en el almacén" $
      fmap almacenMods (Map.lookup (EntRef "aldea" 1, Magnitud "descontento") (comunMagnitudes (persistenteComun (estadoPersistente s65))))
        `shouldBe` Just []
    it "guardar y cargar conserva el modificador activo" $ do
      let Right e' = cargar juguete mapaPrueba (guardar s64)
      comunMagnitudes (persistenteComun (estadoPersistente e'))
        `shouldBe` comunMagnitudes (persistenteComun (estadoPersistente s64))
    it "dos modificadores reciben ids distintos" $ do
      let m = Modificador 0 (Magnitud "x") (EntRef "e" 1) mempty (Fuente "t" "") Nothing Nothing Nothing AlcancePropia
          (a1, i1) = agregarModificador m Map.empty
          (_,  i2) = agregarModificador m a1
      (i1, i2) `shouldBe` (1, 2)

  describe "modificadores condicionales" $ do
    -- Aldea 1 empieza con 100 de población y la cosecha le suma 1 por veintena,
    -- así que tras los pasos de los días 0, 20, 40 y 60 tiene 101, 102, 103 y 104.
    -- Las veintenas empiezan en los días múltiplos de 20.
    let pobAldea1 = (EntRef "aldea" 1, Magnitud "poblacion")
        descAldea1 = (EntRef "aldea" 1, Magnitud "descontento")
        condMas10 c = Modificador 0 (Magnitud "descontento") (EntRef "aldea" 1)
                        (Aporte (fi 10) (Fijo 0)) (Fuente "prueba" "condicional")
                        Nothing Nothing (Just c) AlcancePropia
        -- El estado inicial con el modificador ya en el almacén, y su derivado y su origen
        -- calculados de nuevo, como los dejaría el paso 16.
        conMod c =
          let p0 = estadoPersistente estadoInicial
              com = persistenteComun p0
              (alm, _) = agregarModificador (condMas10 c) (comunMagnitudes com)
              p1 = p0 { persistenteComun = com { comunMagnitudes = alm } }
          in estadoInicial { estadoPersistente = p1
                           , estadoOrigen = Origen (Tick 0) p1
                           , estadoDerivado = derivar juguete mapaPrueba (Tick 0) p1 }
        efectivoDesc e = (\x -> valorEn (derivadoVigentes (estadoDerivado e)) (estadoTick e) (RangoMag (Fijo 0) (fi 100)) x)
                           <$> Map.lookup descAldea1 (comunMagnitudes (persistenteComun (estadoPersistente e)))
        baseDesc = baseMag 1 (Magnitud "descontento")
        aporteDeCondicion e = (.-.) <$> efectivoDesc e <*> baseDesc e
        corre ts e0 = foldl' (\(e, hs) t -> let (e', h) = pasoConHechos t e in (e', hs ++ h)) (e0, []) ts
        masDe103 = Mayor (EntRef "aldea" 1) (Magnitud "poblacion") (fi 103)
        modsDe e = maybe [] almacenMods (Map.lookup descAldea1 (comunMagnitudes (persistenteComun (estadoPersistente e))))
        terminadosPorCondicion hs = [ hechoTick h | h <- hs, hechoTipo h == "modificador_terminado"
                                                  , Map.lookup "razon" (hechoParams h) == Just "condicion" ]
        sMas = fst (corre [0..60] (conMod masDe103))
    it "cuenta solo cuando se cumple su condición: población > 103" $ do
      aporteDeCondicion (fst (corre [0..59] (conMod masDe103))) `shouldBe` Just (Fijo 0)
      aporteDeCondicion sMas `shouldBe` Just (fi 10)
    it "la población que decide es la de los días 0, 20, 40 y 60 (la premisa de las pruebas)" $
      almacenBase <$> Map.lookup pobAldea1 (comunMagnitudes (persistenteComun (estadoPersistente sMas)))
        `shouldBe` Just (fi 104)
    it "los vigentes son ids de modificadores condicionales; sin condicionales, el conjunto es vacío" $ do
      IntSet.size (derivadoVigentes (estadoDerivado sMas)) `shouldBe` 1
      derivadoVigentes (estadoDerivado (avanzar [0..60] estadoInicial)) `shouldBe` IntSet.empty
    it "un modificador sin condición cuenta aunque no esté entre los vigentes" $ do
      let m = (condMas10 Siempre) { modCondicion = Nothing }
      (cuentaEn IntSet.empty (Tick 0) m, cuentaEn IntSet.empty (Tick 0) (condMas10 Siempre)) `shouldBe` (True, False)
    it "una condición que se cumple no salta la ventana del modificador" $ do
      let m = (condMas10 Siempre) { modId = 7, modInicio = Just (Tick 10) }
      (cuentaEn (IntSet.singleton 7) (Tick 9) m, cuentaEn (IntSet.singleton 7) (Tick 10) m) `shouldBe` (False, True)
    it "la vista solo muestra el aporte condicional mientras está vigente" $ do
      let aportes e = fmap (length . mvAportes) (Map.lookup (Magnitud "descontento")
            . evMagnitudes =<< Map.lookup (EntRef "aldea" 1) (vEntidades (proyeccion juguete e)))
      (aportes (fst (corre [0..59] (conMod masDe103))), aportes sMas) `shouldBe` (Just 0, Just 1)
    -- Una condición que deja de cumplirse y vuelve: verdadera hasta el día 39 (y no desde el 40
    -- hasta el 99), y otra vez verdadera desde el 100.
    let intermitente = Alguna [No (DesdeTick 40), DesdeTick 100]
        (s39, hs39)   = corre [0..39] (conMod intermitente)
        (s40, hs40)   = corre [40] s39
        (s99, hs99)   = corre [41..99] s40
        (s100, hs100) = corre [100] s99
    it "mientras se cumple, cuenta" $
      aporteDeCondicion s39 `shouldBe` Just (fi 10)
    it "al dejar de cumplirse emite modificador_terminado con la razón condicion, y deja de contar" $ do
      terminadosPorCondicion (hs39 ++ hs40) `shouldBe` [Tick 40]
      aporteDeCondicion s40 `shouldBe` Just (Fijo 0)
    it "no se borra: sigue en el almacén y no vuelve a anunciarse mientras no cambie" $ do
      length (modsDe s99) `shouldBe` 1
      terminadosPorCondicion hs99 `shouldBe` []
      aporteDeCondicion s99 `shouldBe` Just (Fijo 0)
    it "puede volver a cumplirse y vuelve a contar" $ do
      aporteDeCondicion s100 `shouldBe` Just (fi 10)
      terminadosPorCondicion hs100 `shouldBe` []
    it "un modificador condicional no vigente en la primera derivación no anuncia nada" $
      terminadosPorCondicion (snd (corre [0..39] (conMod masDe103))) `shouldBe` []
    it "no se anuncia dos veces si además vence: al expirar solo emite `expiro`" $ do
      let conFin = (conMod intermitente)
          p0 = estadoPersistente conFin
          com = persistenteComun p0
          alm = Map.adjust (\x -> x { almacenMods = [ m { modFin = Just (Tick 40) } | m <- almacenMods x ] })
                  descAldea1 (comunMagnitudes com)
          p1 = p0 { persistenteComun = com { comunMagnitudes = alm } }
          e0 = conFin { estadoPersistente = p1, estadoOrigen = Origen (Tick 0) p1
                      , estadoDerivado = derivar juguete mapaPrueba (Tick 0) p1 }
          (_, hs) = corre [0..40] e0
      [ Map.lookup "razon" (hechoParams h) | h <- hs, hechoTipo h == "modificador_terminado" ]
        `shouldBe` [Just "expiro"]
    it "guardar y cargar a mitad de veintena conserva la condición y los vigentes" $ do
      let s65 = fst (corre [61..65] sMas)
          Right cargado = cargar juguete mapaPrueba (guardar s65)
      modCondicion <$> modsDe cargado `shouldBe` [Just masDe103]
      derivadoVigentes (estadoDerivado cargado) `shouldBe` derivadoVigentes (estadoDerivado s65)
      aporteDeCondicion cargado `shouldBe` aporteDeCondicion s65
    it "y la partida cargada sigue igual que la original, incluida la vuelta de la condición" $ do
      let Right cargado = cargar juguete mapaPrueba (guardar s99)
      comunMagnitudes (persistenteComun (estadoPersistente (avanzar [100..130] cargado)))
        `shouldBe` comunMagnitudes (persistenteComun (estadoPersistente (avanzar [100..130] s99)))
      derivadoVigentes (estadoDerivado (avanzar [100] cargado)) `shouldBe` derivadoVigentes (estadoDerivado s100)
    it "toda condición sobrevive a guardar y cargar" $ do
      let todas = Todas [ Siempre, Mayor (EntRef "aldea" 1) (Magnitud "poblacion") (fi 3)
                        , Menor (EntRef "aldea" 2) (Magnitud "descontento") (Fijo 5)
                        , No (DesdeTick 40), Alguna [DesdeTick 1, Siempre] ]
          e = conMod todas
          Right cargado = cargar juguete mapaPrueba (guardar e)
      modCondicion <$> modsDe cargado `shouldBe` [Just todas]
    it "un guardado sin condición (campo nulo) sigue cargando" $ do
      let Right cargado = cargar juguete mapaPrueba (guardar (avanzar [0..30] conFiesta))
      modCondicion <$> modsDe cargado `shouldBe` [Nothing]

  describe "ruta: población con restos" $ do
    it "crecer con resto: 0,1 persona por paso suma 1 cada 10 pasos" $
      fst (foldl' (\(n, r) _ -> crecerConResto 1 (Fijo 10) n r) (100, Fijo 0) [1 .. 10 :: Int])
        `shouldBe` 101
    it "sin resto, el mismo crecimiento se perdería" $
      foldl' (\n _ -> fst (crecerConResto 1 (Fijo 10) n (Fijo 0))) (100 :: Int) [1 .. 10 :: Int]
        `shouldBe` 100
    it "migrar con flujo constante de 0,3: 3 personas en 10 veintenas" $ do
      let pob0 = Map.fromList [(1 :: Int, 100), (2, 100)]
          fl   = Map.fromList [(1, [(2, Fijo 3000)])]
          (pobF, _) = foldl' (\(p, r) _ -> migrar 1 p r fl) (pob0, Map.empty) [1 .. 10 :: Int]
      pobF `shouldBe` Map.fromList [(1, 97), (2, 103)]
    it "mayor resto: 10 entre tres pesos iguales da 4, 3, 3 (empate por clave)" $
      repartirMayorResto 10 [(1 :: Int, uno), (2, uno), (3, uno)] `shouldBe` [(1, 4), (2, 3), (3, 3)]
    it "ley: el reparto suma exactamente el total" $ property $ \(NonNegative tot) ws ->
      let pesos = zip [1 :: Int ..] [ Fijo (fromIntegral (abs w `mod` 100000)) | w <- (ws :: [Int]) ]
          r = repartirMayorResto tot pesos
      in any ((> Fijo 0) . snd) pesos ==> sum (map snd r) == tot
    it "ley: cada clave recibe el piso o el techo de su cuota" $ property $ \(NonNegative tot) ws ->
      let pesos = zip [1 :: Int ..] [ Fijo (fromIntegral (abs w `mod` 100000)) | w <- (ws :: [Int]) ]
          den   = sum [ toInteger w | (_, Fijo w) <- pesos ]
          ok (k, q) = let Fijo w = maybe (Fijo 0) id (lookup k pesos)
                          (c, rr) = (toInteger tot * toInteger w) `divMod` den
                      in toInteger q == c || (rr > 0 && toInteger q == c + 1)
      in den > 0 ==> all ok (repartirMayorResto tot pesos)
    it "ley: migrar conserva la población y respeta el piso" $ property $ \ns fs ->
      let pob = Map.fromList (zip [1 :: Int ..] [ 1 + abs n `mod` 5000 | n <- take 6 (ns :: [Int]) ])
          ks  = Map.keys pob
          fl  = Map.fromList [ (i, [ (j, Fijo (fromIntegral (abs f `mod` 2000000))) | (j, f) <- zip ks (fs :: [Int]), j /= i ]) | i <- ks ]
          (pob', _) = migrar 1 pob Map.empty fl
      in sum (Map.elems pob') == sum (Map.elems pob) && all (>= 1) (Map.elems pob')
    it "en el juguete: con más descontento en la aldea 1, la gente se va a la 2 y el total se conserva" $ do
      let s10 = case aplicarCola juguete [Sellado (Tick 10) (FaccionId 1) 0 (SubirImpuesto 1 (fi 20))] (avanzar [0..9] estadoInicial) of
                  (e, _, _) -> e
          sF  = avanzar [10..730] s10
          p i e = maybe 0 parteEntera (baseMag i (Magnitud "poblacion") e)
      (p 1 sF < p 1 s10 + 36, p 2 sF > p 2 s10 + 36) `shouldBe` (True, True)
      p 1 sF + p 2 sF `shouldBe` p 1 s10 + p 2 s10 + 2 * 36   -- 36 veintenas de cosecha, +1 por aldea

  describe "el reloj del estado" $
    it "después de procesar los ticks 0 a 9, el estado está en el tick 9" $
      estadoTick (avanzar [0..9] estadoInicial) `shouldBe` Tick 9

  describe "el juguete pasa el validador de orden" $
    it "sin avisos: poblacion tiene escritores múltiples declarados" $
      validarOrdenSistemas catalogoToy (juegoSistemas juguete) `shouldBe` []


  describe "autoridad: requisitos y ejes" $ do
    it "el requisito por omisión es {eje: todo, clase: exclusivo}, y un objeto vacío lo da" $ do
      A.toJSON requisitoPorOmision `shouldBe` A.object ["eje" A..= ("todo" :: Text), "clase" A..= ("exclusivo" :: Text)]
      A.fromJSON (A.object []) `shouldBe` A.Success requisitoPorOmision
      A.fromJSON (A.object ["clase" A..= ("concurrente" :: Text)]) `shouldBe` A.Success (Requisito "todo" Concurrente)
    it "los ejes se cargan en orden, con la base por omisión en 100" $ do
      map ejId ejesJuguete `shouldBe` ["fuerza", "fe"]
      map ejBase ejesJuguete `shouldBe` [desdeEntero 100, desdeEntero 50]
    it "la carga acumula todos los errores: repetido, «todo» reservado, referencia no positiva" $ do
      let malo = A.object [ "ejes" A..=
            [ A.object ["id" A..= ("fe" :: Text), "magnitud" A..= ("m" :: Text), "referencia" A..= ("50" :: Text)]
            , A.object ["id" A..= ("fe" :: Text), "magnitud" A..= ("m" :: Text), "referencia" A..= ("50" :: Text)]
            , A.object ["id" A..= ("todo" :: Text), "magnitud" A..= ("m" :: Text), "referencia" A..= ("0" :: Text)] ] ]
      length (valErrores (cargarEjes "malo" malo)) `shouldBe` 3
    it "ejes activos: sin lista, todos; con lista, solo esos; un id desconocido es error" $ do
      valValor (ejesActivos "esc" ejesJuguete Nothing) `shouldBe` Just ejesJuguete
      fmap (map ejId) (valValor (ejesActivos "esc" ejesJuguete (Just ["fe"]))) `shouldBe` Just ["fe"]
      length (valErrores (ejesActivos "esc" ejesJuguete (Just ["fe", "comercio"]))) `shouldBe` 1
    it "cada requisito del catálogo nombra «todo» o un eje declarado" $ do
      let reqs = [ (dcTipo d, dcRequiere d) | d <- comandosJuguete ]
      valErrores (validarRequisitos "cat" ejesJuguete reqs) `shouldBe` []
      map errRuta (valErrores (validarRequisitos "cat" [] reqs)) `shouldBe` ["comandos.celebrar_fiesta.requiere"]

  describe "protocolo: archivos dorados del núcleo" $ do
    let s64 = avanzar [5..64] conFiesta
        (s65, h65) = pasoConHechos 65 s64
    it "hola"        $ dorado "protocolo/hola.json" (A.toJSON (NHola versionProtocolo))
    it "catalogo"    $ dorado "protocolo/catalogo.json"
                         (A.toJSON (NCatalogo (CatalogoCliente (declMagnitudes catalogoToy) comandosJuguete [3000, 1500, 1000, 500, 150] (calendarioVeintenas 0) ejesJuguete)))
    it "mapa"        $ dorado "protocolo/mapa.json" (A.toJSON (NMapa (mapaCliente 5 4 mapaPrueba)))
    it "instantanea" $ dorado "protocolo/instantanea.json"
                         (A.toJSON (NInstantanea (relojJuguete s64) (proyeccion juguete s64)))
    it "cambios"     $ dorado "protocolo/cambios.json"
                         (A.toJSON (NCambios (relojJuguete s65) (cambios (proyeccion juguete s64) (proyeccion juguete s65)) h65))
    it "reloj"       $ dorado "protocolo/reloj.json" (A.toJSON (NReloj (relojDe SoloJuliano inicioJuguete (calendarioVeintenas 0) 2 True (Tick 365))))
    it "error"       $ dorado "protocolo/error.json" (A.toJSON (NError (Just 7) "impuesto negativo"))
    it "aviso"       $ dorado "protocolo/aviso.json" (A.toJSON (NAviso "partida guardada: partida1"))
    it "decision"    $ dorado "protocolo/decision.json"
                         (A.toJSON (NDecision 3 "incursion" "frontera" (PreguntaOpcion "opcion" ["resistir", "pagar_tributo"]) (Just (Tick 4100))))
    it "decision con cantidad" $ dorado "protocolo/decision_cantidad.json"
                         (A.toJSON (NDecision 4 "sequia" "tierra" (PreguntaCantidad "grano" 0 100) (Just (Tick 4120))))
    it "decision_cerrada" $ dorado "protocolo/decision_cerrada.json" (A.toJSON (NDecisionCerrada 3))
    it "prediccion"  $ case consultar juguete entornoPrueba (Semilla 1) (Tick 10) [] (Sellado (Tick 10) (FaccionId 1) 8 (SubirImpuesto 1 (fi 5))) (avanzar [0..9] estadoInicial) of
      Left r -> expectationFailure (show r)
      Right (h, a, b) -> dorado "protocolo/prediccion.json"
                           (A.toJSON (NPrediccion 8 h (diferencias (proyeccion juguete a) (proyeccion juguete b))))

  describe "consulta" $ do
    let s9 = avanzar [0..9] estadoInicial
        sell n = Sellado (Tick 10) (FaccionId 1) 8 (SubirImpuesto 1 (fi n))
    it "predice hasta la siguiente veintena" $
      fmap (\(h, _, _) -> h) (consultar juguete entornoPrueba (Semilla 1) (Tick 10) [] (sell 5) s9) `shouldBe` Right (Tick 20)
    it "la diferencia es exactamente el efecto del comando" $
      fmap (\(_, a, b) -> [ (dNombre d, dAntes d, dDespues d) | d <- diferencias (proyeccion juguete a) (proyeccion juguete b) ])
           (consultar juguete entornoPrueba (Semilla 1) (Tick 10) [] (sell 5) s9)
        `shouldBe` Right [("descontento", Just (VFijo (fi 52)), Just (VFijo (fi 57)))]   -- 50 + veintenas 0 y 20; +5 del comando
    it "un comando inválido se rechaza en la consulta, como al aplicarlo" $
      fmap (const ()) (consultar juguete entornoPrueba (Semilla 1) (Tick 10) [] (sell (-1)) s9) `shouldBe` Left (Rechazo "impuesto negativo")


  describe "protocolo: archivos dorados del cliente" $ do
    let leer n = BL.readFile ("../pruebas_compartidas/protocolo/" ++ n)
        esperados =
          [ ("cliente_hola.json", CHola versionProtocolo)
          , ("cliente_comando.json", CComando 7 (A.object ["tipo" A..= ("subir_impuesto" :: Text), "aldea" A..= (1 :: Int), "valor" A..= (5 :: Int)]))
          , ("cliente_pausa.json", CControl (Pausa False))
          , ("cliente_velocidad.json", CControl (Velocidad 5))
          , ("cliente_consulta.json", CConsulta 8 (A.object ["tipo" A..= ("subir_impuesto" :: Text), "aldea" A..= (1 :: Int), "valor" A..= (5 :: Int)]))
          , ("cliente_guardar.json", CControl (Guardar "partida1"))
          , ("cliente_cargar.json", CControl (Cargar "partida1"))
          , ("cliente_responder.json", CResponder 9 3 "resistir") ]
    forM_ esperados $ \(n, m) -> it n $ do
      regenerar <- lookupEnv "REGENERAR_DORADOS"
      case regenerar of
        Just _  -> BL.writeFile ("../pruebas_compartidas/protocolo/" ++ n) (AP.encodePretty' AP.defConfig { AP.confCompare = compare } m <> "\n")
        Nothing -> (deLinea <$> leer n) `shouldReturn` Right m
    it "un mensaje desconocido se rechaza con su nombre" $
      (deLinea "{\"tipo\":\"teletransportar\"}" :: Either Text MensajeCliente)
        `shouldSatisfy` either (T.isInfixOf "teletransportar") (const False)
    it "la versión distinta se rechaza" $
      verificarVersion (versionProtocolo + 1) `shouldSatisfy` isLeft

  describe "calendario visible" $ do
    it "el tick 0 es la fecha de inicio" $ fechaDelTick (Fecha 1475 1 1) (Tick 0) `shouldBe` Fecha 1475 1 1
    it "1476 es bisiesto en el juliano: 366 días después del 1 de enero de 1476 es 1 de enero de 1477" $
      fechaDelTick (Fecha 1476 1 1) (Tick 366) `shouldBe` Fecha 1477 1 1
    it "ida y vuelta del día juliano" $ property $ \(NonNegative n) ->
      let f = desdeDiaJuliano (2260000 + n `mod` 100000) in desdeDiaJuliano (diaJuliano f) == f
    it "día 0: veintena 1, día 1, faltan 20" $ infoPeriodo cv (Tick 0) `shouldBe` InfoPeriodo False 1 1 20
    it "día 359: veintena 18, día 20, falta 1" $ infoPeriodo cv (Tick 359) `shouldBe` InfoPeriodo False 18 20 1
    it "día 362: nemontemi, día 3, faltan 3" $ infoPeriodo cv (Tick 362) `shouldBe` InfoPeriodo True 0 3 3

  describe "espejo: corpus dorado compartido con Godot" $ do
    let s1  = avanzar [0] estadoInicial
        s2  = avanzar [1] s1
        s19 = avanzar [2..19] s2
        s20 = avanzar [20] s19
        s64 = avanzar [5..64] conFiesta
        (s65, h65) = pasoConHechos 65 s64
        s4  = avanzar [0..4] estadoInicial
        casos =
          [ ("01_tick_sin_cambios", s1, s2, [])
          , ("02_veintena", s19, s20, [])
          , ("03_aparece_modificador", s4, conFiesta, [])
          , ("04_modificador_expira", s64, s65, h65)
          , ("05_entidad_eliminada", estadoInicial, sinAldea2 estadoInicial, [])
          , ("06_entidad_nueva", sinAldea2 estadoInicial, estadoInicial, []) ]
    forM_ casos $ \(n, a, b, hs) -> do
      it (T.unpack n) $ dorado ("espejo/" ++ T.unpack n ++ ".json") (casoEspejo n a b hs)
      it (T.unpack n ++ ": aplicar los cambios a la vista de antes da la de después") $
        aplicar (proyeccion juguete a) (cambios (proyeccion juguete a) (proyeccion juguete b))
          `shouldBe` proyeccion juguete b


  describe "calendario genérico" $ do
    let meses = CalendarioInterno "mes" "epagómenos" 30 12 5 0      -- 12 meses de 30 días y 5 epagómenos
    it "otro calendario: un año de meses tiene 365 días y 12 inicios de periodo" $
      (diasDelAnio meses, length (filter (esInicioDePeriodo meses . Tick) [0 .. 364])) `shouldBe` (365, 12)
    it "los días fuera de periodo no inician periodo" $
      any (esInicioDePeriodo meses . Tick) [360 .. 364] `shouldBe` False
    it "el desfase mueve el tick 0 dentro del año" $
      infoPeriodo (calendarioVeintenas 45) (Tick 0) `shouldBe` InfoPeriodo False 3 6 15
    it "la veintena sigue teniendo 18 periodos y 5 nemontemi" $
      length (filter (esInicioDePeriodo cv . Tick) [0 .. 364]) `shouldBe` 18
    it "gregoriano: al 4 de octubre de 1582 juliano le sigue el 15 de octubre gregoriano" $
      [ fechaVisible (CambioAGregoriano (Fecha 1582 10 4)) (Fecha 1582 10 1) (Tick n) | n <- [3, 4] ]
        `shouldBe` [(Fecha 1582 10 4, "juliano"), (Fecha 1582 10 15, "gregoriano")]
    it "gregoriano: 1600 es bisiesto y 1700 no" $
      ( fechaVisible SoloGregoriano (Fecha 1600 2 28) (Tick 1)
      , fechaVisible SoloGregoriano (Fecha 1700 2 28) (Tick 1) )
        `shouldBe` ((Fecha 1600 2 29, "gregoriano"), (Fecha 1700 3 1, "gregoriano"))
    it "ida y vuelta del día juliano gregoriano" $ property $ \(NonNegative n) ->
      let f = desdeDiaJulianoGregoriano (2260000 + n `mod` 200000) in desdeDiaJulianoGregoriano (diaJulianoGregoriano f) == f
    it "un juego de juguete con calendario de meses corre sus sistemas 12 veces al año" $ do
      let conMeses = estadoInicial { estadoPersistente = (estadoPersistente estadoInicial)
                       { persistenteComun = (persistenteComun (estadoPersistente estadoInicial)) { comunCalendario = meses } } }
      baseMag 1 (Magnitud "poblacion") (avanzar [0..364] conMeses) `shouldBe` Just (fi 112)


  describe "agentes externos: contrato" $ do
    let s20 = avanzar [0..19] estadoInicial
    it "agente_turno" $ dorado "protocolo/agente_turno.json"
      (turnoAgente (Semilla 1) (FaccionId 2) (Tick 20) (relojJuguete s20) (proyeccion juguete s20))
    it "agente_plan" $ do
      let plan = PlanAgente 20 [A.object ["tipo" A..= ("subir_impuesto" :: Text), "aldea" A..= (1 :: Int), "valor" A..= (2 :: Int)]] (Just "tesoro bajo")
      regenerar <- lookupEnv "REGENERAR_DORADOS"
      case regenerar of
        Just _  -> BL.writeFile "../pruebas_compartidas/protocolo/agente_plan.json" (AP.encodePretty' AP.defConfig { AP.confCompare = compare } plan <> "\n")
        Nothing -> (A.eitherDecode <$> BL.readFile "../pruebas_compartidas/protocolo/agente_plan.json") `shouldReturn` Right plan
    it "la nota es opcional" $
      A.eitherDecode "{\"tipo\":\"agente_plan\",\"tick\":40,\"comandos\":[]}" `shouldBe` Right (PlanAgente 40 [] Nothing)
    it "otro tipo de mensaje no pasa por un plan" $
      (A.eitherDecode "{\"tipo\":\"comando\",\"tick\":40,\"comandos\":[]}" :: Either String PlanAgente) `shouldSatisfy` isLeft
    it "la semilla del agente es determinista y distinta por tick" $
      (semillaAgente (Semilla 1) (FaccionId 2) (Tick 20), semillaAgente (Semilla 1) (FaccionId 2) (Tick 20) /= semillaAgente (Semilla 1) (FaccionId 2) (Tick 40))
        `shouldBe` (semillaAgente (Semilla 1) (FaccionId 2) (Tick 20), True)


  describe "guion: carga" $ do
    it "el guion del juguete carga con 3 fases, 11 situaciones y 11 tipos" $
      (length (guFases guionJuguete), length (guSituaciones guionJuguete), length (guTipos guionJuguete)) `shouldBe` (3, 11, 11)
    it "la fecha de una fase se convierte a tick: 1 de enero de 1485 es el día 3653" $
      faDesde (guFases guionJuguete !! 1) `shouldBe` Just 3653
    it "un tipo fuera del vocabulario, una fase desconocida y un efecto mal escrito dan tres errores" $ do
      let malo = A.object [ "tipos" A..= ["guerra" :: Text], "fases" A..= [A.object ["id" A..= ("uno" :: Text)]]
                          , "situaciones" A..= [ A.object [ "id" A..= ("x" :: Text), "tipo" A..= ("sucesión" :: Text), "fases" A..= ["dos" :: Text]
                                                          , "opciones" A..= [A.object ["id" A..= ("a" :: Text), "efectos" A..= [A.object ["tipo" A..= ("volar" :: Text)]]]] ] ] ]
      length (valErrores (cargarGuion "malo.json" inicioJuguete malo)) `shouldBe` 3

  describe "guion: fases" $ do
    let (s30, hs30) = avanzarCon entornoGuion [0..10949] estadoInicial
        fases = [ (hechoTick h, Map.lookup "fase" (hechoParams h)) | h <- hs30, hechoTipo h == "fase" ]
    it "pasa por las tres fases en orden, y la frontera llega antes de su fecha por su condición" $ do
      map snd fases `shouldBe` [Just "consolidacion", Just "frontera", Just "crisis"]
      (case fases of (_ : (Tick tf, _) : _) -> tf < 3653; _ -> False) `shouldBe` True
    it "la fuente de presión no corre en la consolidación" $
      presionEn (fst (avanzarCon entornoGuion [0..1000] estadoInicial)) `shouldBe` Fijo 0
    it "en la fase de frontera, la presión llega a 3 modificadores × intensidad 2 = 6" $ do
      let Tick tf = case fases of (_ : (t, _) : _) -> t; _ -> Tick 0
      presionEn (fst (avanzarCon entornoGuion [0 .. tf + 100] estadoInicial)) `shouldBe` fi 6
    it "al apagarse en la crisis, la presión baja sin saltos y vuelve a la base" $ do
      let Tick tc = case fases of (_ : _ : (t, _) : _) -> t; _ -> Tick 0
          (sAntes, _) = avanzarCon entornoGuion [0 .. tc - 1] estadoInicial
          trayectoria = scanl (\e t -> fst (paso juguete entornoGuion (Semilla 1) (Tick t) [] e)) sAntes [tc .. tc + 100]
          valores = map presionEn trayectoria
      (head valores > Fijo 0, last valores) `shouldBe` (True, Fijo 0)
      and (zipWith (>=) valores (tail valores)) `shouldBe` True
    it "el estado de la partida a los 30 años es la fase de crisis" $
      edFase (directorDe s30) `shouldBe` 2

  describe "guion: director" $ do
    let (s30, _) = avanzarCon entornoGuion [0..10949] estadoInicial
        hist = reverse (edHistorial (directorDe s30))
    it "respeta el espaciado de 60 días entre situaciones" $
      and (zipWith (\a b -> let Tick x = diTick a; Tick y = diTick b in y - x >= 60) hist (tail hist)) `shouldBe` True
    it "cada situación sale solo en sus fases" $
      all (\x -> diFase x `elem` (maybe [] siFases (lookup (diSituacion x) [ (siId s, s) | s <- guSituaciones guionJuguete ]))) hist `shouldBe` True
    it "la incursión solo sale con presión en la frontera" $
      all (\x -> diSituacion x /= "incursion" || diFase x == "frontera") hist `shouldBe` True
    it "es determinista: guardar a mitad y cargar da el mismo historial a los 30 años" $ do
      let (s5000, _) = avanzarCon entornoGuion [0..4999] estadoInicial
          Right cargado = cargar juguete mapaPrueba (guardar s5000)
          (sA, _) = avanzarCon entornoGuion [5000..10949] cargado
      edHistorial (directorDe sA) `shouldBe` edHistorial (directorDe s30)
    it "los ids de decisión no se repiten en 30 años, aunque las anteriores ya se resolvieron" $ do
      let (_, hs) = avanzarCon entornoGuion [0..10949] estadoInicial
          ids = [ i | h <- hs, hechoTipo h == "situacion", Just i <- [Map.lookup "decision" (hechoParams h)] ]
      length ids `shouldBe` Set.size (Set.fromList ids)
    it "sin respuesta, al vencer el plazo se aplica la primera opción y no quedan decisiones colgando" $
      Map.size (comunDecisiones (persistenteComun (estadoPersistente s30))) `shouldSatisfy` (<= 1)

  describe "guion: responder" $ do
    -- Avanza día a día hasta el primer día en que el director presenta una situación.
    let trayecto = tail (scanl (\(e, _) t -> paso juguete entornoGuion (Semilla 1) (Tick t) [] e) (estadoInicial, []) [0 .. 3000])
        (sPrimera, hs) = head [ x | x@(_, h) <- trayecto, any ((== "situacion") . hechoTipo) h ]
        hSit = head [ h | h <- hs, hechoTipo h == "situacion" ]
        dec = maybe 0 (read . T.unpack) (Map.lookup "decision" (hechoParams hSit))
        Just sid = Map.lookup "situacion" (hechoParams hSit)
        Just s = lookup sid [ (siId x, x) | x <- guSituaciones guionJuguete ]
        segunda = fst (siOpciones s !! 1)
        Tick tp = estadoTick sPrimera
        responderEn r = pasoCompleto juguete entornoGuion (Semilla 1) (Tick (tp + 1)) [] [r] sPrimera
    it "responder con una opción la resuelve y emite situacion_resuelta" $ do
      let (e', hs', _, rr) = responderEn (Respuesta 1 dec segunda)
      (rr, any ((== "situacion_resuelta") . hechoTipo) hs', Map.member dec (comunDecisiones (persistenteComun (estadoPersistente e'))))
        `shouldBe` ([], True, False)
    it "una opción que no existe se rechaza sin tocar la decisión" $ do
      let (e', _, _, rr) = responderEn (Respuesta 2 dec "teletransportar")
      (map (reSecuencia . fst) rr, Map.member dec (comunDecisiones (persistenteComun (estadoPersistente e')))) `shouldBe` ([2], True)
    it "una decisión que no existe se rechaza" $ do
      let (_, _, _, rr) = responderEn (Respuesta 3 9999 "x")
      map (reSecuencia . fst) rr `shouldBe` [3]

  describe "guion: métricas del hito 0 como prueba permanente" $ do
    let (s30, _) = avanzarCon entornoGuion [0..10949] estadoInicial
        m = metricas 3650 10950 (directorDe s30)
    it "con tres actos, el juguete cumple el criterio: ningún tipo > 25 % y ≥ 2 tipos nuevos por década" $ do
      (cumpleVariedad 0.25 2 m, m) `shouldBe` (True, m)   -- si falla, muestra las métricas
      mTotal m `shouldSatisfy` (>= 20)
    it "sin fases (todas las situaciones siempre), la novedad por década falla: la prueba detecta un acto II repetitivo" $ do
      let plano = guionJuguete { guFases = [], guSituaciones = [ x { siFases = [], siCondicion = Siempre } | x <- guSituaciones guionJuguete ] }
          (sP, _) = avanzarCon (Entorno mapaPrueba plano economiaVacia) [0..10949] estadoInicial
          mP = metricas 3650 10950 (directorDe sP)
      (cumpleVariedad 0.25 2 mP, mTotal mP > 0) `shouldBe` (False, True)

  monedaPruebas
  where
    mkSys :: NombreSistema -> Cadencia
          -> Set Magnitud -> Set Magnitud -> Sistema s
    mkSys n c lee esc = Sistema n c lee esc (\_ e -> (e, []))

entornoPrueba :: Entorno
entornoPrueba = entornoSimple mapaPrueba

mapaPrueba :: Mapa
mapaPrueba = either (error . show) id (proveedorHexagonal (DatosHex 5 4 (Fijo 10000) 1))

esAsimetrica :: ErrorMapa -> Bool
esAsimetrica (ConexionAsimetrica _ _) = True
esAsimetrica _ = False

cerca :: Int -> Fijo -> Int -> Bool
cerca tol (Fijo a) b = abs (fromIntegral a - b) <= tol


cv :: CalendarioInterno
cv = calendarioVeintenas 0

isLeft :: Either a b -> Bool
isLeft (Left _)  = True
isLeft (Right _) = False


-- ---------------------------------------------------------------------------
-- Moneda designada e inflación (Motor.Moneda)
-- ---------------------------------------------------------------------------

faccionJ :: EntRef
faccionJ = EntRef "faccion" 1

{-# NOINLINE economiaJuguete #-}
economiaJuguete :: Economia
economiaJuguete = case A.decode bienesBytes >>= \v -> valValor (cargarEconomia "bienes_juguete.json" v) of
  Just ec -> ec
  Nothing -> error "test/bienes_juguete.json no carga"

bienesBytes :: BL.ByteString
bienesBytes = unsafePerformIO (BL.readFile "test/bienes_juguete.json")
{-# NOINLINE bienesBytes #-}

entornoMoneda :: Entorno
entornoMoneda = Entorno mapaPrueba guionVacio economiaJuguete

-- | Una mina que cada veintena suma su producción a las existencias de plata.
minaSistema :: Sistema Aldeas
minaSistema = Sistema
  { sisNombre   = NombreSistema "mina"
  , sisCadencia = Periodo
  , sisLee      = Set.singleton (magProduccion "plata")
  , sisEscribe  = Set.singleton (magExistencias "plata")
  , sisEjecutar = \_ est ->
      let alm = comunMagnitudes (persistenteComun (estadoPersistente est))
          prod = maybe (Fijo 0) almacenBase (Map.lookup (faccionJ, magProduccion "plata") alm)
      in (conAlmacen est (sumarBase faccionJ (magExistencias "plata") prod alm), [])
  }

-- | Un granero: una cosecha grande en la veintena 12 y consumo el resto del año.
graneroSistema :: Sistema Aldeas
graneroSistema = Sistema
  { sisNombre   = NombreSistema "granero"
  , sisCadencia = Periodo
  , sisLee      = Set.empty
  , sisEscribe  = Set.singleton (magExistencias "maiz")
  , sisEjecutar = \_ est ->
      let alm = comunMagnitudes (persistenteComun (estadoPersistente est))
          cal = comunCalendario (persistenteComun (estadoPersistente est))
          x = maybe (Fijo 0) almacenBase (Map.lookup (faccionJ, magExistencias "maiz") alm)
          x' = if ipPeriodo (infoPeriodo cal (estadoTick est)) == 12 then x .+. fi 1800
               else max (Fijo 0) (x .-. fi 100)
      in (conAlmacen est (fijarBase faccionJ (magExistencias "maiz") x' alm), [])
  }

conAlmacen :: Estado Aldeas -> Almacen -> Estado Aldeas
conAlmacen est alm =
  let p = estadoPersistente est
  in est { estadoPersistente = p { persistenteComun = (persistenteComun p) { comunMagnitudes = alm } } }

jugueteMoneda :: Juego Aldeas ComandoJuguete
jugueteMoneda = juguete { juegoSistemas = juegoSistemas juguete ++ [minaSistema, graneroSistema] }

estadoMoneda :: Estado Aldeas
estadoMoneda =
  let alm = foldl' (\a (b, m, v) -> fijarBase faccionJ (m b) (fi v) a)
              (comunMagnitudes (persistenteComun (estadoPersistente estadoInicial)))
              [ ("plata", magExistencias, 2000), ("plata", magProduccion, 100)
              , ("oro", magExistencias, 200), ("maiz", magExistencias, 1000)
              , ("", const (Magnitud "tesoro"), 1000) ]
      e = conAlmacen estadoInicial alm
  in e { estadoOrigen = Origen (Tick 0) (estadoPersistente e) }

-- | Juega desde el tick 0 hasta @n@ − 1, designando @moneda@ el primer día.
jugarConMoneda :: Text -> Int64 -> Estado Aldeas
jugarConMoneda moneda n =
  foldl' (\e t -> fst (paso jugueteMoneda entornoMoneda (Semilla 1) (Tick t)
                         [ Sellado (Tick 0) (FaccionId 1) 1 (DesignarMonedaJ (Just moneda)) | t == 0 ] e))
         estadoMoneda [0 .. n - 1]

magDe :: Magnitud -> Estado Aldeas -> Maybe Fijo
magDe m e = almacenBase <$> Map.lookup (faccionJ, m) (comunMagnitudes (persistenteComun (estadoPersistente e)))

monedaDe :: Estado Aldeas -> Maybe EstadoMonetario
monedaDe e = Map.lookup faccionJ (comunMonedas (persistenteComun (estadoPersistente e)))

genFijoNoNeg :: Gen Fijo
genFijoNoNeg = Fijo <$> choose (0, 100000000)       -- de 0 a 10 000

genBien :: Gen Bien
genBien = do
  v <- Fijo <$> choose (1, 100000)
  q <- Fijo <$> choose (0, 10000)
  r <- Fijo <$> choose (1, 50000000)
  e <- Fijo <$> choose (0, 10000)
  pure (Bien "g" v q r e True)

monedaPruebas :: Spec
monedaPruebas = do
  describe "moneda: carga de los bienes" $ do
    it "carga los cuatro bienes del juguete; las plumas no son designables" $ do
      Map.size (ecoBienes economiaJuguete) `shouldBe` 4
      bnDesignable <$> Map.lookup "plumas" (ecoBienes economiaJuguete) `shouldBe` Just False
      pmHorizonte (ecoParams economiaJuguete) `shouldBe` fi 6
    it "acumula todos los errores: rangos, valor no positivo y bienes repetidos" $ do
      let malo = A.object [ "bienes" A..= [ bienJ "a" "0" "1.5" "-0.1", bienJ "b" "1" "0.5" "0.2", bienJ "b" "1" "0.5" "0.2" ] ]
          bienJ i v q e = A.object [ "id" A..= (i :: Text), "valor" A..= (v :: Text), "calidad_monetaria" A..= (q :: Text)
                                   , "referencia" A..= ("10" :: Text), "elasticidad" A..= (e :: Text) ]
          Validacion errs r = cargarEconomia "malo.json" malo
      length errs `shouldBe` 4
      fmap (const ()) r `shouldBe` Nothing

  describe "moneda: el precio de un bien" $ do
    let pm = ecoParams economiaJuguete
        bien i = ecoBienes economiaJuguete Map.! i
    it "con la disponibilidad de referencia vale valor · calidad" $ do
      precioBien pm (bien "plata") (fi 2000) (Fijo 0) `shouldBe` Fijo 19000
      precioBien pm (bien "oro") (fi 200) (Fijo 0) `shouldBe` fi 6
    it "la producción cuenta como disponible durante el horizonte" $
      precioBien pm (bien "plata") (fi 1400) (fi 100) `shouldBe` precioBien pm (bien "plata") (fi 2000) (Fijo 0)
    it "ley: no sube cuando hay más existencias" $ property $
      forAll genBien $ \b -> forAll genFijoNoNeg $ \x1 -> forAll genFijoNoNeg $ \x2 ->
        precioBien pm b (max x1 x2) (Fijo 0) <= precioBien pm b (min x1 x2) (Fijo 0)
    it "ley: no sube cuando hay más producción" $ property $
      forAll genBien $ \b -> forAll genFijoNoNeg $ \y1 -> forAll genFijoNoNeg $ \y2 ->
        precioBien pm b (fi 10) (max y1 y2) <= precioBien pm b (fi 10) (min y1 y2)
    it "ley: con elasticidad 0 el precio no depende de la cantidad" $ property $
      forAll genBien $ \b0 -> forAll genFijoNoNeg $ \x ->
        let b = b0 { bnElasticidad = Fijo 0 }
        in precioBien pm b x (Fijo 0) == max (pmPrecioMinimo pm) (bnValor b .*. bnCalidad b)
    it "ley: nunca baja del piso, así que el nivel de precios siempre existe" $ property $
      forAll genBien $ \b -> forAll genFijoNoNeg $ \x ->
        precioBien pm b x x >= pmPrecioMinimo pm

  describe "moneda: designar" $ do
    let designar m = designarMoneda economiaJuguete faccionJ m (Tick 0) estadoMoneda
        motivo = either id (const "")
    it "rechaza un bien que no existe, uno no designable y retirar sin moneda" $ do
      motivo (designar (Just "cacao")) `shouldBe` "no hay ningún bien «cacao»"
      motivo (designar (Just "plumas")) `shouldBe` "«plumas» no puede ser moneda"
      motivo (designar Nothing) `shouldBe` "no hay moneda designada"
    it "al designar, el precio y el nivel de precios se ven en el acto, con su hecho" $ do
      let Right (e, hs) = designar (Just "oro")
      magDe magPrecioMoneda e `shouldBe` Just (fi 6)
      magDe magNivelPrecios e `shouldBe` Just (uno ./. fi 6)
      map hechoTipo hs `shouldBe` ["moneda_designada"]
      emMoneda <$> monedaDe e `shouldBe` Just "oro"
    it "volver a designar la misma moneda se rechaza; retirarla borra sus magnitudes" $ do
      let Right (e, _) = designar (Just "oro")
      either id (const "") (designarMoneda economiaJuguete faccionJ (Just "oro") (Tick 1) e) `shouldBe` "«oro» ya es la moneda"
      let Right (e', hs) = designarMoneda economiaJuguete faccionJ Nothing (Tick 1) e
      monedaDe e' `shouldBe` Nothing
      magDe magPrecioMoneda e' `shouldBe` Nothing
      map hechoTipo hs `shouldBe` ["moneda_retirada"]
    it "un comando rechazado no cambia el estado (rechazo sin daño)" $ do
      let (e, _, rechazos) = pasoDetallado jugueteMoneda entornoMoneda (Semilla 1) (Tick 0)
                               [Sellado (Tick 0) (FaccionId 1) 1 (DesignarMonedaJ (Just "plumas"))] estadoMoneda
          (e0, _, _) = pasoDetallado jugueteMoneda entornoMoneda (Semilla 1) (Tick 0) [] estadoMoneda
      length rechazos `shouldBe` 1
      guardar e `shouldBe` guardar e0
    it "costo en moneda: una obra de 300 cuesta 50 de oro, o 300 / p(plata), con la producción de la mina" $ do
      let Right (eo, _) = designar (Just "oro")
          Right (ep, _) = designar (Just "plata")
      costoEnMoneda economiaJuguete (Tick 0) eo faccionJ (fi 300) `shouldBe` Just (fi 50)
      costoEnMoneda economiaJuguete (Tick 0) ep faccionJ (fi 300) `shouldBe` Just (fi 300 ./. precioBien (ecoParams economiaJuguete) (ecoBienes economiaJuguete Map.! "plata") (fi 2000) (fi 100))
      costoEnMoneda economiaJuguete (Tick 0) estadoMoneda faccionJ (fi 300) `shouldBe` Nothing

  describe "moneda: el tesoro se cuenta en la moneda" $ do
    let tesoro = magDe (Magnitud "tesoro")
        designarEn m t e = either (error . T.unpack) fst (designarMoneda economiaJuguete faccionJ m (Tick t) e)
        valorReal e = aValor economiaJuguete (estadoTick e) e faccionJ (maybe (Fijo 0) id (tesoro e))
    it "al designar oro (p = 6), 1000 de valor pasan a ser 166,6666 oros" $
      tesoro (designarEn (Just "oro") 0 estadoMoneda) `shouldBe` Just (fi 1000 ./. fi 6)
    it "designar, cambiar y retirar la moneda no crea ni destruye valor (salvo el redondeo)" $ do
      let eOro = designarEn (Just "oro") 0 estadoMoneda
          ePlata = designarEn (Just "plata") 0 eOro
          eNada = designarEn Nothing 0 ePlata
      map (\e -> cerca 10 (valorReal e) (1000 * 10000)) [eOro, ePlata, eNada] `shouldBe` [True, True, True]
      tesoro eNada `shouldSatisfy` maybe False (\v -> cerca 10 v (1000 * 10000))
    it "enCuenta convierte un costo en valor a la moneda; sin moneda no cambia" $ do
      enCuenta economiaJuguete (Tick 0) estadoMoneda faccionJ (fi 300) `shouldBe` fi 300
      enCuenta economiaJuguete (Tick 0) (designarEn (Just "oro") 0 estadoMoneda) faccionJ (fi 300) `shouldBe` fi 50
    it "la inflación se come un tesoro guardado en plata; en oro no pierde valor" $ do
      let ePlata = jugarConMoneda "plata" (2 * 365)
          eOro = jugarConMoneda "oro" (2 * 365)
      valorReal ePlata `shouldSatisfy` (< fi 900)
      cerca 10 (valorReal eOro) (1000 * 10000) `shouldBe` True

  describe "moneda: inflación" $ do
    let dosAnios = 2 * 365
        ePlata = jugarConMoneda "plata" dosAnios
        eOro = jugarConMoneda "oro" dosAnios
        eMaiz = jugarConMoneda "maiz" dosAnios
    it "sin moneda designada, el paso monetario no escribe nada" $ do
      let e = foldl' (\s t -> fst (paso jugueteMoneda entornoMoneda (Semilla 1) (Tick t) [] s)) estadoMoneda [0 .. 400]
      map (`magDe` e) [magPrecioMoneda, magNivelPrecios, magInflacion] `shouldBe` [Nothing, Nothing, Nothing]
    it "el historial guarda un año y una veintena (19 precios), uno por veintena" $ do
      fmap (length . emHistorial) (monedaDe ePlata) `shouldBe` Just 19
    it "la plata de la mina se abarata cada veintena: inflación positiva" $ do
      let Just infl = magDe magInflacion ePlata
          Just em = monedaDe ePlata
      infl `shouldSatisfy` (> Fijo 0)
      Just infl `shouldBe` inflacionDe cv em
      -- el más reciente primero: cada veintena la plata vale menos que la anterior
      map snd (emHistorial em) `shouldBe` sort (map snd (emHistorial em))
    it "el oro no cambia de cantidad: inflación 0 y precios estables" $ do
      magDe magInflacion eOro `shouldBe` Just (Fijo 0)
      magDe magPrecioMoneda eOro `shouldBe` Just (fi 6)
    it "el maíz sube y baja con la cosecha: el nivel de precios fluctúa dentro del año" $ do
      let Just em = monedaDe eMaiz
          ps = map snd (emHistorial em)
      maximum ps `shouldSatisfy` (> minimum ps)
      length (filter id (zipWith (<) ps (drop 1 ps))) `shouldSatisfy` (> 0)
      length (filter id (zipWith (>) ps (drop 1 ps))) `shouldSatisfy` (> 0)
    it "antes de un año no hay inflación: no se inventa" $
      magDe magInflacion (jugarConMoneda "plata" 200) `shouldBe` Nothing
    it "cambiar de moneda empieza el historial de cero" $ do
      let (e, _) = paso jugueteMoneda entornoMoneda (Semilla 1) (Tick dosAnios)
                     [Sellado (Tick dosAnios) (FaccionId 1) 1 (DesignarMonedaJ (Just "oro"))] ePlata
      fmap emMoneda (monedaDe e) `shouldBe` Just "oro"
      magDe magInflacion e `shouldBe` Nothing
    it "ley: guardar y cargar a mitad de veintena conserva la moneda, y la partida sigue igual" $ do
      let e = jugarConMoneda "plata" 437
          Right e' = cargar jugueteMoneda mapaPrueba (guardar e)
          seguir s = foldl' (\x t -> fst (paso jugueteMoneda entornoMoneda (Semilla 1) (Tick t) [] x)) s [437 .. 900]
      monedaDe e' `shouldBe` monedaDe e
      guardar (seguir e') `shouldBe` guardar (seguir e)
    it "un guardado anterior a la moneda carga sin monedas" $ do
      let Just (A.Object o) = A.decode (guardar estadoMoneda) :: Maybe Value
          quitar (A.Object x) = A.Object (ajustarKM quitarComun "origenP" (ajustarKM quitarComun "persist" x))
          quitar v = v
          quitarComun (A.Object x) = A.Object (ajustarKM (\case A.Object c -> A.Object (KM.delete "monedas" c); v -> v) "comun" x)
          quitarComun v = v
          viejo = A.encode (quitar (A.Object o))
      viejo `shouldNotBe` guardar estadoMoneda
      fmap monedaDe (cargar jugueteMoneda mapaPrueba viejo) `shouldBe` Right Nothing

-- | KM.adjust no existe en todas las versiones de aeson.
ajustarKM :: (Value -> Value) -> KM.Key -> KM.KeyMap Value -> KM.KeyMap Value
ajustarKM f k m = maybe m (\v -> KM.insert k (f v) m) (KM.lookup k m)
