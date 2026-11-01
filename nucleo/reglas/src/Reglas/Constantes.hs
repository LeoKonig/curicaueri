{-# LANGUAGE StrictData, OverloadedStrings #-}
module Reglas.Constantes where

import Motor.Base
import Reglas.Base

-- | Constantes del hito 0a: los valores de `hito_0/datos/constantes.json`
-- (bloques `economia`, `eficiencia` y `ticks_por_anio`), que el generador de
-- tablas usa también. Si cambian allí, cambian aquí y las tablas lo confirman.
-- Las marcadas «literal» son números escritos dentro de las fórmulas del
-- prototipo, sin entrada en el JSON.
data Constantes = Constantes
  { cIngresoPorPop         :: Fijo   -- economia.ingreso_por_pop (0.012)
  , cTasaBase              :: Int    -- economia.tasa_base
  , cNeutralTasa           :: Int    -- literal: la tasa de referencia del agravio (3)
  , cAgravioSubirImpuesto  :: Fijo   -- economia.agravio_subir_impuesto
  , cAgravioBajarImpuesto  :: Fijo   -- economia.agravio_bajar_impuesto
  , cTesoroPorPunto        :: Fijo   -- economia.tesoro_por_punto_presupuesto
  , cTicksPorAnio          :: Fijo   -- ticks_por_anio: veintenas por año
    -- Eficiencia de un altépetl (`effLines`), en puntos de 0 a 100.
  , cEfBase                :: Int    -- eficiencia.base
  , cEfPorAdminGobernador  :: Int    -- eficiencia.por_admin_gobernador
  , cEfPorDistancia        :: Int    -- eficiencia.por_distancia
  , cEfBonoAdmin25         :: Int    -- eficiencia.bono_admin_25
  , cEfPorAdminCazonci     :: Int    -- eficiencia.por_admin_cazonci
  , cEfIdentidadAjena      :: Int    -- eficiencia.por_fraccion_identidad_ajena
  , cEfMin                 :: Int    -- eficiencia.clamp[0]
  , cEfMax                 :: Int    -- eficiencia.clamp[1]
  , cUmbralPresupuestoAdm  :: Int    -- literal: presupuesto de administración que da el bono (25)
  , cUmbralIdentidadAjena  :: Fijo   -- literal: fracción mínima de pobladores ajenos (0.001)
  , cAdminNeutral          :: Int    -- literal: administración que no suma ni resta (3)
    -- Agravio del gobernador (`popParts`): (base − administración) × por punto.
  , cGobernadorAgravioBase :: Int    -- literal: 2
  , cGobernadorAgravioPunto :: Int   -- literal: 3
    -- Obras (`step`): la partida de obras mínima para que avancen.
  , cObrasPresupuestoMinimo :: Int   -- construccion.presupuesto_minimo
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
  , cEfBase                = 40
  , cEfPorAdminGobernador  = 12
  , cEfPorDistancia        = -10
  , cEfBonoAdmin25         = 5
  , cEfPorAdminCazonci     = 4
  , cEfIdentidadAjena      = -20
  , cEfMin                 = 20
  , cEfMax                 = 100
  , cUmbralPresupuestoAdm  = 25
  , cUmbralIdentidadAjena  = Fijo 10         -- 0.001 = 10 / 10 000
  , cAdminNeutral          = 3
  , cGobernadorAgravioBase = 2
  , cGobernadorAgravioPunto = 3
  , cObrasPresupuestoMinimo = 20
  }
