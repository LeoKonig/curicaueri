{-# LANGUAGE StrictData, OverloadedStrings #-}
module Reglas.Constantes where

import Motor.Base
import Reglas.Base

-- | Constantes del hito 0a: los valores de `hito_0/datos/constantes.json`
-- (bloque `economia` y `ticks_por_anio`), que el generador de tablas usa
-- también. Si cambian allí, cambian aquí y las tablas lo confirman.
data Constantes = Constantes
  { cIngresoPorPop         :: Fijo   -- economia.ingreso_por_pop (0.012)
  , cTasaBase              :: Int    -- economia.tasa_base
  , cNeutralTasa           :: Int    -- la tasa de referencia del agravio (3)
  , cAgravioSubirImpuesto  :: Fijo   -- economia.agravio_subir_impuesto
  , cAgravioBajarImpuesto  :: Fijo   -- economia.agravio_bajar_impuesto
  , cTesoroPorPunto        :: Fijo   -- economia.tesoro_por_punto_presupuesto
  , cTicksPorAnio          :: Fijo   -- ticks_por_anio: veintenas por año
  } deriving (Eq, Show)

constantesDefault :: Constantes
constantesDefault = Constantes
  { cIngresoPorPop         = Fijo 120        -- 0.012 = 120 / 10 000
  , cTasaBase              = 3
  , cNeutralTasa           = 3
  , cAgravioSubirImpuesto  = fi 4
  , cAgravioBajarImpuesto  = fi 2
  , cTesoroPorPunto        = fi 6
  , cTicksPorAnio          = fi 18
  }
