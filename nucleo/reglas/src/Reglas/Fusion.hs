{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Fusión de pops pequeños (V5, *Escala de la simulación*; documento
-- funcional, sección 12). Es una mecánica de rendimiento, como la de
-- Victoria 3: los pops chicos con la misma clave y casi los mismos valores
-- se juntan en uno, para que el número de pops siga a la diversidad de la
-- población y no a su historia (una migración, una conversión a medias).
--
-- Cada veintena, dentro de cada clave (altépetl, identidad, estrato), los
-- pops se recorren del mayor al menor (empate por id). Un pop de menos de
-- 'cFusionTamano' personas se funde con el primero de los ya vistos que sea
-- compatible: gradiente, lealtad y agravio a no más de 'cFusionGradiente',
-- 'cFusionLealtad' y 'cFusionAgravio', y ninguno de los dos con
-- modificadores propios (un aporte no se puede repartir sin inventar cómo).
-- El que queda conserva su id; su tamaño es la suma, y el gradiente, la
-- lealtad y la base de cada magnitud son la media ponderada por tamaño,
-- redondeada hacia abajo:
--
-- > x = ⌊(x_a · n_a + x_b · n_b) / (n_a + n_b)⌋
--
-- Así se conservan el tamaño total de cada clave y, salvo el redondeo, todo
-- lo que es lineal en el tamaño: el ingreso, los trabajadores, los fieles
-- de cada tradición y el agravio total.
module Reglas.Fusion
  ( fusion
  , fusionarPops
  , clavePop
  ) where

import Data.List (foldl', sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Ord (Down (..))
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Estado
import Motor.Hechos
import Motor.Magnitudes
import Motor.Sistema
import Reglas.Base
import Reglas.Constantes
import Reglas.Estado

-- | Los pops con la misma clave son los que se pueden fundir. La de V5 es
-- (asentamiento, identidad, condición, estrato, residencia); el prototipo no
-- tiene condición ni residencia.
clavePop :: Pop -> (AltId, Text, Text)
clavePop q = (popAltepetl q, popIdentidad q, popEstrato q)

-- | Un pop del grupo, con las bases de sus magnitudes si no tiene
-- modificadores propios ('Nothing' si los tiene: no se funde ni recibe), y
-- los ids de los que ya absorbió.
data Visto = Visto Pop (Maybe (Map Magnitud Fijo)) [PopId]

-- | La fusión de una veintena sobre los pops y el almacén. Sin fusiones,
-- devuelve los mismos mapas (el mismo objeto: la vista no ve nada sucio).
fusionarPops :: Constantes -> Tick -> Purepecha -> Almacen -> (Purepecha, Almacen, [Hecho])
fusionarPops c t p alm0
  | cFusionTamano c <= 0 = (p, alm0, [])
  | otherwise = let (p', alm', hs) = foldl' escribir (p, alm0, []) (concatMap fundirGrupo candidatos)
                in (p', alm', reverse hs)
  where
    pequeno q = popTamano q < cFusionTamano c
    -- Los grupos se arman en una pasada por los pops; solo se miran los que
    -- tienen al menos dos pops y uno pequeño.
    grupos = Map.fromListWith (flip (++)) [ (clavePop q, [q]) | q <- Map.elems (ppPops p) ]
    candidatos = [ g | g@(_ : _ : _) <- Map.elems grupos, any pequeno g ]

    magnitudesDe q =
      let r = entRefPop (popId q)
          xs = Map.takeWhileAntitone ((== r) . fst) (Map.dropWhileAntitone ((< r) . fst) alm0)
      in if all (null . almacenMods) (Map.elems xs)
           then Just (Map.fromList [ (m, almacenBase x) | ((_, m), x) <- Map.toList xs ])
           else Nothing

    fundirGrupo g = [ v | v@(Visto _ _ (_ : _)) <- foldl' ver [] (sortOn (\q -> (Down (popTamano q), popId q)) g) ]

    -- Los vistos van en el orden en que llegaron: el primero compatible es el
    -- mayor (y, en empate, el de menor id).
    ver vistos q = case magnitudesDe q of
      Just mq | pequeno q, (antes, Visto k (Just mk) abs' : despues) <- break (compatible q mq) vistos ->
        antes ++ Visto (juntarPop k q) (Just (Map.intersectionWith (\a b -> media a (popTamano k) b (popTamano q)) mk mq))
                       (abs' ++ [popId q]) : despues
      mq -> vistos ++ [Visto q mq []]

    compatible q mq (Visto k (Just mk) _) =
         Map.keysSet mk == Map.keysSet mq
      && cerca (cFusionGradiente c) (popGradiente k) (popGradiente q)
      && cerca (cFusionLealtad c) (popLealtad k) (popLealtad q)
      && maybe True id (cerca (cFusionAgravio c) <$> Map.lookup magAgravio mk <*> Map.lookup magAgravio mq)
    compatible _ _ _ = False

    cerca tope (Fijo a) (Fijo b) = let Fijo u = tope in abs (a - b) <= u

    juntarPop k q = k { popTamano    = popTamano k + popTamano q
                      , popLealtad   = media (popLealtad k) (popTamano k) (popLealtad q) (popTamano q)
                      , popGradiente = media (popGradiente k) (popTamano k) (popGradiente q) (popTamano q) }

    escribir (pp, alm, hs) (Visto k mk absorbidos) =
      let rk = entRefPop (popId k)
          pops' = foldl' (flip Map.delete) (Map.insert (popId k) k (ppPops pp)) absorbidos
          conBases = foldl' (\al (m, b) -> Map.adjust (\x -> x { almacenBase = b }) (rk, m) al) alm
                            (maybe [] Map.toList mk)
          -- Los absorbidos tienen las mismas magnitudes que k ('compatible').
          sinAbsorbidos = foldl' (flip Map.delete) conBases
                            [ (entRefPop a, m) | a <- absorbidos, m <- maybe [] Map.keys mk ]
          hecho = Hecho "pops_fusionados" t (rk : map entRefPop absorbidos)
                    (Map.fromList [ ("tamano", T.pack (show (popTamano k)))
                                  , ("absorbidos", T.pack (show (length absorbidos))) ])
      in (pp { ppPops = pops' }, sinAbsorbidos, hecho : hs)

-- | La media ponderada por tamaño, redondeada hacia abajo; con los dos
-- vacíos, el primer valor.
media :: Fijo -> Int -> Fijo -> Int -> Fijo
media (Fijo a) na (Fijo b) nb
  | na + nb <= 0 = Fijo a
  | otherwise = Fijo (fromInteger ((toInteger a * toInteger na + toInteger b * toInteger nb) `div` toInteger (na + nb)))

magAgravio :: Magnitud
magAgravio = Magnitud "agravio"

-- | El sistema de fusión (cada periodo, después del agravio): escribe los
-- pops y, de los que se funden, la base de sus magnitudes.
fusion :: Constantes -> Sistema Purepecha
fusion c = Sistema
  { sisNombre   = NombreSistema "fusion_pops"
  , sisCadencia = Periodo
  , sisLee      = Set.empty
  , sisEscribe  = Set.singleton magAgravio
  , sisEjecutar = \_ est ->
      let per = estadoPersistente est
          com = persistenteComun per
          (p', alm', hs) = fusionarPops c (estadoTick est) (persistenteJuego per) (comunMagnitudes com)
      in if null hs then (est, [])
         else (est { estadoPersistente = per { persistenteJuego = p', persistenteComun = com { comunMagnitudes = alm' } } }, hs)
  }
