{-# LANGUAGE StrictData, TypeFamilies #-}
module Motor.Estado where

import Data.IntSet (IntSet)
import Data.Map.Strict (Map)
import Data.Sequence (Seq)
import Data.Text (Text)
import Motor.Base
import Motor.Calendario (CalendarioInterno)
import Motor.Magnitudes

type family DerivadoDe s
type family PlanDe     s

data ValorCtx
  = CCantidad Fijo
  | CEntero Int
  | COpcion Text
  | CEntidad EntRef
  deriving (Eq, Show)

type Contexto = Map Text ValorCtx

data Pregunta
  = PreguntaCantidad Text Int Int
  | PreguntaOpcion   Text [Text]
  deriving (Eq, Show)

preVariable :: Pregunta -> Text
preVariable (PreguntaCantidad v _ _) = v
preVariable (PreguntaOpcion   v _)   = v

-- | Continuación defuncionalizada. Todo lo que hace falta para reanudar
-- el mismo evento desde el mismo punto sin guardar clausuras.
data Reanudacion = Reanudacion
  { rnEvento          :: Text
  , rnOpcion          :: Text
  , rnSiguienteEfecto :: Int
  , rnContexto        :: Contexto
  } deriving (Eq, Show)

data DecisionPendiente = DecisionPendiente
  { dpId          :: Int
  , dpPregunta    :: Pregunta
  , dpReanudacion :: Reanudacion
  } deriving (Eq, Show)

data EntradaCronica = EntradaCronica
  { ecTick      :: Tick
  , ecTipo      :: Text
  , ecEntidades :: [EntRef]
  , ecClave     :: Text
  , ecParams    :: Map Text Text
  } deriving (Eq, Show)

-- | El fin de la partida: cuándo ocurrió y por qué (la fecha del guion o la
-- razón de la condición de derrota que se cumplió). Una partida terminada ya
-- no avanza (ver 'Motor.Juego.pasoCompleto').
data FinPartida = FinPartida
  { fpTick  :: Tick
  , fpRazon :: Text
  } deriving (Eq, Show)

-- | Una situación que el director presentó al jugador.
data Disparo = Disparo
  { diTick      :: Tick
  , diSituacion :: Text
  , diTipo      :: Text
  , diFase      :: Text
  } deriving (Eq, Show)

-- | Lo que el director recuerda entre ticks. Es persistente: si se perdiera
-- al guardar, la partida cargada tomaría otro rumbo (tensión, variedad y
-- novedad dependen de lo que ya salió).
data EstadoDirector = EstadoDirector
  { edFase         :: Int                 -- ^ índice de la fase en curso; -1 antes de empezar
  , edSistemas     :: Maybe [Text]        -- ^ sistemas activos de la fase (Nothing: todos)
  , edIntensidades :: Map Text Fijo       -- ^ intensidad de cada fuente de presión en la fase
  , edUltima       :: Maybe Tick          -- ^ última situación presentada
  , edHistorial    :: [Disparo]           -- ^ la más reciente primero
  , edPlazos       :: Map Int Tick        -- ^ decisión → último día para responderla
  , edProximaDecision :: Int              -- ^ ids de decisión nunca se reutilizan
  } deriving (Eq, Show)

directorInicial :: EstadoDirector
directorInicial = EstadoDirector (-1) Nothing mempty Nothing [] mempty 1

-- | La moneda de una entidad (una facción) que la designó (ver Motor.Moneda).
-- Es persistente: la inflación compara con lo ya visto, y sin el historial
-- una partida cargada no sabría cuánto subieron los precios.
data EstadoMonetario = EstadoMonetario
  { emMoneda    :: Text              -- ^ el bien designado como moneda
  , emDesde     :: Tick              -- ^ día de la designación
  , emHistorial :: [(Tick, Fijo)]    -- ^ precio de la moneda al empezar cada periodo; el más reciente primero; acotado
  } deriving (Eq, Show)

data Comun s = Comun
  { comunMagnitudes :: Almacen
  , comunDecisiones :: Map Int DecisionPendiente
  , comunPlanes     :: Map FaccionId (PlanDe s)
  , comunCronica    :: Seq EntradaCronica
  , comunCalendario :: CalendarioInterno   -- del escenario: periodos y días fuera
  , comunDirector   :: EstadoDirector      -- fase en curso y memoria del director
  , comunMonedas    :: Map EntRef EstadoMonetario  -- solo las entidades con moneda designada
  , comunFin        :: Maybe FinPartida      -- Nothing mientras la partida sigue
  }

data Persistente s = Persistente
  { persistenteComun :: Comun s
  , persistenteJuego :: s
  }

data Derivado s = Derivado
  { derivadoVigentes :: IntSet
  , derivadoJuego    :: DerivadoDe s
  }

data Origen s = Origen
  { origenTick        :: Tick
  , origenPersistente :: Persistente s
  }

data Estado s = Estado
  { estadoTick        :: Tick
  , estadoPersistente :: Persistente s
  , estadoOrigen      :: Origen s
  , estadoDerivado    :: Derivado s
  }
