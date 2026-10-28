{-# LANGUAGE OverloadedStrings #-}
module Main where

import Data.List (foldl')
import qualified Data.Map.Strict as Map
import Test.Hspec

import Motor.Base
import Motor.Carga (validarOrdenSistemas, Validacion (..), ErrorCarga (..))
import Motor.Autoridad
import Motor.Protocolo (DeclComando (..))
import qualified Data.Aeson as A
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
        tesoro st =
          facTesoro (ppFaccion (persistenteJuego (estadoPersistente st)))
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
      ppFaccion (persistenteJuego (estadoPersistente a))
        `shouldBe` ppFaccion (persistenteJuego (estadoPersistente b))

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
    it "tick 0 a tasas neutras: 1000 + 0,1 × 60 000 − (0,1 × 30 + 0,1 × 25) = 6994,5" $ do
      let j = Reglas.Juego.juego constantesDefault
          (s1, _) = paso j (entornoSimple mapaVacio) (Semilla 1) (Tick 0) [] estadoInicial1475
      facTesoro (ppFaccion (persistenteJuego (estadoPersistente s1))) `shouldBe` Fijo 69945000
