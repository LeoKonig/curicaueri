{-# LANGUAGE StrictData, TypeFamilies #-}
module Motor.Sistema where

import Data.List (foldl')
import Data.Set (Set)
import Data.Text (Text)
import Motor.Azar
import Motor.Base
import Motor.Calendario
import Motor.Estado
import Motor.Hechos
import Motor.Magnitudes

-- | Diario: cada tick. Periodo: el primer día de cada periodo del calendario
-- interno (la veintena, en el prototipo), nunca fuera de periodo. Anual: el
-- día 0 del año interno.
data Cadencia = Diario | Periodo | Anual
  deriving (Eq, Show)

newtype NombreSistema = NombreSistema Text
  deriving (Eq, Show)

data Sistema s = Sistema
  { sisNombre   :: NombreSistema
  , sisCadencia :: Cadencia
  , sisLee      :: Set Magnitud
  , sisEscribe  :: Set Magnitud
  , sisEjecutar :: Rng -> Estado s -> (Estado s, [Hecho])
  }

activo :: CalendarioInterno -> Cadencia -> Tick -> Bool
activo _ Diario _ = True
activo c Periodo t = esInicioDePeriodo c t
activo c Anual t = esInicioDeAnio c t

-- | El pliegue de sistemas con la guarda de veintena.
correr :: Semilla -> Tick -> [Sistema s] -> Estado s -> (Estado s, [Hecho])
correr sigma t sistemas s0 = (s, hs [])
  where
    cal = comunCalendario (persistenteComun (estadoPersistente s0))
    (s, hs) = foldl' correrUno (s0, id) sistemas
    -- Los sistemas que la fase en curso no activa no corren (V5, actos como
    -- fases del escenario). Sin fases, corren todos.
    enFase sis = maybe True (unNombre (sisNombre sis) `elem`) (edSistemas (comunDirector (persistenteComun (estadoPersistente s0))))
    correrUno (e, k) sis
      | activo cal (sisCadencia sis) t && enFase sis =
          let (e', hs') = sisEjecutar sis (rng sigma (unNombre (sisNombre sis)) t) e
          in (e', k . (hs' ++))
      | otherwise = (e, k)
    unNombre (NombreSistema x) = x
