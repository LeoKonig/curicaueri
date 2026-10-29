{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Fórmulas del hito 0a con los nombres del prototipo (`taxM`, `tShare`,
-- `tx`, `popParts`…). Cada una tiene su tabla de casos en
-- `test/tablas_hito0.json`, generada por `hito_0/tablas/generar.mjs` a
-- partir del HTML. Los sistemas de `Reglas.Sistemas` solo las llaman.
module Reglas.Formulas where

import Data.Text (Text)

import Motor.Base

import Reglas.Base
import Reglas.Constantes
import Reglas.Estado

-- | `taxM`: el factor de tasas del altépetl. La capital paga solo impuesto
-- interno; una sujeta, el promedio de tributo e impuesto.
taxM :: Constantes -> Tasas -> Bool -> Fijo
taxM c t capital
  | capital   = fi (tasaImpuesto t) ./. fi (cTasaBase c)
  | otherwise = fi (tasaTributo t + tasaImpuesto t) ./. fi (2 * cTasaBase c)

-- | `tShare`: la parte de la producción de una sujeta que va a la capital.
-- La capital no envía tributo a nadie.
tShare :: Tasas -> Bool -> Fijo
tShare t capital
  | capital   = Fijo 0
  | otherwise = fi (tasaTributo t) ./. fi (tasaTributo t + tasaImpuesto t)

-- | Ingreso de la población de un altépetl por veintena. Es la parte de
-- `incomeParts` que no depende del territorio: en 1b no hay rendimientos
-- del mapa, así que el término de territorio no entra todavía.
ingresoPoblacion :: Constantes -> Tasas -> Bool -> Int -> Fijo
ingresoPoblacion c t capital tam =
  fi tam .*. cIngresoPorPop c .*. taxM c t capital

-- | El gasto de un punto de presupuesto por veintena: `tesoro_por_punto_presupuesto`.
gastoPunto :: Constantes -> Int -> Fijo
gastoPunto c puntos = fi puntos .*. cTesoroPorPunto c

-- | `tx`: el agravio que produce una tasa, según su distancia a la neutra.
-- Subir cuesta más que bajar, y al subir crece con el cuadrado.
tx :: Constantes -> Int -> Fijo
tx c d
  | d > 0     = cAgravioSubirImpuesto c .*. fi d .+. fi (d * d)
  | d < 0     = cAgravioBajarImpuesto c .*. fi d
  | otherwise = Fijo 0

-- | El factor de estrato de `popParts`: la nobleza siente la mitad.
factorEstrato :: Text -> Fijo
factorEstrato e
  | e == "nobleza" = fiD 5
  | otherwise      = uno

-- | Componentes de `popParts` que 1b puede calcular, por veintena (sin
-- dividir entre `cTicksPorAnio`). La capital no paga tributo; el tributo y
-- el impuesto llevan el factor de estrato; la identidad ajena suma 2; y la
-- distancia suma 1,5 por cada unidad de distancia.
data PartesAgravio = PartesAgravio
  { paTributo   :: Fijo
  , paImpuesto  :: Fijo
  , paIdentidad :: Fijo
  , paDistancia :: Fijo
  } deriving (Eq, Show)

popParts :: Constantes -> Tasas -> Bool -> Text -> Text -> Fijo -> PartesAgravio
popParts c t capital estrato identidad distancia = PartesAgravio
  { paTributo   = if capital then Fijo 0
                  else tx c (tasaTributo t - cNeutralTasa c) .*. factorEstrato estrato
  , paImpuesto  = tx c (tasaImpuesto t - cNeutralTasa c) .*. factorEstrato estrato
  , paIdentidad = if identidad == "purepecha" then Fijo 0 else fi 2
  , paDistancia = distancia .*. fiD 15
  }

-- | La suma de las partes, por veintena: `popParts` ÷ `ticks_por_anio`.
deltaAgravio :: Constantes -> PartesAgravio -> Fijo
deltaAgravio c p =
  (paTributo p .+. paImpuesto p .+. paIdentidad p .+. paDistancia p)
    ./. cTicksPorAnio c
