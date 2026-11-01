{-# LANGUAGE StrictData #-}
-- | La influencia en el semianillo tropical (documento funcional, sección 9;
-- V5, *Mapa: influencia, dueño y control*).
--
-- La influencia de una fuente s sobre una celda c decae con el costo de
-- llegar, I = F·e^(−d/λ). Con φ = −λ ln I, el máximo de productos es un
-- mínimo de sumas, φ(c) = min_s (π_s + d(s, c)) con π_s = −λ ln F_s, y se
-- calcula con un Dijkstra multifuente donde cada fuente arranca con su
-- potencial. El núcleo nunca calcula una exponencial: solo un logaritmo por
-- fuente.
--
-- Cada celda guarda las dos mejores facciones distintas (el dueño y la
-- segunda, para las zonas disputadas). Por debajo del umbral de influencia
-- (φ por encima de −λ ln umbral) la celda no tiene dueño: es tierra de nadie,
-- y el recorrido no se extiende por ella.
--
-- El resultado es derivado: se recalcula, no se guarda. 'actualizarInfluencia'
-- parte del resultado anterior y repara solo lo que tocan las fuentes que
-- cambiaron; da exactamente lo mismo que 'calcularInfluencia' (es una ley).
module Motor.Influencia
  ( FuenteInfluencia (..)
  , ParamInfluencia (..)
  , Influencia
  , infParam, infFuentes, infCeldas
  , potencial
  , calcularInfluencia
  , actualizarInfluencia
  , repararInfluencia
  , mejoresEn
  , duenoDe
  ) where

import Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IntMap
import qualified Data.IntSet as IntSet
import Motor.Base
import Motor.Recorrido

-- | Una fuente de influencia: un centro de poder de una facción. Su fuerza es
-- el valor de una magnitud (población, guarnición, modificadores) que el
-- llamador ya leyó. Las fuentes se identifican por la clave del 'IntMap'.
data FuenteInfluencia = FuenteInfluencia
  { fuenteFaccion :: FaccionId
  , fuenteCelda   :: CeldaId
  , fuenteFuerza  :: Fijo
  } deriving (Eq, Show)

data ParamInfluencia = ParamInfluencia
  { piAlcance :: Fijo   -- ^ λ, en las unidades del costo (km)
  , piUmbral  :: Fijo   -- ^ influencia mínima para tener dueño; 0, sin umbral
  } deriving (Eq, Show)

data Influencia = Influencia
  { infParam   :: ParamInfluencia
  , infFuentes :: IntMap FuenteInfluencia
  , infCeldas  :: IntMap Mejores
  } deriving (Eq, Show)

-- | π = −λ ln F. Una fuente sin fuerza (F ≤ 0) no irradia nada.
potencial :: Fijo -> Fijo -> Maybe Fijo
potencial lambda f
  | f <= Fijo 0 = Nothing
  | otherwise   = either (const Nothing) (\l -> Just (negF (lambda .*. l))) (lnFijo f)

-- | El φ más alto que todavía tiene dueño.
tope :: ParamInfluencia -> Maybe Fijo
tope p = if piUmbral p > Fijo 0 then potencial (piAlcance p) (piUmbral p) else Nothing

semillas :: ParamInfluencia -> IntMap FuenteInfluencia -> [(CeldaId, Etiqueta)]
semillas p fs =
  [ (fuenteCelda f, Etiqueta pf g i)
  | (i, f) <- IntMap.toList fs
  , let FaccionId g = fuenteFaccion f
  , Just pf <- [potencial (piAlcance p) (fuenteFuerza f)] ]

calcularInfluencia :: ParamInfluencia -> Grafo -> IntMap FuenteInfluencia -> Influencia
calcularInfluencia p gr fs =
  Influencia p fs (propagarGrafo DosGrupos (tope p) gr (semillas p fs))

-- | La influencia con las fuentes nuevas, a partir de la anterior: repara si
-- cambió poco y recalcula si cambió mucho. Las dos vías dan exactamente lo
-- mismo (es una ley), así que la elección solo cambia el tiempo. El umbral
-- sale de medir a la escala del juego completo: reparar cuesta más que
-- recalcular cuando cambia más o menos una de cada 20 fuentes.
actualizarInfluencia :: ParamInfluencia -> Grafo -> IntMap FuenteInfluencia -> Influencia -> Influencia
actualizarInfluencia p gr fs previa
  | p /= infParam previa = calcularInfluencia p gr fs
  | 20 * cambiadas > IntMap.size fs + IntMap.size (infFuentes previa) = calcularInfluencia p gr fs
  | otherwise = repararInfluencia p gr fs previa
  where
    cambiadas = IntMap.size (IntMap.filterWithKey (\i f -> IntMap.lookup i fs /= Just f) (infFuentes previa))
              + IntMap.size (IntMap.filterWithKey (\i f -> IntMap.lookup i (infFuentes previa) /= Just f) fs)

-- | La influencia con las fuentes nuevas, reparando la anterior.
--
-- 1. Las fuentes que desaparecieron o cambiaron (de facción, de celda o de
--    fuerza) dejan de valer: se quitan sus etiquetas de todas las celdas.
-- 2. A cada celda que perdió una etiqueta se le vuelve a ofrecer todo lo que
--    le llega: las etiquetas de sus vecinas y las fuentes que están en ella
--    (una fuente que otra de su facción opacaba en todas partes no tiene
--    ninguna etiqueta desde la cual reparar). Las fuentes nuevas o cambiadas
--    arrancan con su potencial.
-- 3. 'propagar' extiende solo lo que mejora alguna celda.
--
-- El trabajo es proporcional a las celdas que cambian, más un recorrido de
-- las etiquetas para encontrar las de las fuentes que cambiaron. Si cambian
-- los parámetros, se recalcula todo. El mapa debe ser el mismo con que se
-- calculó la anterior.
repararInfluencia :: ParamInfluencia -> Grafo -> IntMap FuenteInfluencia -> Influencia -> Influencia
repararInfluencia p gr fs previa
  | p /= infParam previa = calcularInfluencia p gr fs
  | IntSet.null caducas && IntMap.null nuevas = previa { infFuentes = fs }
  | otherwise =
      Influencia p fs (propagar DosGrupos (tope p) mapa
        (semillas p (IntMap.union nuevas enTocadas) ++ semillasDeVecinas mapa limpias tocadas) limpias)
  where
    mapa = grafoMapa gr
    viejas = infFuentes previa
    distinta i f = IntMap.lookup i fs /= Just f
    caducas = IntMap.keysSet (IntMap.filterWithKey distinta viejas)
    nuevas = IntMap.filterWithKey (\i f -> IntMap.lookup i viejas /= Just f) fs
    vale e = not (IntSet.member (etFuente e) caducas)
    -- Las celdas con alguna etiqueta caduca y lo que les queda.
    cambios = IntMap.foldrWithKey
      (\c m acc -> if all vale (listaMejores m) then acc
                   else (c, filter vale (listaMejores m)) : acc) [] (infCeldas previa)
    tocadas = map fst cambios
    conjTocadas = IntSet.fromList tocadas
    enTocadas = IntMap.filter (\f -> let CeldaId c = fuenteCelda f in IntSet.member c conjTocadas) fs
    limpias = foldr (\(c, es) m -> case es of
                       []    -> IntMap.delete c m
                       [a]   -> IntMap.insert c (Una a) m
                       a : b : _ -> IntMap.insert c (Dos a b) m)
                    (infCeldas previa) cambios

-- | Las mejores facciones de una celda, de la más fuerte a la segunda.
mejoresEn :: Influencia -> CeldaId -> [Etiqueta]
mejoresEn inf (CeldaId c) = maybe [] listaMejores (IntMap.lookup c (infCeldas inf))

-- | El dueño de una celda: la facción de mayor influencia; en un empate, la
-- de id menor. 'Nothing' en tierra de nadie.
duenoDe :: Influencia -> CeldaId -> Maybe FaccionId
duenoDe inf c = case mejoresEn inf c of
  e : _ -> Just (FaccionId (etGrupo e))
  []    -> Nothing
