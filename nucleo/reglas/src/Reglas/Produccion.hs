{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Producción de bienes por territorio (V5, *La tierra y la gente* y
-- *Población, asentamientos y territorio*; documento funcional, sección 12;
-- hito 3).
--
-- Cada altépetl trabaja las celdas que le asigna 'asignarCeldas' (las más
-- cercanas a su cabecera, dentro de 'cRadioProduccionKm'). Una celda rinde,
-- trabajada entera, los bienes de su terreno ('dtRendimiento') y necesita
-- 'dtTrabajadores' para ello. La producción la manda el factor escaso:
--
-- > Q_a = Σ_k y(c_k) · min(1, max(0, W_a − Σ_{j<k} ℓ(c_j)) / ℓ(c_k)) · (1 + Σ p)
--
-- con las celdas ordenadas por y/ℓ de mayor a menor (empate por id): los
-- trabajadores van primero a las mejores. W_a son los trabajadores del
-- altépetl, la fracción 'cFraccionTrabajadora' de sus pops productivos (todos
-- menos la nobleza), y (1 + Σ p) es su magnitud @produccion@, donde las obras
-- aportan sus porcentajes. Con varios bienes por celda, y es la suma de sus
-- rendimientos, sin pesos: los bienes todavía no tienen valor en el juego
-- (la moneda real es la tarea siguiente).
--
-- Qué celdas trabaja cada altépetl es estado derivado del paso 16: se
-- recalcula al empezar el periodo y lo lee la producción del periodo
-- siguiente, igual que el resto del derivado.
module Reglas.Produccion
  ( bienesDe
  , catalogoBienes
  , derivarCeldas
  , celdaTrabajo
  , ordenarCeldas
  , trabajadoresDe
  , produccionCeldas
  , totalProduccion
  , produccion
  ) where

import Data.List (foldl', sortBy)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.IntMap.Strict as IntMap
import qualified Data.Set as Set
import Data.Text (Text)

import Motor.Base
import Motor.Estado
import Motor.Magnitudes
import Motor.Mapa (Mapa (..), Celda (..), Terreno)
import Motor.Moneda (magExistencias, magProduccion)
import Motor.Recorrido (asignarCeldas, grafoDe)
import Motor.Sistema
import Motor.Terrenos (DefTerreno (..))
import Reglas.Base
import Reglas.Constantes
import Reglas.Estado

-- | Los bienes que el territorio puede producir: los que aparece en el
-- rendimiento de algún terreno, en orden alfabético.
bienesDe :: Map Terreno DefTerreno -> [Text]
bienesDe t = Map.keys (Map.unions (map dtRendimiento (Map.elems t)))

rangoBien :: RangoMag
rangoBien = RangoMag (fi 0) (fi 1000000000)

-- | Existencias y producción de cada bien, magnitudes de la facción
-- (CLAUDE.md, *Bienes como magnitudes de la facción*).
catalogoBienes :: [Text] -> Map Magnitud DefMagnitud
catalogoBienes bs = Map.fromList
  [ (m, DefMagnitud n rangoBien ("m." <> n) Nothing False)
  | b <- bs, m@(Magnitud n) <- [magExistencias b, magProduccion b] ]

-- | Una celda que se puede trabajar, con lo que pide y lo que da.
celdaTrabajo :: Int -> DefTerreno -> Maybe CeldaTrabajo
celdaTrabajo c d
  | Map.null (dtRendimiento d) || dtTrabajadores d <= Fijo 0 = Nothing
  | otherwise = Just (CeldaTrabajo c (dtTrabajadores d) (dtRendimiento d))

-- | Las celdas de mejor a peor por y/ℓ, con empate por id. La comparación se
-- hace en enteros, multiplicando en cruz, para no redondear el cociente.
ordenarCeldas :: [CeldaTrabajo] -> [CeldaTrabajo]
ordenarCeldas = sortBy cmp
  where
    y c = sum [ fromIntegral r :: Integer | Fijo r <- Map.elems (ctRendimiento c) ]
    l c = let Fijo x = ctTrabajadores c in fromIntegral x :: Integer
    cmp a b = compare (y b * l a, ctCelda a) (y a * l b, ctCelda b)

-- | El derivado del paso 16: qué celdas trabaja cada altépetl, ya ordenadas.
-- Sin tabla de terrenos que rinda algo, ninguna (y no se recorre el mapa).
derivarCeldas :: Constantes -> Map Terreno DefTerreno -> Mapa -> Purepecha -> Map AltId [CeldaTrabajo]
derivarCeldas c tabla mapa p
  | null (bienesDe tabla) = Map.empty
  | otherwise =
      let fuentes = [ (AsentId i, CeldaId (altCelda a)) | a <- Map.elems (ppAltepetl p), let AltId i = altId a ]
          asig = asignarCeldas (cRadioProduccionKm c) (grafoDe mapa) fuentes
          trabajo cel = IntMap.lookup cel (mapaCeldas mapa) >>= \ce ->
                          Map.lookup (celdaTerreno ce) tabla >>= celdaTrabajo cel
          porAlt = Map.fromListWith (++)
                     [ (AltId a, [ct]) | (cel, AsentId a) <- IntMap.toList asig, Just ct <- [trabajo cel] ]
      in Map.map ordenarCeldas porAlt

-- | Trabajadores de cada altépetl: ⌊N_p · φ⌋ por cada pop productivo (todos
-- los estratos menos la nobleza), sumados en una sola pasada por los pops.
-- Todavía no hay leva, así que no se resta nada (R_a = 0).
trabajadoresDe :: Constantes -> Purepecha -> Map AltId Int
trabajadoresDe c p = Map.fromListWith (+)
  [ (popAltepetl pop, trabajadores pop) | pop <- Map.elems (ppPops p), popEstrato pop /= "nobleza" ]
  where
    trabajadores pop = let Fijo x = fi (popTamano pop) .*. cFraccionTrabajadora c
                       in fromIntegral (x `div` escala)

-- | La fórmula con nombre @produccion_por_factor_escaso@: lo que dan las
-- celdas (ya ordenadas) con W trabajadores, por bien, antes de las obras.
-- La celda que queda a medias se calcula con una sola división entera.
produccionCeldas :: Int -> [CeldaTrabajo] -> Map Text Fijo
produccionCeldas w celdas = snd (foldl' celda (fromIntegral w * escala, Map.empty) celdas)
  where
    celda (libres, acc) ct
      | libres <= 0 = (libres, acc)
      | otherwise =
          let Fijo l = ctTrabajadores ct
              aporte (Fijo yv)
                | libres >= l = Fijo yv
                | otherwise   = Fijo (fromIntegral ((fromIntegral yv * fromIntegral libres :: Integer) `div` fromIntegral l))
          in (libres - l, Map.unionWith (.+.) acc (Map.map aporte (ctRendimiento ct)))

-- | Q_a sin distinguir bienes: la cantidad que cumple la ley de monotonía.
totalProduccion :: Map Text Fijo -> Fijo
totalProduccion = foldl' (.+.) (Fijo 0) . Map.elems

-- | El sistema de producción (paso 6, cada periodo). Escribe la base de
-- @bien.<id>.produccion@ de la facción con lo producido en el periodo y la
-- suma a @bien.<id>.existencias@; es el único escritor de las dos. Lee la
-- producción de cada altépetl (las obras) y las celdas del derivado.
--
-- El tributo en especie entre altépetl no mueve nada todavía: las
-- existencias son de la facción y todos los altépetl son de la misma, así
-- que lo que un sujeto entrega a su cabecera no sale de la bolsa común. Se
-- moverá cuando haya existencias por altépetl o tributo entre facciones.
produccion :: Constantes -> [Text] -> Sistema Purepecha
produccion c bienes = Sistema
  { sisNombre   = NombreSistema "produccion"
  , sisCadencia = Periodo
  , sisLee      = Set.singleton magProduccionAlt
  , sisEscribe  = Set.fromList (concat [ [magExistencias b, magProduccion b] | b <- bienes ])
  , sisEjecutar = \_ est ->
      if null bienes then (est, []) else
      let p     = persistenteJuego (estadoPersistente est)
          celdas = dpCeldas (derivadoJuego (estadoDerivado est))
          ws    = trabajadoresDe c p
          vig   = derivadoVigentes (estadoDerivado est)
          com   = persistenteComun (estadoPersistente est)
          factor alt = maybe baseProduccionAlt (valorEn vig (estadoTick est) rangoProduccionAlt)
                         (Map.lookup (entRefAlt alt, magProduccionAlt) (comunMagnitudes com))
          deAlt alt cs = Map.map (.*. factor alt) (produccionCeldas (Map.findWithDefault 0 alt ws) cs)
          total = Map.unionsWith (.+.) (Map.fromList [ (b, Fijo 0) | b <- bienes ]
                                        : Map.elems (Map.mapWithKey deAlt celdas))
          escribir alm (b, q) =
            sumarBase entFaccion (magExistencias b) q (fijarBase entFaccion (magProduccion b) q alm)
          alm' = foldl' escribir (comunMagnitudes com) (Map.toList (Map.filterWithKey (\b _ -> b `elem` bienes) total))
      in (est { estadoPersistente = (estadoPersistente est) { persistenteComun = com { comunMagnitudes = alm' } } }, [])
  }
