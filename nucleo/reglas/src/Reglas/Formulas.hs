{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Fórmulas del hito 0a con los nombres del prototipo (`taxM`, `tShare`,
-- `tx`, `popParts`, `effLines`…). Cada una tiene su tabla de casos en
-- `test/tablas_hito0.json`, generada por `hito_0/tablas/generar.mjs` a
-- partir del HTML. Los sistemas de `Reglas.Sistemas` solo las llaman.
module Reglas.Formulas where

import qualified Data.Map.Strict as Map
import Data.Text (Text)

import Motor.Base

import Reglas.Base
import Reglas.Constantes
import Reglas.Estado

-- | `Math.round` de JavaScript: a la mitad, hacia arriba (también en negativos).
redondearJS :: Fijo -> Int
redondearJS (Fijo n) = fromIntegral ((n + escala `div` 2) `div` escala)

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

-- | `effLines.tot`: la eficiencia del altépetl en puntos (de `cEfMin` a
-- `cEfMax`), a partir de la administración del gobernador, la distancia a la
-- capital, si el presupuesto de administración llega al umbral, la
-- administración del cazonci y la fracción de pobladores de identidad ajena.
eficienciaPuntos :: Constantes -> Int -> Fijo -> Bool -> Int -> Fijo -> Int
eficienciaPuntos c adminGob distancia admin25 adminCazonci fraccionAjena =
  let base      = fi (cEfBase c)
      gobernador = fi (cEfPorAdminGobernador c * adminGob)
      lejania   = distancia .*. fi (cEfPorDistancia c)
      bono      = if admin25 then fi (cEfBonoAdmin25 c) else Fijo 0
      cazonci   = if adminCazonci /= cAdminNeutral c
                    then fi (cEfPorAdminCazonci c * (adminCazonci - cAdminNeutral c))
                    else Fijo 0
      ajena     = if fraccionAjena > cUmbralIdentidadAjena c
                    then fi (redondearJS (fi (cEfIdentidadAjena c) .*. fraccionAjena))
                    else Fijo 0
      suma      = base .+. gobernador .+. lejania .+. bono .+. cazonci .+. ajena
  in redondearJS (rangoFijo (fi (cEfMin c)) (fi (cEfMax c)) suma)

-- | `eff`: la eficiencia como factor, de 0,2 a 1.
eficiencia :: Constantes -> Int -> Fijo -> Bool -> Int -> Fijo -> Fijo
eficiencia c adminGob distancia admin25 adminCazonci fraccionAjena =
  fi (eficienciaPuntos c adminGob distancia admin25 adminCazonci fraccionAjena) ./. fi 100

-- | La administración de un personaje. Un gobernador ausente vale 0, como
-- `vacante` en el prototipo.
adminDe :: Purepecha -> Maybe PerId -> Int
adminDe p mper = maybe 0 perAdmin (mper >>= \i -> Map.lookup i (ppPersonajes p))

-- | La eficiencia de cada altépetl del estado, con el presupuesto y el
-- gobernante de su facción. Los tamaños se suman en una
-- sola pasada por los pops: recorrerlos una vez por altépetl hacía la
-- hacienda cuadrática (con 200 altépetl y 4 000 pops, 0,3 s por veintena).
eficiencias :: Constantes -> Purepecha -> Map.Map AltId Fijo
eficiencias c p =
  let sumar (t, aj) pop = (t + popTamano pop, aj + if popIdentidad pop /= "purepecha" then popTamano pop else 0)
      tamanos = Map.fromListWith (\(t1, a1) (t2, a2) -> (t1 + t2, a1 + a2))
                  [ (popAltepetl pop, sumar (0, 0) pop) | pop <- Map.elems (ppPops p) ]
      deAlt a = let (total, ajenos) = Map.findWithDefault (0, 0) (altId a) tamanos
                    fraccion = if total > 0 then fi ajenos ./. fi total else Fijo 0
                    fac = Map.lookup (altFaccion a) (ppFacciones p)
                    admin25 = maybe False (\f -> pbAdministracion (facPresupuesto f) >= cUmbralPresupuestoAdm c) fac
                in eficiencia c (adminDe p (altGobernador a)) (altDistancia a) admin25
                              (maybe 0 (adminDe p . Just . facGobernante) fac) fraccion
  in Map.map deAlt (ppAltepetl p)

-- | Ingreso de la población de un altépetl por veintena. Es la parte de
-- `incomeParts` que no depende del territorio: en 1b no hay rendimientos
-- del mapa, así que el término de territorio no entra todavía.
ingresoPoblacion :: Constantes -> Tasas -> Bool -> Fijo -> Int -> Fijo
ingresoPoblacion c t capital eff tam =
  fi tam .*. cIngresoPorPop c .*. eff .*. taxM c t capital

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

-- | Componentes de `popParts` que el juego puede calcular, por veintena (sin
-- dividir entre `cTicksPorAnio`). La capital no paga tributo; el tributo y
-- el impuesto llevan el factor de estrato; un buen gobernador resta y uno
-- malo suma; la identidad ajena suma 2; y la distancia suma 1,5 por cada
-- unidad.
data PartesAgravio = PartesAgravio
  { paTributo    :: Fijo
  , paImpuesto   :: Fijo
  , paGobernador :: Fijo
  , paIdentidad  :: Fijo
  , paDistancia  :: Fijo
  } deriving (Eq, Show)

popParts :: Constantes -> Tasas -> Bool -> Text -> Text -> Fijo -> Int -> PartesAgravio
popParts c t capital estrato identidad distancia adminGob = PartesAgravio
  { paTributo    = if capital then Fijo 0
                   else tx c (tasaTributo t - cNeutralTasa c) .*. factorEstrato estrato
  , paImpuesto   = tx c (tasaImpuesto t - cNeutralTasa c) .*. factorEstrato estrato
  , paGobernador = fi ((cGobernadorAgravioBase c - adminGob) * cGobernadorAgravioPunto c)
  , paIdentidad  = if identidad == "purepecha" then Fijo 0 else fi 2
  , paDistancia  = distancia .*. fiD 15
  }

-- | La suma de las partes, por veintena: `popParts` ÷ `ticks_por_anio`.
deltaAgravio :: Constantes -> PartesAgravio -> Fijo
deltaAgravio c p =
  (paTributo p .+. paImpuesto p .+. paGobernador p .+. paIdentidad p .+. paDistancia p)
    ./. cTicksPorAnio c
