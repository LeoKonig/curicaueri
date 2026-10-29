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
      -- estratoW nobleza = 0.5, común = 1.0
      dNobleza .*. fi 2 `shouldBe` dComun

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
    -- El neto (720 − 420) se divide una sola vez entre 18: 1000 + 300 ÷ 18 =
    -- 1016,6666… El punto fijo trunca a 1016,6666 (resolución 0,0001).
    it "tick 0 a tasas neutras: 1000 + (60 000 × 0,012 − 70 × 6) ÷ 18 = 1016,6666" $ do
      let j = Reglas.Juego.juego constantesDefault
          (s1, _) = paso j (entornoSimple mapaVacio) (Semilla 1) (Tick 0) [] estadoInicial1475
      baseFaccion magTesoro s1 `shouldBe` Fijo 10166666

  describe "reglas: tablas de casos del hito 0a (prototipo HTML)" $ do
    tablas <- runIO (fmap (>>= parseEither parseTablas)
                          (A.eitherDecodeFileStrict "test/tablas_hito0.json"))
    let -- Dos cifras cuentan como iguales si difieren menos de 0,001: el punto
        -- fijo tiene resolución 0,0001 y cada operación redondea.
        cercaCon :: Integer -> Fijo -> Double -> Expectation
        cercaCon tol (Fijo n) x = abs (fromIntegral n - x * 10000) `shouldSatisfy` (<= fromIntegral tol)
        cerca = cercaCon 10

    it "tasas: taxM y tShare coinciden con el prototipo en la rejilla 1..5" $
      either expectationFailure (\tb -> forM_ (tbTasas tb) $ \(t, i, cap, tm, ts) -> do
        cerca (taxM constantesDefault (Tasas t i) cap) tm
        cerca (tShare (Tasas t i) cap) ts) tablas

    -- La tolerancia de esta tabla es 0,002 por veintena, y no 0,001: el factor
    -- de tasas se redondea a 0,0001 y la capital tiene 30 000 pobladores, así
    -- que el error llega a 0,0001 × 30 000 × 0,012 ÷ 18 ≈ 0,002 como máximo.
    it "ingreso: el total por veintena coincide con el prototipo" $
      either expectationFailure (\tb -> forM_ (tbIngreso tb) $ \(t, i, pops, total) -> do
        let tasas = Tasas t i
            suma  = foldl' (.+.) (Fijo 0)
                      [ ingresoPoblacion constantesDefault tasas (not sujeta) pop
                      | (pop, sujeta) <- pops ]
        cercaCon 20 (suma ./. cTicksPorAnio constantesDefault) (total / 18)) tablas

    it "gastos: el presupuesto por veintena coincide con el prototipo" $
      either expectationFailure (\tb -> forM_ (tbGastos tb) $ \(ej, adm, dip, total) ->
        cerca (gastoPunto constantesDefault (ej + adm + dip) ./. cTicksPorAnio constantesDefault)
              (total / 18)) tablas

    it "agravio: cada componente y la suma por veintena coinciden con el prototipo" $
      either expectationFailure (\tb -> forM_ (tbAgravio tb) $
        \(t, i, cap, estrato, identidad, dist, comps, porVeintena) -> do
          let p = popParts constantesDefault (Tasas t i) cap estrato identidad (fi dist)
          cerca (paTributo p)   (comps Map.! "Tributo")
          cerca (paImpuesto p)  (comps Map.! "Impuesto interno")
          cerca (paIdentidad p) (comps Map.! "Identidad ajena")
          cerca (paDistancia p) (comps Map.! "Distancia a la capital")
          cerca (deltaAgravio constantesDefault p) porVeintena) tablas

-- | Las cuatro tablas de `test/tablas_hito0.json` (generadas por
-- `hito_0/tablas/generar.mjs`), como tuplas.
data Tablas = Tablas
  { tbTasas   :: [(Int, Int, Bool, Double, Double)]
    -- ^ tributo, impuesto, capital, taxM, tShare
  , tbIngreso :: [(Int, Int, [(Int, Bool)], Double)]
    -- ^ tributo, impuesto, (población, sujeta) por altépetl, total
  , tbGastos  :: [(Int, Int, Int, Double)]
    -- ^ ejército, administración, diplomacia, total
  , tbAgravio :: [(Int, Int, Bool, Text, Text, Int, Map.Map Text Double, Double)]
    -- ^ tributo, impuesto, capital, estrato, identidad, distancia, componentes, por veintena
  }

parseTablas :: A.Value -> Parser Tablas
parseTablas = withObject "tablas" $ \o -> do
  cs <- o .: "casos"
  withObject "casos" (\c -> Tablas
    <$> (c .: "tasas"             >>= traverse fTasa)
    <*> (c .: "ingreso_total"     >>= traverse fIngreso)
    <*> (c .: "gastos"            >>= traverse fGasto)
    <*> (c .: "agravio_por_veintena" >>= traverse fAgravio)) cs
  where
    fTasa = withObject "tasa" $ \o ->
      (,,,,) <$> o .: "tributo" <*> o .: "impuesto" <*> o .: "capital"
             <*> o .: "taxM" <*> o .: "tShare"
    fIngreso = withObject "ingreso" $ \o -> do
      pops <- o .: "poblacion" >>= traverse (withObject "altepetl" $ \p ->
                (,) <$> p .: "pop" <*> p .: "sujeta")
      (,,,) <$> o .: "tributo" <*> o .: "impuesto" <*> pure pops <*> o .: "totalIncome"
    fGasto = withObject "gasto" $ \o ->
      (,,,) <$> o .: "ejercito" <*> o .: "administracion" <*> o .: "diplomacia"
            <*> o .: "totalExpenses"
    fAgravio = withObject "agravio" $ \o ->
      (,,,,,,,) <$> o .: "tributo" <*> o .: "impuesto" <*> o .: "capital"
                <*> o .: "estrato" <*> o .: "identidad" <*> o .: "distancia"
                <*> o .: "componentes" <*> o .: "porVeintena"
