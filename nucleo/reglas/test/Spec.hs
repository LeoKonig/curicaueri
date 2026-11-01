{-# LANGUAGE OverloadedStrings #-}
module Main where

import Control.Monad (forM_)
import Data.List (foldl')
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Test.Hspec

import Motor.Base
import Motor.Carga (validarOrdenSistemas, Validacion (..), ErrorCarga (..))
import Motor.Autoridad
import Motor.Protocolo (DeclComando (..), DeclParametro (..), TipoParametro (..))
import qualified Data.Aeson as A
import Data.Aeson.Types (Parser, parseEither, withObject, (.:))
import Motor.Estado
import Motor.Juego
import Motor.Magnitudes
import Motor.Mapa
import Motor.Guion (Entorno (..), entornoSimple)

import qualified Reglas.Juego
import Reglas.Juego (catalogoMag)
import Reglas.Base
import Reglas.Comando
import Reglas.Constantes
import Reglas.Escenario
import Reglas.Estado
import Reglas.Formulas
import Reglas.Grupos
import Reglas.Edificios
import Reglas.Produccion
import Motor.Terrenos (DefTerreno (..), cargarTerrenos, conCostoDeTerreno)
import Motor.Moneda (magExistencias, magProduccion)
import Test.QuickCheck
import Motor.Guardado (guardar, cargar)
import Motor.Hechos (Hecho (..))
import qualified Data.ByteString.Lazy as BL

mapaVacio :: Mapa
mapaVacio = Mapa mempty mempty (Fijo 10000)

-- | @datos/edificios.json@ cargado, o la lista de errores.
leerEdificios :: IO (Either [Text] Edificios)
leerEdificios = do
  v <- A.eitherDecodeFileStrict "../../datos/edificios.json"
  pure $ case v of
    Left err -> Left [T.pack err]
    Right j  -> case cargarEdificios "datos/edificios.json" catalogoMag j of
      Validacion [] (Just e) -> Right e
      Validacion errs _      -> Left (map errMensaje errs)

-- | @datos/terrenos.json@ cargado.
leerTerrenos :: IO (Map.Map Terreno DefTerreno)
leerTerrenos = do
  v <- A.eitherDecodeFileStrict "../../datos/terrenos.json"
  case v of
    Left err -> fail err
    Right j  -> case cargarTerrenos "datos/terrenos.json" j of
      Validacion [] (Just t) -> pure t
      Validacion errs _      -> fail (show (map errMensaje errs))

-- | Celdas de prueba: hasta tres bienes con rendimientos y trabajadores
-- positivos, con ids distintos.
genCeldas :: Gen [CeldaTrabajo]
genCeldas = do
  n <- choose (0, 8)
  mapM (\i -> do
          l  <- choose (1, 2000)
          k  <- choose (1, 3)
          ys <- vectorOf k (choose (0, 500000))
          let bs = take k ["maiz", "pescado", "sal"]
          pure (CeldaTrabajo i (Fijo (l * 10000)) (Map.fromList (zip bs (map Fijo ys)))))
       [1 .. n]

-- | @datos/grupos.json@ cargado, o la lista de errores.
leerGrupos :: IO (Either [Text] Grupos)
leerGrupos = do
  v <- A.eitherDecodeFileStrict "../../datos/grupos.json"
  pure $ case v of
    Left err -> Left [T.pack err]
    Right j  -> case cargarGrupos "datos/grupos.json" j of
      Validacion [] (Just g) -> Right g
      Validacion errs _      -> Left (map errMensaje errs)

main :: IO ()
main = do
 gruposArchivo <- leerGrupos
 dorNombrar   <- BL.readFile "../../pruebas_compartidas/protocolo/comando_nombrar_gobernador.json"
 dorDestituir <- BL.readFile "../../pruebas_compartidas/protocolo/comando_destituir_gobernador.json"
 dorConstruir <- BL.readFile "../../pruebas_compartidas/protocolo/comando_construir_edificio.json"
 dorTributo   <- BL.readFile "../../pruebas_compartidas/protocolo/comando_pedir_tributo_obra.json"
 edificiosArchivo <- leerEdificios
 terrenosArchivo  <- leerTerrenos
 hspec $ do
  describe "reglas: autoridad (V5, el prototipo no cambia)" $ do
    it "todos los comandos del prototipo usan el requisito por omisión" $
      map dcRequiere catalogoComandos `shouldBe` map (const requisitoPorOmision) catalogoComandos
    it "datos/ejes.json carga, trae los cinco ejes y el escenario y el catálogo lo respetan" $ do
      v <- A.eitherDecodeFileStrict "../../datos/ejes.json"
      case v of
        Left err -> expectationFailure err
        Right j -> do
          let Validacion errs mes = cargarEjes "datos/ejes.json" j
          map errMensaje errs `shouldBe` []
          let es = maybe [] id mes
          map ejId es `shouldBe` ["coercion", "extraccion", "legitimidad", "administracion", "red"]
          [ ejReferencia e | e <- es, ejId e == "legitimidad" ] `shouldBe` [desdeEntero 50]
          map errMensaje (valErrores (ejesActivos "escenario 1475" es ejesActivos1475)) `shouldBe` []
          map errMensaje (valErrores (validarRequisitos "catálogo" es [ (dcTipo d, dcRequiere d) | d <- catalogoComandos ])) `shouldBe` []

  describe "reglas: sistemas no violan el orden" $ do
    it "los tres sistemas del juego pasan validarOrdenSistemas" $ do
      let j = Reglas.Juego.juego constantesDefault
      validarOrdenSistemas catalogoMag (juegoSistemas j) `shouldBe` []

  describe "reglas: subir el impuesto sube el ingreso y el agravio" $ do
    let j  = Reglas.Juego.juego constantesDefault
        s0 = estadoInicial1475
        tesoro = baseFaccion magTesoro
        agravioPop k st =
          case Map.lookup (entRefPop (PopId k), Magnitud "agravio")
                          (comunMagnitudes
                            (persistenteComun (estadoPersistente st))) of
            Just (AlmacenMag b _) -> b
            Nothing               -> Fijo 0

        (sSin, _) =
          paso j (entornoSimple mapaVacio) (Semilla 1) (Tick 0) [] s0

        sell = Sellado (Tick 0) (FaccionId 1) 0 (FijarImpuestoInterno 5)
        (sCon, _) =
          paso j (entornoSimple mapaVacio) (Semilla 1) (Tick 0) [sell] s0

    it "ingreso: con tasa 5 el tesoro termina más alto" $
      tesoro sCon `shouldSatisfy` (> tesoro sSin)

    it "agravio: con tasa 5 el agravio del pop común sube" $
      agravioPop 2 sCon `shouldSatisfy` (> agravioPop 2 sSin)

    it "agravio: con tasa 5 el agravio de la nobleza sube la mitad" $ do
      let dComun   = agravioPop 2 sCon .-. agravioPop 2 sSin
          dNobleza = agravioPop 1 sCon .-. agravioPop 1 sSin
      -- El factor de estrato de la nobleza es 0,5 y el de lo común, 1. Cada
      -- delta se trunca a 0,0001 por separado, así que la mitad exacta puede
      -- diferir en una o dos unidades.
      let Fijo mitad = dNobleza .*. fi 2
          Fijo comun = dComun
      abs (mitad - comun) `shouldSatisfy` (<= 2)

  describe "reglas: repetición con el juego real" $ do
    it "misma semilla, mismos comandos, misma traza (10 ticks)" $ do
      let j = Reglas.Juego.juego constantesDefault
          traza s = foldl' (\e t -> fst (paso j (entornoSimple mapaVacio) (Semilla 7) (Tick t) [] e))
                          s [0..9]
          a = traza estadoInicial1475
          b = traza estadoInicial1475
      comunMagnitudes (persistenteComun (estadoPersistente a))
        `shouldBe` comunMagnitudes (persistenteComun (estadoPersistente b))

  describe "reglas: rechazo sin daño" $ do
    it "una tasa fuera de rango no toca el estado" $ do
      let j    = Reglas.Juego.juego constantesDefault
          sell = Sellado (Tick 0) (FaccionId 1) 0 (FijarImpuestoInterno 9)
          (s', _, rs) = aplicarCola j [sell] estadoInicial1475
      case rs of
        [Rechazo _] -> pure ()
        _           -> expectationFailure "se esperaba un rechazo"
      ppTasas (persistenteJuego (estadoPersistente s'))
        `shouldBe` ppTasas (persistenteJuego (estadoPersistente estadoInicial1475))

  describe "reglas: nombramientos y grupos de poder (hito 3)" $ do
    let gs = either (error . show) id gruposArchivo
        j  = Reglas.Juego.juegoCon constantesDefault gs
        Validacion erroresEsc mEsc = conGrupos "datos/grupos.json" gs tipoFaccion1475 estadoInicial1475
        s0 = maybe (error (show erroresEsc)) id mEsc
        alm st = comunMagnitudes (persistenteComun (estadoPersistente st))
        efectivo m st = maybe (Fijo 0)
          (valorEn (derivadoVigentes (estadoDerivado st)) (estadoTick st) (RangoMag (Fijo 0) (fi 100)))
          (Map.lookup (entFaccion, m) (alm st))
        baseDe m st = maybe (Fijo 0) almacenBase (Map.lookup (entFaccion, m) (alm st))
        aporte m st = efectivo m st .-. baseDe m st
        cmd t n c st = aplicarCola j [Sellado (Tick t) (FaccionId 1) n c] st
        estadoDe (e, _, _) = e
        rechazoDe (_, _, rs) = rs
        hechosDe (_, hs, _) = hs
        correr ts st = foldl' (\e t -> fst (paso j (entornoSimple mapaVacio) (Semilla 1) (Tick t) [] e)) st ts
        terminados hs = [ Map.lookup "razon" (hechoParams h) | h <- hs, hechoTipo h == "modificador_terminado" ]
        gob a st = Map.lookup (AltId a) (ppAltepetl (persistenteJuego (estadoPersistente st))) >>= altGobernador
        nobPoder = magPoder "nobleza_guerrera"
        admPoder = magPoder "administradores"
        admLeal  = magLealtad "administradores"
        sacLeal  = magLealtad "sacerdocio"
        -- Zacapu (2) queda vacante; el Inepto (3, nobleza guerrera) pasa a gobernar Uruapan (3),
        -- que gobernaba el Capaz (4, administradores).
        sVacante = estadoDe (cmd 0 0 (DestituirGobernador (AltId 2)) s0)
        sReemp   = cmd 0 1 (NombrarGobernador (AltId 3) (PerId 3)) sVacante
    it "datos/grupos.json carga con los cuatro grupos del vocabulario" $ do
      either id (const []) gruposArchivo `shouldBe` []
      grIds gs `shouldBe` ["nobleza_guerrera", "administradores", "sacerdocio", "mercaderes"]
    it "el escenario con grupos carga, y sus bases son las del reino centralizado" $ do
      map errMensaje erroresEsc `shouldBe` []
      (baseDe nobPoder s0, baseDe admPoder s0, baseDe (magLealtad "mercaderes") s0)
        `shouldBe` (fi 60, fi 40, fi 50)
    it "los gobernadores del escenario ya aportan: dos cargos de la nobleza y uno de los administradores" $ do
      (aporte nobPoder s0, aporte admPoder s0) `shouldBe` (fi 10, fi 5)
      -- los administradores pretendían los dos cargos de la nobleza: 2 × (−3), y +5 por el suyo
      aporte admLeal s0 `shouldBe` fi (-1)
    it "el desglose nombra el nombramiento" $
      [ fuenteRef (modFuente m) | Just x <- [Map.lookup (entFaccion, admPoder) (alm s0)], m <- almacenMods x ]
        `shouldBe` ["4:gobernador:3"]
    it "añadir varios de una vez da el mismo almacén que añadirlos uno a uno" $ do
      let mk k (e, m) = Modificador 0 (Magnitud m) (EntRef e 1) (Aporte (fi k) (Fijo 0)) (Fuente "prueba" (T.pack (show k)))
                                    Nothing Nothing Nothing AlcancePropia
          ms = zipWith mk [1 ..] [("a", "x"), ("b", "x"), ("a", "x"), ("a", "y"), ("a", "x"), ("b", "x")]
      agregarVarios ms (alm s0) `shouldBe` foldl' (\a m -> fst (agregarModificador m a)) (alm s0) ms
    it "las magnitudes de los grupos están en el catálogo del juego" $
      all (`Map.member` juegoCatalogoMag j) [nobPoder, admLeal] `shouldBe` True
    it "destituir quita el cargo, vuelve a la base y emite modificador_terminado con razón fuente" $ do
      let r = cmd 0 0 (DestituirGobernador (AltId 3)) s0
      gob 3 (estadoDe r) `shouldBe` Nothing
      aporte admPoder (estadoDe r) `shouldBe` Fijo 0
      terminados (hechosDe r) `shouldBe` [Just "fuente", Just "fuente", Just "fuente"]
    it "reemplazar termina los modificadores del anterior y añade los del nuevo" $ do
      gob 3 (estadoDe sReemp) `shouldBe` Just (PerId 3)
      rechazoDe sReemp `shouldBe` []
      terminados (hechosDe sReemp) `shouldBe` [Just "fuente", Just "fuente", Just "fuente"]
      (aporte nobPoder (estadoDe sReemp), aporte admPoder (estadoDe sReemp)) `shouldBe` (fi 10, Fijo 0)
    it "sin trinquete: el aporte es constante mientras dura el cargo" $ do
      let s100 = correr [1 .. 100] (estadoDe sReemp)
      aporte nobPoder s100 `shouldBe` aporte nobPoder (estadoDe sReemp)
      baseDe nobPoder s100 `shouldBe` baseDe nobPoder (estadoDe sReemp)
    it "solo pierden lealtad los grupos que pretendían el cargo" $ do
      let conSacerdote = s0 { estadoPersistente = (estadoPersistente s0) { persistenteJuego =
            (persistenteJuego (estadoPersistente s0)) { ppPersonajes = Map.adjust (\pe -> pe { perGrupo = Just "sacerdocio" })
                                                         (PerId 1) (ppPersonajes (persistenteJuego (estadoPersistente s0))) } } }
          r = estadoDe (cmd 0 1 (NombrarGobernador (AltId 2) (PerId 1)) (estadoDe (cmd 0 0 (DestituirGobernador (AltId 2)) conSacerdote)))
      aporte sacLeal r `shouldBe` fi 5
      aporte (magLealtad "mercaderes") r `shouldBe` Fijo 0
      -- los administradores pierden 3 por cada uno de los dos cargos que no son suyos, y ganan 5 por el suyo
      aporte admLeal r `shouldBe` fi (-1)
    it "un personaje sin grupo no mueve poder de nadie" $ do
      let r = estadoDe (cmd 0 1 (NombrarGobernador (AltId 2) (PerId 1)) sVacante)
      gob 2 r `shouldBe` Just (PerId 1)
      alm r `shouldBe` alm sVacante
    it "rechazos legibles sin daño: altépetl o personaje inexistente, muerto, ya gobierna" $ do
      let muerto = s0 { estadoPersistente = (estadoPersistente s0) { persistenteJuego =
            (persistenteJuego (estadoPersistente s0)) { ppPersonajes = Map.adjust (\pe -> pe { perVivo = False })
                                                         (PerId 1) (ppPersonajes (persistenteJuego (estadoPersistente s0))) } } }
          intento st c = let r = cmd 0 0 c st in (rechazoDe r, alm (estadoDe r) == alm st
                                                  , ppAltepetl (persistenteJuego (estadoPersistente (estadoDe r)))
                                                      == ppAltepetl (persistenteJuego (estadoPersistente st)))
      intento s0 (NombrarGobernador (AltId 9) (PerId 1)) `shouldBe` ([Rechazo "el altépetl no existe"], True, True)
      intento s0 (NombrarGobernador (AltId 2) (PerId 9)) `shouldBe` ([Rechazo "el personaje no existe"], True, True)
      intento muerto (NombrarGobernador (AltId 2) (PerId 1)) `shouldBe` ([Rechazo "Zuangua está muerto"], True, True)
      intento s0 (NombrarGobernador (AltId 2) (PerId 4)) `shouldBe` ([Rechazo "Gobernador Capaz ya gobierna Uruapan"], True, True)
      intento s0 (NombrarGobernador (AltId 2) (PerId 3)) `shouldBe` ([Rechazo "Gobernador Inepto ya gobierna Zacapu"], True, True)
      intento sVacante (DestituirGobernador (AltId 2)) `shouldBe` ([Rechazo "Zacapu no tiene gobernador"], True, True)
      intento s0 (DestituirGobernador (AltId 9)) `shouldBe` ([Rechazo "el altépetl no existe"], True, True)
    it "un mal gobernador nombrado por comando sigue bajando la recaudación" $ do
      let paso0 st = fst (paso j (entornoSimple mapaVacio) (Semilla 1) (Tick 0) [] st)
      baseFaccion magTesoro (paso0 (estadoDe sReemp)) `shouldSatisfy` (< baseFaccion magTesoro (paso0 sVacante))
    it "sin archivo de grupos, nombrar solo cambia el gobernador" $ do
      let jSin = Reglas.Juego.juego constantesDefault
          (r, hs, rs) = aplicarCola jSin [Sellado (Tick 0) (FaccionId 1) 0 (DestituirGobernador (AltId 3))] estadoInicial1475
      (rs, hs, gob 3 r, alm r == alm estadoInicial1475) `shouldBe` ([], [], Nothing, True)
    it "la carga acumula los errores de un grupos.json malo" $ do
      let malo = A.object
            [ "grupos" A..= (["a", "a", "b"] :: [Text])
            , "bases" A..= A.object [ "reino" A..= A.object
                [ "a" A..= A.object ["poder" A..= ("120" :: Text), "lealtad" A..= ("50" :: Text)]
                , "z" A..= A.object ["poder" A..= ("1" :: Text), "lealtad" A..= ("1" :: Text)] ] ]
            , "cargos" A..= A.object [ "gobernador" A..= A.object ["pretendientes" A..= (["q"] :: [Text])] ]
            , "poder_por_cargo" A..= ("-1" :: Text), "lealtad_por_cargo" A..= ("5" :: Text)
            , "lealtad_por_cargo_perdido" A..= ("3" :: Text) ]
      map errMensaje (valErrores (cargarGrupos "malo.json" malo)) `shouldBe`
        [ "grupo repetido", "falta la base de este grupo", "fuera de 0..100", "grupo desconocido"
        , "grupo desconocido: q", "no puede ser negativa" ]
    it "un personaje con un grupo que el archivo no declara falla al cargar el escenario" $ do
      let raro = estadoInicial1475 { estadoPersistente = (estadoPersistente estadoInicial1475) { persistenteJuego =
            (persistenteJuego (estadoPersistente estadoInicial1475)) { ppPersonajes = Map.adjust (\pe -> pe { perGrupo = Just "brujos" })
                (PerId 1) (ppPersonajes (persistenteJuego (estadoPersistente estadoInicial1475))) } } }
      map errMensaje (valErrores (conGrupos "grupos.json" gs tipoFaccion1475 raro)) `shouldBe` ["grupo desconocido: brujos"]
    it "los comandos coinciden con sus archivos dorados, de ida y de vuelta" $ do
      (A.decode dorNombrar, A.decode dorDestituir)
        `shouldBe` (Just (A.toJSON (NombrarGobernador (AltId 3) (PerId 2))), Just (A.toJSON (DestituirGobernador (AltId 2))))
      (A.decode dorNombrar, A.decode dorDestituir)
        `shouldBe` (Just (NombrarGobernador (AltId 3) (PerId 2)), Just (DestituirGobernador (AltId 2)))
    it "un personaje guardado sin grupo (guardados anteriores) carga sin grupo" $
      (A.decode "{\"perId\":1,\"perNombre\":\"Z\",\"perAdmin\":3,\"perMando\":2,\"perEdad\":40,\"perVivo\":true}" :: Maybe Personaje)
        `shouldBe` Just (Personaje (PerId 1) "Z" 3 2 40 True Nothing)

  describe "reglas: cifras de la recaudación" $
    -- Con las eficiencias del escenario (93, 31 y 68 puntos) el ingreso anual
    -- es 526,32; el gasto, 420. El neto se divide una sola vez entre 18:
    -- 1000 + 106,32 ÷ 18 = 1005,9066…
    it "tick 0 a tasas neutras: 1000 + (526,32 − 70 × 6) ÷ 18 = 1005,9066" $ do
      let j = Reglas.Juego.juego constantesDefault
          (s1, _) = paso j (entornoSimple mapaVacio) (Semilla 1) (Tick 0) [] estadoInicial1475
      cercaCon 3 (baseFaccion magTesoro s1) 1005.906666

  describe "reglas: gobernadores (hito 3, primer corte)" $ do
    let j = Reglas.Juego.juego constantesDefault
        unTick e = fst (paso j (entornoSimple mapaVacio) (Semilla 1) (Tick 0) [] e)
        agravioPop k st =
          maybe (Fijo 0) almacenBase
            (Map.lookup (entRefPop (PopId k), Magnitud "agravio")
                        (comunMagnitudes (persistenteComun (estadoPersistente st))))
        base      = unTick estadoInicial1475
        -- Zuangua es el cazonci; Tangáxoan (administración 4) gobierna Tzintzuntzan,
        -- el Inepto (1) Zacapu y el Capaz (3) Uruapan.
        sinInepto = unTick (conGobernador (AltId 2) (PerId 4) estadoInicial1475)
        conInepto = unTick (conGobernador (AltId 1) (PerId 3) estadoInicial1475)

    it "un mal gobernador baja la recaudación" $
      baseFaccion magTesoro conInepto `shouldSatisfy` (< baseFaccion magTesoro base)

    it "un buen gobernador la sube" $
      baseFaccion magTesoro sinInepto `shouldSatisfy` (> baseFaccion magTesoro base)

    it "un mal gobernador sube el agravio de su altépetl" $
      agravioPop 1 conInepto `shouldSatisfy` (> agravioPop 1 base)

    it "un buen gobernador baja el agravio de su altépetl" $
      agravioPop 3 sinInepto `shouldSatisfy` (< agravioPop 3 base)

  describe "reglas: obras con cuadrilla, materiales y beneficio (hito 3, etapa 1)" $ do
    let eds  = either (const edificiosVacios) id edificiosArchivo
        mapa = conCostoDeTerreno terrenosArchivo (either (error . show) id (proveedorHexagonal datosMapa1475))
        ent  = entornoSimple mapa
        dr   = Reglas.Juego.datosVacios { Reglas.Juego.drEdificios = eds, Reglas.Juego.drTerrenos = terrenosArchivo }
        j    = Reglas.Juego.juegoDatos constantesDefault dr
        conDerivado e = e { estadoDerivado = derivar j (entGrafo ent) (estadoTick e) (estadoPersistente e) }
        e0   = conDerivado estadoInicial1475
        -- Corre los días [desde .. hasta], con los comandos del primero.
        correrDias cmds desde hasta est0 =
          foldl' (\(e, hs) t -> let (e', hs') = paso j ent (Semilla 1) (Tick t)
                                                  (if t == desde then cmds else []) e
                                in (e', hs ++ hs'))
                 (est0, []) [desde .. hasta]
        construir e a n = [Sellado (Tick 0) (FaccionId 1) 0 (ConstruirEdificio e (AltId a) n)]
        alm st = comunMagnitudes (persistenteComun (estadoPersistente st))
        foto st = (persistenteJuego (estadoPersistente st), alm st)
        jue st = persistenteJuego (estadoPersistente st)
        altDe a st = ppAltepetl (jue st) Map.! AltId a
        efectivo r m st = maybe (Fijo 0) (valorEn (derivadoVigentes (estadoDerivado st)) (estadoTick st)
                                            (maybe (RangoMag (Fijo minBound) (Fijo maxBound)) dmRango (Map.lookup m catalogoMag)))
                                        (Map.lookup (r, m) (alm st))
        aplicar1 c st = aplicarCola j [Sellado (Tick 0) (FaccionId 1) 0 c] st
        conPresupuestoObras n st = let p = estadoPersistente st; ju = persistenteJuego p
                                   in st { estadoPersistente = p { persistenteJuego = ju { ppPresupuesto =
                                             (ppPresupuesto ju) { pbObras = n } } } }
        conTesoro x st = let p = estadoPersistente st; com = persistenteComun p
                         in st { estadoPersistente = p { persistenteComun = com { comunMagnitudes =
                                   fijarBase entFaccion magTesoro x (comunMagnitudes com) } } }
        conPops f st = let p = estadoPersistente st; ju = persistenteJuego p
                       in conDerivado st { estadoPersistente = p { persistenteJuego = ju { ppPops = Map.map f (ppPops ju) } } }
        terminadoEn hs = [ t | h <- hs, hechoTipo h == "edificio_terminado", let Tick t = hechoTick h ]
        -- La yácata de Zacapu con una cuadrilla de 500, hasta terminarla.
        (conYacata, hsYacata) = correrDias (construir "yacata" 2 500) 0 400 e0
        diaYacata = case terminadoEn hsYacata of { (t : _) -> t; [] -> -1 }
        def e = maybe (error ("falta " <> T.unpack e)) id (defEdificio eds e)
        culto e = deCulto (def e)

    it "datos/edificios.json carga con cuatro edificios y dos tradiciones" $ do
      fmap idsEdificios edificiosArchivo `shouldBe` Right ["yacata", "fortaleza", "troje", "gran_yacata"]
      map trId (tradiciones eds) `shouldBe` ["purepecha", "catolica"]

    it "la carga acumula los errores de un edificios.json malo" $ do
      let o = A.object
          malo = o [ "tradiciones" A..= [o ["id" A..= ("p" :: Text), "identidades" A..= ["purepecha" :: Text]]]
                   , "edificios" A..= [
                   o [ "id" A..= ("a" :: Text), "costo" A..= o ["valor" A..= ("-1" :: Text), "veintenas" A..= (0 :: Int), "trabajo" A..= ("-5" :: Text)] ]
                 , o [ "id" A..= ("a" :: Text), "costo" A..= o ["valor" A..= ("1" :: Text), "veintenas" A..= (1 :: Int), "insumos" A..= [o []]
                                                                 , "materiales" A..= o ["piedra" A..= ("10" :: Text)]]
                     , "culto" A..= o ["tradicion" A..= ("x" :: Text), "nivel" A..= ("aldea" :: Text), "capacidad" A..= ("1" :: Text)
                                      , "sacerdotes" A..= ("1" :: Text), "referencia" A..= ("1" :: Text)]
                     , "modificadores" A..= [ o ["entidad" A..= ("pueblo" :: Text), "magnitud" A..= ("nada" :: Text), "sumar" A..= ("1" :: Text), "porcentaje" A..= ("1" :: Text)]
                                            , o ["entidad" A..= ("altepetl" :: Text), "magnitud" A..= ("agravio" :: Text), "sumar" A..= ("1" :: Text), "formula" A..= ("cubica" :: Text)] ]
                     , "al_terminar" A..= [ o ["tipo" A..= ("fijar_mag" :: Text), "entidad" A..= ("faccion" :: Text), "magnitud" A..= ("prestigio" :: Text), "valor" A..= ("1" :: Text)] ] ]
                 , o [ "id" A..= ("b" :: Text), "costo" A..= o ["valor" A..= ("1" :: Text), "veintenas" A..= (1 :: Int)]
                     , "modificadores" A..= [ o ["entidad" A..= ("altepetl" :: Text), "magnitud" A..= ("agravio" :: Text), "sumar" A..= ("1" :: Text), "formula" A..= ("por_asistentes" :: Text)] ] ] ] ]
          Validacion errs _ = cargarEdificios "malo.json" catalogoMag malo
      map errRuta errs `shouldMatchList`
        [ "edificios.a", "edificios.a.costo.valor", "edificios.a.costo.trabajo", "edificios.a.costo.veintenas"
        , "edificios.a.costo.insumos", "edificios.a.cuadrilla_maxima"
        , "edificios.a.culto.nivel", "edificios.a.culto.tradicion"
        , "edificios.a.modificadores.0.entidad", "edificios.a.modificadores.0.magnitud", "edificios.a.modificadores.0"
        , "edificios.a.modificadores.1.formula", "edificios.a.al_terminar.0.tipo", "edificios.b.culto" ]

    it "primer corte: un edificio sin trabajo ni materiales avanza con la partida mínima, sin cuadrilla" $ do
      let datoViejo = A.object [ "edificios" A..= [ A.object
                        [ "id" A..= ("monolito" :: Text), "costo" A..= A.object ["valor" A..= ("100" :: Text), "veintenas" A..= (2 :: Int)]
                        , "modificadores" A..= [A.object ["entidad" A..= ("altepetl" :: Text), "magnitud" A..= ("reservas_asedio" :: Text), "sumar" A..= ("1" :: Text)]] ] ] ]
          Validacion [] (Just viejos) = cargarEdificios "viejo.json" catalogoMag datoViejo
          jv = Reglas.Juego.juegoDatos constantesDefault Reglas.Juego.datosVacios { Reglas.Juego.drEdificios = viejos }
          correr cmds est = foldl' (\e t -> fst (paso jv (entornoSimple mapaVacio) (Semilla 1) (Tick t) (if t == 0 then cmds else []) e)) est [0 .. 20]
          hecho = correr (construir "monolito" 1 0) estadoInicial1475
          pobre = correr (construir "monolito" 1 0) (conPresupuestoObras 10 estadoInicial1475)
      altEdificios (ppAltepetl (jue hecho) Map.! AltId 1) `shouldBe` ["monolito"]
      altObra (ppAltepetl (jue pobre) Map.! AltId 1) `shouldBe` Just (Obra "monolito" 0 2 0 (Fijo 0) Map.empty Map.empty [])
      case aplicarCola jv [Sellado (Tick 0) (FaccionId 1) 0 (ConstruirEdificio "monolito" (AltId 1) 5)] estadoInicial1475 of
        (_, _, [Rechazo _]) -> pure ()
        _ -> expectationFailure "una obra sin cuadrilla no acepta cuadrilla"

    it "empezar cobra el valor y retira la cuadrilla de los trabajadores del altépetl" $
      case aplicar1 (ConstruirEdificio "yacata" (AltId 2) 500) e0 of
        (st, _, []) -> do
          baseFaccion magTesoro st `shouldBe` (baseFaccion magTesoro e0 .-. desdeEntero 400)
          altObra (altDe 2 st) `shouldBe` Just (Obra "yacata" 0 8 500 (Fijo 0) Map.empty Map.empty [])
          retiradosDe (jue st) `shouldBe` Map.fromList [(AltId 2, 500)]
          Map.lookup (AltId 2) (trabajadoresDe constantesDefault (jue st)) `shouldBe` Just 2500
        (_, _, rs) -> expectationFailure ("rechazado: " <> show rs)

    it "rechazos sin daño: cuadrilla fuera de rango o sin gente, sin tesoro, otra obra, máximo" $ do
      let enObra  = (\(st, _, _) -> st) (aplicar1 (ConstruirEdificio "troje" (AltId 2) 100) e0)
          conGran = let p = estadoPersistente e0; ju = persistenteJuego p
                    in e0 { estadoPersistente = p { persistenteJuego = ju { ppAltepetl =
                              Map.adjust (\a -> a { altEdificios = ["gran_yacata"] }) (AltId 1) (ppAltepetl ju) } } }
          casos = [ (e0, ConstruirEdificio "yacata" (AltId 2) 0)
                  , (e0, ConstruirEdificio "yacata" (AltId 2) 601)
                  , (e0, ConstruirEdificio "gran_yacata" (AltId 2) 2000)
                  , (conTesoro (desdeEntero 100) e0, ConstruirEdificio "yacata" (AltId 2) 500)
                  , (e0, ConstruirEdificio "palacio" (AltId 2) 1)
                  , (e0, ConstruirEdificio "yacata" (AltId 9) 1)
                  , (enObra, ConstruirEdificio "yacata" (AltId 2) 500)
                  , (conGran, ConstruirEdificio "gran_yacata" (AltId 1) 1000) ]
      forM_ casos $ \(st, c) -> case aplicar1 c st of
        (st', _, [Rechazo _]) -> foto st' `shouldBe` foto st
        _ -> expectationFailure ("se esperaba un rechazo: " <> show c)

    it "una obra sin material a su alcance se acepta y espera; no avanza su acopio" $ do
      let sinMaterial = e0 { estadoDerivado = (estadoDerivado e0) { derivadoJuego = (derivadoJuego (estadoDerivado e0)) { dpMateriales = Map.empty } } }
      case aplicar1 (ConstruirEdificio "yacata" (AltId 2) 500) sinMaterial of
        (st, _, []) -> fmap obAcopio (altObra (altDe 2 st)) `shouldBe` Just Map.empty
        (_, _, rs)  -> expectationFailure ("rechazado: " <> show rs)

    it "tributo en especie: el material llega con retraso, se cobra su transporte y quien lo envía pone gente y agravio" $ do
      let pedir = [Sellado (Tick 1) (FaccionId 1) 0 (PedirTributoObra (AltId 2) "piedra" (AltId 1) 300)]
          -- Sin partida de obras la cuadrilla local no trabaja: todo el material es tributo.
          (s0, _) = correrDias (construir "yacata" 2 500) 0 0 (conPresupuestoObras 0 e0)
          (s1, _) = correrDias pedir 1 1 s0
          (s20, _) = correrDias [] 2 20 s1
          obra st = maybe (error "sin obra") id (altObra (altDe 2 st))
          entregas = obEnCamino (obra s20)
          dist = Map.lookup (AltId 2) (dpDistancias (derivadoJuego (estadoDerivado s1))) >>= Map.lookup (AltId 1)
          agravioDe st = [ modAporte m | m <- maybe [] almacenMods (Map.lookup (entRefAlt (AltId 1), magTasaAgravio) (alm st))
                                       , modFuente m == fuenteTributo (AltId 2) "piedra" ]
      Map.toList (obTributos (obra s1)) `shouldBe` [("piedra", TributoObra (AltId 1) 300)]
      Map.lookup (AltId 1) (retiradosDe (jue s1)) `shouldBe` Just 300
      agravioDe s1 `shouldBe` [Aporte (cAgravioTributoObra constantesDefault) (Fijo 0)]
      dist `shouldSatisfy` (/= Nothing)
      case (entregas, dist) of
        ([en], Just d) -> do
          enMaterial en `shouldBe` "piedra"
          enLlega en `shouldBe` (20 + diasDeTransporte constantesDefault d)
          enCosto en `shouldBe` (cCostoTransporte constantesDefault .*. enCantidad en .*. d)
          -- Llega el día previsto y el tesoro paga el transporte.
          let dia = fromIntegral (enLlega en)
              antes = correrDias [] 21 (dia - 1) s20
              (llego, _) = correrDias [] dia dia (fst antes)
          Map.findWithDefault (Fijo 0) "piedra" (obAcopio (obra (fst antes))) `shouldBe` Fijo 0
          Map.findWithDefault (Fijo 0) "piedra" (obAcopio (obra llego)) `shouldSatisfy` (> Fijo 0)
          -- Sin tesoro para el transporte, la entrega espera.
          let (sinPagar, _) = correrDias [] dia dia (conTesoro (Fijo 0) (fst antes))
          Map.findWithDefault (Fijo 0) "piedra" (obAcopio (obra sinPagar)) `shouldBe` Fijo 0
          length (obEnCamino (obra sinPagar)) `shouldSatisfy` (>= 1)
        _ -> expectationFailure ("se esperaba una entrega: " <> show entregas)

    it "al terminar la obra, quien envía tributo recupera su gente y su agravio, con modificador_terminado" $ do
      let pedir = [Sellado (Tick 1) (FaccionId 1) 0 (PedirTributoObra (AltId 2) "piedra" (AltId 1) 300)]
          (s0, _) = correrDias (construir "yacata" 2 500) 0 0 e0
          (s1, _) = correrDias pedir 1 1 s0
          (fin, hs) = correrDias [] 2 600 s1
      altObra (altDe 2 fin) `shouldBe` Nothing
      altEdificios (altDe 2 fin) `shouldBe` ["yacata"]
      Map.lookup (AltId 1) (retiradosDe (jue fin)) `shouldBe` Nothing
      [ modFuente m | m <- maybe [] almacenMods (Map.lookup (entRefAlt (AltId 1), magTasaAgravio) (alm fin))
                    , fuenteTipo (modFuente m) == "tributo_obra" ] `shouldBe` []
      [ () | h <- hs, hechoTipo h == "modificador_terminado", Map.lookup "fuente" (hechoParams h) == Just "tributo_obra" ]
        `shouldBe` [()]

    it "rechazos sin daño del tributo: sin obra, material no pedido, a sí mismo, inexistente, sin gente, repetido, recién empezada" $ do
      let (s0, _) = correrDias (construir "yacata" 2 500) 0 0 e0
          (conPedido, _, _) = aplicar1 (PedirTributoObra (AltId 2) "piedra" (AltId 1) 300) s0
          recienEmpezada = (\(st, _, _) -> st) (aplicar1 (ConstruirEdificio "troje" (AltId 3) 100) e0)
          casos = [ (s0, PedirTributoObra (AltId 1) "piedra" (AltId 2) 100)
                  , (s0, PedirTributoObra (AltId 2) "cobre" (AltId 1) 100)
                  , (s0, PedirTributoObra (AltId 2) "piedra" (AltId 2) 100)
                  , (s0, PedirTributoObra (AltId 2) "piedra" (AltId 9) 100)
                  , (s0, PedirTributoObra (AltId 2) "piedra" (AltId 1) 0)
                  , (s0, PedirTributoObra (AltId 2) "piedra" (AltId 1) 100000)
                  , (conPedido, PedirTributoObra (AltId 2) "piedra" (AltId 3) 100)
                  , (recienEmpezada, PedirTributoObra (AltId 3) "madera" (AltId 1) 100) ]
      forM_ casos $ \(st, c) -> case aplicar1 c st of
        (st', _, [Rechazo _]) -> foto st' `shouldBe` foto st
        _ -> expectationFailure ("se esperaba un rechazo: " <> show c)

    it "ley de la obra acotada con tributo: el acopio más lo que viene en camino no pasa de lo pedido" $ do
      let pedir = [ Sellado (Tick 1) (FaccionId 1) 0 (PedirTributoObra (AltId 2) "piedra" (AltId 1) 600)
                  , Sellado (Tick 1) (FaccionId 1) 1 (PedirTributoObra (AltId 2) "madera" (AltId 3) 300) ]
          (s0, _) = correrDias (construir "yacata" 2 500) 0 0 e0
          trazas = scanl (\e t -> fst (paso j ent (Semilla 1) (Tick t) (if t == 1 then pedir else []) e)) s0 [1 .. 300]
          d = def "yacata"
          bien o = and [ Map.findWithDefault (Fijo 0) g (obAcopio o)
                         .+. foldl' (.+.) (Fijo 0) [ enCantidad en | en <- obEnCamino o, enMaterial en == g ] <= m
                       | (g, m) <- Map.toList (deMateriales d) ]
      all bien [ o | st <- trazas, Just o <- [altObra (altDe 2 st)] ] `shouldBe` True

    it "el pedido de tributo coincide con su archivo dorado y está en el catálogo" $ do
      A.decode dorTributo `shouldBe` Just (A.toJSON (PedirTributoObra (AltId 2) "piedra" (AltId 1) 300))
      A.decode dorTributo `shouldBe` Just (PedirTributoObra (AltId 2) "piedra" (AltId 1) 300)
      [ dpNombre p | d <- catalogoComandosConMateriales ["yacata"] ["madera", "piedra"], dcTipo d == "pedir_tributo_obra", p <- dcParametros d ]
        `shouldBe` ["altepetl", "material", "fuente", "cuadrilla"]

    it "la obra extrae su material, trabaja y termina; nunca antes de su duración mínima" $ do
      diaYacata `shouldSatisfy` (>= 7 * 20)
      altObra (altDe 2 conYacata) `shouldBe` Nothing
      altEdificios (altDe 2 conYacata) `shouldBe` ["yacata"]
      retiradosDe (jue conYacata) `shouldBe` Map.empty

    it "ley de la obra acotada: el acopio no pasa de lo pedido y el avance no decrece" $ do
      let trazas = scanl (\e t -> fst (paso j ent (Semilla 1) (Tick t) (if t == 0 then construir "yacata" 2 500 else []) e)) e0 [0 .. 200]
          obras = [ o | st <- trazas, Just o <- [altObra (altDe 2 st)] ]
          d = def "yacata"
      all (\o -> and [ Map.findWithDefault (Fijo 0) g (obAcopio o) <= m | (g, m) <- Map.toList (deMateriales d) ]) obras `shouldBe` True
      and (zipWith (\a b -> obAvance b >= obAvance a && obTrabajo b >= obTrabajo a) obras (drop 1 obras)) `shouldBe` True
      all (\o -> obTrabajo o <= deTrabajo d) obras `shouldBe` True

    it "factor escaso: la cuadrilla baja la producción solo donde deja tierra sin trabajar" $ do
      let q st = foldl' (.+.) (Fijo 0) [ base (magProduccion b) st | b <- bienesDe terrenosArchivo ]
          base m st = maybe (Fijo 0) almacenBase (Map.lookup (entFaccion, m) (alm st))
          -- Uruapan con menos gente: ahí faltan brazos.
          pocos = conPops (\pop -> if popId pop == PopId 5 then pop { popTamano = 4000 } else pop) e0
          celdas est a = Map.findWithDefault [] (AltId a) (dpCeldas (derivadoJuego (estadoDerivado est)))
          tierra est a = foldl' (.+.) (Fijo 0) (map ctTrabajadores (celdas est a))
          brazos est a = fi (Map.findWithDefault 0 (AltId a) (trabajadoresDe constantesDefault (jue est)))
          caso (est, a, c) =
            let (sin, _) = correrDias [] 0 20 est
                (st, _)  = correrDias (construir "troje" a c) 0 20 est
            in (brazos est a .-. fi c < tierra est a, q st < q sin, q st == q sin)
          casos = [ (est, a, c) | est <- [e0, pocos], a <- [1, 2, 3], c <- [100, 300] ]
      forM_ (zip [0 :: Int ..] casos) $ \(k, x) -> case caso x of
        (True, baja, _)   -> (k, baja) `shouldBe` (k, True)
        (False, _, igual) -> (k, igual) `shouldBe` (k, True)
      -- Hay de los dos casos: si no, la prueba no probaría nada.
      let faltan = [ () | x <- casos, let (f, _, _) = caso x, f ]
      (null faltan, length faltan == length casos) `shouldBe` (False, False)

    it "el sustento: con poca partida de obras trabaja menos gente y la obra tarda más; sin partida no avanza" $ do
      let (lenta, hsL) = correrDias (construir "yacata" 2 500) 0 600 (conPresupuestoObras 6 e0)
          (parada, _)  = correrDias (construir "yacata" 2 500) 0 100 (conPresupuestoObras 0 e0)
      case terminadoEn hsL of
        (t : _) -> t `shouldSatisfy` (> diaYacata)
        []      -> altObra (altDe 2 lenta) `shouldSatisfy` (/= Nothing)
      fmap obAvance (altObra (altDe 2 parada)) `shouldBe` Just 0

    it "la yácata atiende a los fieles purépechas y el desglose nombra la obra" $ do
      let fieles = Map.findWithDefault (Fijo 0) (AltId 2, "purepecha") (dpFielesLocal (derivadoJuego (estadoDerivado conYacata)))
      fieles `shouldSatisfy` (> Fijo 0)
      efectivo (entRefAlt (AltId 2)) magTasaAgravio conYacata `shouldSatisfy` (< Fijo 0)
      efectivo (entRefAlt (AltId 2)) magProduccionAlt conYacata `shouldSatisfy` (> fi 1)
      [ modFuente m | m <- maybe [] almacenMods (Map.lookup (entRefAlt (AltId 2), magTasaAgravio) (alm conYacata)) ]
        `shouldBe` [fuenteEdificio "yacata" (AltId 2)]

    it "sin sacerdotes una yácata no atiende a nadie" $ do
      let sinSacerdotes = conPops (\pop -> if popEstrato pop == "sacerdote" then pop { popTamano = 0 } else pop) conYacata
          (st, _) = correrDias [] 401 420 sinSacerdotes
      efectivo (entRefAlt (AltId 2)) magTasaAgravio st `shouldBe` Fijo 0

    it "la religión decide: con gradiente 1 nadie va a la yácata, y nadie va a un templo de otra tradición" $ do
      let catolicos = conPops (\pop -> pop { popGradiente = uno }) conYacata
          (st, _) = correrDias [] 401 420 catolicos
          trPurepecha = head [ t | t <- tradiciones eds, trId t == "purepecha" ]
          trCatolica  = head [ t | t <- tradiciones eds, trId t == "catolica" ]
          popDe i = jue conYacata `seq` (ppPops (jue conYacata) Map.! PopId i)
      Map.findWithDefault (Fijo 0) (AltId 2, "purepecha") (dpFielesLocal (derivadoJuego (estadoDerivado catolicos))) `shouldBe` Fijo 0
      efectivo (entRefAlt (AltId 2)) magTasaAgravio st `shouldBe` Fijo 0
      afinidad trCatolica (popDe 3) `shouldBe` Fijo 0
      afinidad trPurepecha (popDe 4) `shouldBe` Fijo 0          -- los hñähñú no van a la yácata
      afinidad trPurepecha (popDe 3) `shouldBe` uno

    it "ley: nadie asiste dos veces a los templos locales" $ do
      let todos = conPops id conYacata
          locales = foldl' (.+.) (Fijo 0) (Map.elems (dpFielesLocal (derivadoJuego (estadoDerivado todos))))
          poblacion = fi (sum (map popTamano (Map.elems (ppPops (jue todos)))))
      locales `shouldSatisfy` (<= poblacion)

    it "el centro ceremonial suma fieles de todo el reino, con menos peso los lejanos" $ do
      let conGran = conDerivado (let p = estadoPersistente e0; ju = persistenteJuego p
                                 in e0 { estadoPersistente = p { persistenteJuego = ju { ppAltepetl =
                                           Map.adjust (\a -> a { altEdificios = ["gran_yacata"] }) (AltId 1) (ppAltepetl ju) } } })
          centro = Map.findWithDefault (Fijo 0) (AltId 1, "purepecha") (dpFielesCentro (derivadoJuego (estadoDerivado conGran)))
          purepechas = fi (sum [ popTamano q | q <- Map.elems (ppPops (jue conGran)), popIdentidad q == "purepecha" ])
          deTzintzuntzan = fi (sum [ popTamano q | q <- Map.elems (ppPops (jue conGran)), popIdentidad q == "purepecha", popAltepetl q == AltId 1 ])
      centro `shouldSatisfy` (> deTzintzuntzan)
      centro `shouldSatisfy` (< purepechas)
      let (st, _) = correrDias [] 0 0 conGran
      efectivo entFaccion magLegitimidad st `shouldSatisfy` (> fi 50)

    it "ley del beneficio: no decrece con las copias ni con los fieles, y la copia n + 1 aporta menos que la n" $
      property $ forAll (choose (1, 30)) $ \n -> forAll (choose (0, 200000)) $ \f -> forAll (choose (0, 2000)) $ \sac ->
        let cu = culto "yacata"
            a = Aporte (fi (-7)) (Fijo 0)
            v k fs = sumando (beneficio FPorAsistentes cu k (fi fs) (fi sac) a)
            l k = sumando (beneficio FLogaritmica Nothing k (Fijo 0) (Fijo 0) a)
            margen g k = g (k + 1) .-. g k
        in v (n + 1) f <= v n f && v n (f + 1000) <= v n f
           && l (n + 1) <= l n
           && margen l (n + 1) >= margen l n
           && sumando (beneficio FLineal Nothing n (Fijo 0) (Fijo 0) a) == fi (-7 * n)

    it "guardar a mitad de una obra con cuadrilla y cargar sigue igual" $ do
      let (mitad, _) = correrDias (construir "yacata" 2 500) 0 63 e0
          cargado = either (error . show) id (cargar j mapa (guardar mitad))
          seguir st = fst (correrDias [] 64 300 st)
      foto cargado `shouldBe` foto mitad
      foto (seguir cargado) `shouldBe` foto (seguir mitad)

    it "guardados anteriores: una obra sin cuadrilla ni acopio y un pop sin gradiente cargan con 0" $ do
      (A.decode "{\"obEdificio\":\"yacata\",\"obAvance\":3,\"obTotal\":8}" :: Maybe Obra)
        `shouldBe` Just (Obra "yacata" 3 8 0 (Fijo 0) Map.empty Map.empty [])
      (A.decode "{\"popId\":1,\"popAltepetl\":1,\"popIdentidad\":\"purepecha\",\"popEstrato\":\"comun\",\"popTamano\":10,\"popLealtad\":\"50\"}" :: Maybe Pop)
        `shouldBe` Just (Pop (PopId 1) (AltId 1) "purepecha" "comun" 10 (fi 50) (Fijo 0))

    it "el comando coincide con su archivo dorado; sin cuadrilla, vale 0" $ do
      A.decode dorConstruir `shouldBe` Just (A.toJSON (ConstruirEdificio "fortaleza" (AltId 1) 300))
      A.decode dorConstruir `shouldBe` Just (ConstruirEdificio "fortaleza" (AltId 1) 300)
      A.decode "{\"tipo\":\"construir_edificio\",\"edificio\":\"troje\",\"altepetl\":2}" `shouldBe` Just (ConstruirEdificio "troje" (AltId 2) 0)

    it "el catálogo ofrece los edificios y la cuadrilla, y los sistemas pasan validarOrdenSistemas" $ do
      [ (dpNombre p, dpTipo p) | d <- catalogoComandosCon (idsEdificios eds), dcTipo d == "construir_edificio", p <- dcParametros d ]
        `shouldBe` [ ("edificio", POpcion ["yacata", "fortaleza", "troje", "gran_yacata"])
                   , ("altepetl", PEntero 1 1000000), ("cuadrilla", PEntero 0 100000) ]
      validarOrdenSistemas (juegoCatalogoMag j) (juegoSistemas j) `shouldBe` []

  describe "reglas: producción de bienes por territorio (hito 3)" $ do
    let mapa = conCostoDeTerreno terrenosArchivo (either (error . show) id (proveedorHexagonal datosMapa1475))
        ent  = entornoSimple mapa
        dr   = Reglas.Juego.datosVacios { Reglas.Juego.drTerrenos = terrenosArchivo }
        j    = Reglas.Juego.juegoDatos constantesDefault dr
        conDerivado e = e { estadoDerivado = derivar j (entGrafo ent) (estadoTick e) (estadoPersistente e) }
        e0   = conDerivado estadoInicial1475
        correrDias desde hasta e = foldl' (\st t -> fst (paso j ent (Semilla 1) (Tick t) [] st)) e [desde .. hasta]
        alm st = comunMagnitudes (persistenteComun (estadoPersistente st))
        base m st = maybe (Fijo 0) almacenBase (Map.lookup (entFaccion, m) (alm st))
        llano = CeldaTrabajo 1 (fi 500) (Map.fromList [("maiz", fi 40), ("mantas", fi 4)])
        lago  = CeldaTrabajo 2 (fi 400) (Map.fromList [("pescado", fi 20), ("sal", fi 3)])

    it "los bienes del territorio son los seis de V5 y están en el catálogo del juego" $ do
      bienesDe terrenosArchivo `shouldBe` ["cobre", "maiz", "mantas", "obsidiana", "pescado", "sal"]
      all (`Map.member` juegoCatalogoMag j) (concat [ [magExistencias b, magProduccion b] | b <- bienesDe terrenosArchivo ])
        `shouldBe` True

    it "el factor escaso: con 700 trabajadores, el llano entero y medio lago" $ do
      ordenarCeldas [lago, llano] `shouldBe` [llano, lago]
      produccionCeldas 700 [llano, lago]
        `shouldBe` Map.fromList [("maiz", fi 40), ("mantas", fi 4), ("pescado", fi 10), ("sal", Fijo 15000)]
      produccionCeldas 0 [llano, lago] `shouldBe` Map.empty
      produccionCeldas 100000 [llano, lago]
        `shouldBe` Map.fromList [("maiz", fi 40), ("mantas", fi 4), ("pescado", fi 20), ("sal", fi 3)]
      produccionCeldas 100000 [] `shouldBe` Map.empty

    it "ley: un trabajador más nunca baja la producción de ningún bien" $
      property $ forAll genCeldas $ \cs -> forAll (choose (0, 20000)) $ \w ->
        let antes = produccionCeldas w (ordenarCeldas cs)
            despues = produccionCeldas (w + 1) (ordenarCeldas cs)
        in all (\(b, q) -> Map.findWithDefault (Fijo 0) b despues >= q) (Map.toList antes)

    it "ley: una celda más nunca baja la producción total (Q_a)" $
      property $ forAll genCeldas $ \cs -> forAll (choose (0, 20000)) $ \w ->
        not (null cs) ==>
          let sinUna = tail cs
          in totalProduccion (produccionCeldas w (ordenarCeldas cs))
               >= totalProduccion (produccionCeldas w (ordenarCeldas sinUna))

    it "trabajadores: un cuarto de cada pop productivo; la nobleza no trabaja" $
      trabajadoresDe constantesDefault escenario1475
        `shouldBe` Map.fromList [(AltId 1, 6750), (AltId 2, 3000), (AltId 3, 4500)]

    it "cada celda la trabaja a lo sumo un altépetl, dentro del radio" $ do
      let cs = dpCeldas (derivadoJuego (estadoDerivado e0))
          todas = concatMap (map ctCelda) (Map.elems cs)
      length todas `shouldBe` length (Map.keys (Map.fromList (zip todas todas)))
      Map.keys cs `shouldBe` [AltId 1, AltId 2, AltId 3]
      all (\c -> ordenarCeldas c == c) (Map.elems cs) `shouldBe` True

    it "una veintena produce, la producción se escribe y se suma a las existencias, que nunca bajan" $ do
      let s1 = correrDias 0 0 e0
          s2 = correrDias 1 20 s1
          bs = bienesDe terrenosArchivo
      base (magProduccion "maiz") s1 `shouldSatisfy` (> Fijo 0)
      forM_ bs $ \b -> do
        base (magExistencias b) s1 `shouldBe` base (magProduccion b) s1
        base (magExistencias b) s2 `shouldBe` (base (magExistencias b) s1 .+. base (magProduccion b) s2)
        base (magExistencias b) s2 `shouldSatisfy` (>= base (magExistencias b) s1)
        base (magExistencias b) s1 `shouldSatisfy` (>= Fijo 0)

    it "sin tabla de terrenos no se produce nada ni se recorre el mapa" $ do
      let jv = Reglas.Juego.juego constantesDefault
          s1 = fst (paso jv ent (Semilla 1) (Tick 0) [] estadoInicial1475)
      dpCeldas (derivadoJuego (estadoDerivado s1)) `shouldBe` Map.empty
      [ k | (k, _) <- Map.toList (alm s1), snd k == magProduccion "maiz" ] `shouldBe` []

    it "las obras mueven la producción: +10 % en un altépetl sube lo que produce" $ do
      let mods = [ Modificador 0 magProduccionAlt (entRefAlt (AltId a)) (Aporte (Fijo 0) (Fijo 1000))
                     (fuenteEdificio "yacata" (AltId a)) Nothing Nothing Nothing AlcancePropia | a <- [1, 2, 3] ]
          conMods e = let p = estadoPersistente e; com = persistenteComun p
                      in e { estadoPersistente = p { persistenteComun = com { comunMagnitudes = agregarVarios mods (comunMagnitudes com) } } }
          q st = base (magProduccion "maiz") st
          normal = q (correrDias 0 0 e0)
          conObra = q (correrDias 0 0 (conMods e0))
      cercaCon 3 conObra (fromIntegral (let Fijo n = normal in n) * 1.1 / 10000)

    it "guardar a mitad de veintena y cargar: el derivado y la producción siguen igual" $ do
      let mitad = correrDias 0 33 e0
          cargado = either (error . show) id (cargar j mapa (guardar mitad))
          seguir = correrDias 34 60
      derivadoJuego (estadoDerivado cargado) `shouldBe` derivadoJuego (estadoDerivado mitad)
      alm (seguir cargado) `shouldBe` alm (seguir mitad)

    it "los sistemas del juego con terrenos pasan validarOrdenSistemas" $
      validarOrdenSistemas (juegoCatalogoMag j) (juegoSistemas j) `shouldBe` []

  describe "reglas: tablas de casos del hito 0a (prototipo HTML)" $ do
    tablas <- runIO (fmap (>>= parseEither parseTablas)
                          (A.eitherDecodeFileStrict "test/tablas_hito0.json"))
    let cerca = cercaCon 10

    it "tasas: taxM y tShare coinciden con el prototipo en la rejilla 1..5" $
      either expectationFailure (\tb -> forM_ (tbTasas tb) $ \(t, i, cap, tm, ts) -> do
        cerca (taxM constantesDefault (Tasas t i) cap) tm
        cerca (tShare (Tasas t i) cap) ts) tablas

    it "eficiencia: los puntos coinciden con el prototipo en 810 combinaciones" $
      either expectationFailure (\tb -> forM_ (tbEficiencia tb) $ \ce ->
        eficienciaPuntos constantesDefault (ceAdminGob ce) (fi (ceDistancia ce))
                         (cePresupuestoAdm ce >= cUmbralPresupuestoAdm constantesDefault)
                         (ceAdminCazonci ce)
                         (fraccionAjena (cePurepecha ce) (ceAjenos ce))
          `shouldBe` cePuntos ce) tablas

    -- La tolerancia de esta tabla es 0,002 por veintena, y no 0,001: el factor
    -- de tasas se redondea a 0,0001 y la capital tiene 30 000 pobladores, así
    -- que el error llega a 0,0001 × 30 000 × 0,012 ÷ 18 ≈ 0,002 como máximo.
    it "ingreso: el total por veintena coincide con el prototipo" $
      either expectationFailure (\tb -> forM_ (tbIngreso tb) $ \ci -> do
        let tasas = Tasas (ciTributo ci) (ciImpuesto ci)
            suma = foldl' (.+.) (Fijo 0)
              [ ingresoPoblacion constantesDefault tasas (not (aiSujeta a))
                  (eficiencia constantesDefault (aiAdminGob a) (fi (aiDistancia a))
                              (ciPresupuestoAdm ci >= cUmbralPresupuestoAdm constantesDefault)
                              3 (fraccionAjena (aiPurepecha a) (aiAjenos a)))
                  (aiPurepecha a + aiAjenos a)
              | a <- ciAltepetl ci ]
        cercaCon 20 (suma ./. cTicksPorAnio constantesDefault) (ciTotal ci / 18)) tablas

    it "gastos: el presupuesto por veintena coincide con el prototipo" $
      either expectationFailure (\tb -> forM_ (tbGastos tb) $ \(ej, adm, dip, total) ->
        cerca (gastoPunto constantesDefault (ej + adm + dip) ./. cTicksPorAnio constantesDefault)
              (total / 18)) tablas

    it "agravio: cada componente y la suma por veintena coinciden con el prototipo" $
      either expectationFailure (\tb -> forM_ (tbAgravio tb) $ \ca -> do
          let p = popParts constantesDefault (Tasas (cgTributo ca) (cgImpuesto ca)) (cgCapital ca)
                           (cgEstrato ca) (cgIdentidad ca) (fi (cgDistancia ca)) (cgAdminGob ca)
              comps = cgComponentes ca
          cerca (paTributo p)    (comps Map.! "Tributo")
          cerca (paImpuesto p)   (comps Map.! "Impuesto interno")
          cerca (paGobernador p) (comps Map.! "Gobernador")
          cerca (paIdentidad p)  (comps Map.! "Identidad ajena")
          cerca (paDistancia p)  (comps Map.! "Distancia a la capital")
          cerca (deltaAgravio constantesDefault p) (cgPorVeintena ca)) tablas

-- | Dos cifras cuentan como iguales si difieren como mucho `tol` unidades de
-- punto fijo (cada una vale 0,0001): el punto fijo redondea en cada operación.
cercaCon :: Integer -> Fijo -> Double -> Expectation
cercaCon tol (Fijo n) x = abs (fromIntegral n - x * 10000) `shouldSatisfy` (<= fromIntegral tol)

-- | La fracción de pobladores de identidad ajena, como la calcula el estado.
fraccionAjena :: Int -> Int -> Fijo
fraccionAjena purepecha ajenos
  | purepecha + ajenos > 0 = fi ajenos ./. fi (purepecha + ajenos)
  | otherwise              = Fijo 0

-- | El estado con otro gobernador en un altépetl.
conGobernador :: AltId -> PerId -> Estado Purepecha -> Estado Purepecha
conGobernador a g e =
  let p  = estadoPersistente e
      j  = persistenteJuego p
      j' = j { ppAltepetl = Map.adjust (\x -> x { altGobernador = Just g }) a (ppAltepetl j) }
      p' = p { persistenteJuego = j' }
  in e { estadoPersistente = p', estadoOrigen = Origen (Tick 0) p' }

-- | Las tablas de `test/tablas_hito0.json` (generadas por
-- `hito_0/tablas/generar.mjs`).
data Tablas = Tablas
  { tbTasas      :: [(Int, Int, Bool, Double, Double)]
    -- ^ tributo, impuesto, capital, taxM, tShare
  , tbEficiencia :: [CasoEficiencia]
  , tbIngreso    :: [CasoIngreso]
  , tbGastos     :: [(Int, Int, Int, Double)]
    -- ^ ejército, administración, diplomacia, total
  , tbAgravio    :: [CasoAgravio]
  }

data CasoEficiencia = CasoEficiencia
  { ceAdminGob       :: Int
  , ceDistancia      :: Int
  , cePresupuestoAdm :: Int
  , ceAdminCazonci   :: Int
  , cePurepecha      :: Int
  , ceAjenos         :: Int
  , cePuntos         :: Int
  }

data AltIngreso = AltIngreso
  { aiSujeta     :: Bool
  , aiAdminGob   :: Int
  , aiDistancia  :: Int
  , aiPurepecha  :: Int
  , aiAjenos     :: Int
  }

data CasoIngreso = CasoIngreso
  { ciTributo        :: Int
  , ciImpuesto       :: Int
  , ciPresupuestoAdm :: Int
  , ciAltepetl       :: [AltIngreso]
  , ciTotal          :: Double
  }

data CasoAgravio = CasoAgravio
  { cgTributo     :: Int
  , cgImpuesto    :: Int
  , cgCapital     :: Bool
  , cgEstrato     :: Text
  , cgIdentidad   :: Text
  , cgDistancia   :: Int
  , cgAdminGob    :: Int
  , cgComponentes :: Map.Map Text Double
  , cgPorVeintena :: Double
  }

parseTablas :: A.Value -> Parser Tablas
parseTablas = withObject "tablas" $ \o -> do
  cs <- o .: "casos"
  withObject "casos" (\c -> Tablas
    <$> (c .: "tasas"                >>= traverse fTasa)
    <*> (c .: "eficiencia"           >>= traverse fEficiencia)
    <*> (c .: "ingreso_total"        >>= traverse fIngreso)
    <*> (c .: "gastos"               >>= traverse fGasto)
    <*> (c .: "agravio_por_veintena" >>= traverse fAgravio)) cs
  where
    fTasa = withObject "tasa" $ \o ->
      (,,,,) <$> o .: "tributo" <*> o .: "impuesto" <*> o .: "capital"
             <*> o .: "taxM" <*> o .: "tShare"
    fEficiencia = withObject "eficiencia" $ \o ->
      CasoEficiencia <$> o .: "adminGobernador" <*> o .: "distancia"
                     <*> o .: "presupuestoAdministracion" <*> o .: "adminCazonci"
                     <*> o .: "pobladoresPurepecha" <*> o .: "pobladoresAjenos"
                     <*> o .: "puntos"
    fIngreso = withObject "ingreso" $ \o ->
      CasoIngreso <$> o .: "tributo" <*> o .: "impuesto" <*> o .: "presupuestoAdministracion"
                  <*> (o .: "altepetl" >>= traverse fAlt) <*> o .: "totalIncome"
    fAlt = withObject "altepetl" $ \a ->
      AltIngreso <$> a .: "sujeta" <*> a .: "adminGobernador" <*> a .: "distancia"
                 <*> a .: "pobladoresPurepecha" <*> a .: "pobladoresAjenos"
    fGasto = withObject "gasto" $ \o ->
      (,,,) <$> o .: "ejercito" <*> o .: "administracion" <*> o .: "diplomacia"
            <*> o .: "totalExpenses"
    fAgravio = withObject "agravio" $ \o ->
      CasoAgravio <$> o .: "tributo" <*> o .: "impuesto" <*> o .: "capital"
                  <*> o .: "estrato" <*> o .: "identidad" <*> o .: "distancia"
                  <*> o .: "adminGobernador" <*> o .: "componentes" <*> o .: "porVeintena"
