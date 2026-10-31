{-# LANGUAGE OverloadedStrings #-}
module Main where

import Control.Monad (forM_)
import Data.List (foldl')
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Test.Hspec

import Motor.Base
import Motor.Carga (validarOrdenSistemas, Validacion (..), ErrorCarga (..))
import Motor.Autoridad
import Motor.Protocolo (DeclComando (..))
import qualified Data.Aeson as A
import Data.Aeson.Types (Parser, parseEither, withObject, (.:))
import Motor.Estado
import Motor.Juego
import Motor.Magnitudes
import Motor.Mapa
import Motor.Guion (entornoSimple)

import qualified Reglas.Juego
import Reglas.Juego (catalogoMag)
import Reglas.Base
import Reglas.Comando
import Reglas.Constantes
import Reglas.Escenario
import Reglas.Estado
import Reglas.Formulas

mapaVacio :: Mapa
mapaVacio = Mapa mempty mempty (Fijo 10000)

main :: IO ()
main = hspec $ do
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
