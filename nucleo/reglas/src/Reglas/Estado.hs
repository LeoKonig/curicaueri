{-# LANGUAGE StrictData, OverloadedStrings, TypeFamilies #-}
module Reglas.Estado where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Data.Aeson (ToJSON, FromJSON (..), withObject, (.:), (.:?), (.!=))
import GHC.Generics (Generic)

import Motor.Base
import Motor.Estado
import Motor.Magnitudes
import Reglas.Base

data Purepecha = Purepecha
  { ppAltepetl    :: Map AltId Altepetl
  , ppPops        :: Map PopId Pop
  , ppPersonajes  :: Map PerId Personaje
  , ppCazonci     :: PerId          -- ^ quien gobierna; su administración mueve la eficiencia
  , ppTasas       :: Tasas
  , ppPresupuesto :: Presupuesto
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

data Altepetl = Altepetl
  { altId         :: AltId
  , altNombre     :: Text
  , altGobernador :: Maybe PerId
  , altDistancia  :: Fijo
  , altSujetoA    :: Maybe AltId
  , altLealtad    :: Fijo
  , altCelda      :: Int          -- ^ celda del mapa donde está la cabecera
  , altObra       :: Maybe Obra   -- ^ la obra en curso; una a la vez, como en el prototipo
  , altEdificios  :: [Text]       -- ^ ids de los edificios terminados, en el orden en que se terminaron
  } deriving (Eq, Show, Generic, ToJSON)

-- | Los guardados anteriores al hito 3 no traen obra ni edificios: cargan
-- sin obra y sin edificios. Los nombres son los que escribe el 'ToJSON'
-- genérico.
instance FromJSON Altepetl where
  parseJSON = withObject "Altepetl" $ \o ->
    Altepetl <$> o .: "altId" <*> o .: "altNombre" <*> o .: "altGobernador"
             <*> o .: "altDistancia" <*> o .: "altSujetoA" <*> o .: "altLealtad"
             <*> o .: "altCelda" <*> o .:? "altObra" <*> o .:? "altEdificios" .!= []

-- | Una obra en curso (V5, *Las palancas*, Construcción). Como en el
-- prototipo, avanza una veintena de obra por cada veintena en que la partida
-- de obras llega al mínimo; por eso se guarda el avance y no una fecha de
-- término, que dependería del presupuesto futuro.
data Obra = Obra
  { obEdificio :: Text
  , obAvance   :: Int    -- ^ veintenas de obra hechas
  , obTotal    :: Int    -- ^ veintenas de obra que exige el edificio
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

data Pop = Pop
  { popId        :: PopId
  , popAltepetl  :: AltId
  , popIdentidad :: Text
  , popEstrato   :: Text
  , popTamano    :: Int
  , popLealtad   :: Fijo
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

data Personaje = Personaje
  { perId     :: PerId
  , perNombre :: Text
  , perAdmin  :: Int
  , perMando  :: Int
  , perEdad   :: Int
  , perVivo   :: Bool
  , perGrupo  :: Maybe Text     -- ^ grupo de poder (V5, *Los nombramientos mueven poder*); sin grupo, no mueve poder
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

-- | La facción no es un registro: su tesoro, prestigio y legitimidad son
-- magnitudes de la entidad @faccion 1@, en el almacén común. Así los sistemas
-- los declaran como escritos o leídos, y el validador de orden los ve.
entFaccion :: EntRef
entFaccion = EntRef "faccion" 1

magTesoro, magPrestigio, magLegitimidad :: Magnitud
magTesoro      = Magnitud "tesoro"
magPrestigio   = Magnitud "prestigio"
magLegitimidad = Magnitud "legitimidad"

-- | Rango del tesoro: nunca negativo. El límite superior es provisional: el
-- prototipo no lo tiene, y la cifra solo evita desbordar el punto fijo.
rangoTesoro :: RangoMag
rangoTesoro = RangoMag (fi 0) (fi 1000000000)

-- | Rango del prestigio y la legitimidad. Provisional, como el del tesoro.
rangoPrestigio, rangoLegitimidad :: RangoMag
rangoPrestigio   = RangoMag (fi (-1000000)) (fi 1000000)
rangoLegitimidad = RangoMag (fi 0) (fi 100)

-- | Magnitudes del altépetl que mueven las obras (V5, *Arquitectura de
-- extensión*; hito 3). Ninguna tiene sistema que escriba su base: la fija el
-- escenario y los edificios aportan modificadores con su fuente.
--
-- * @produccion@: factor de la producción y del ingreso del altépetl, con base
--   1. Los edificios aportan porcentajes (yácata +10 %, fortaleza −5 %), que se
--   suman entre sí como cualquier modificador.
-- * @tasa_agravio@: puntos de agravio por año que suma o resta a sus pops, con
--   base 0 (yácata −5, troje −3).
-- * @reservas_asedio@: cuánto resiste la plaza un asedio, con base 0
--   (fortaleza +4, troje +3). La leerá el asedio del hito 4.
magProduccionAlt, magTasaAgravio, magReservasAsedio :: Magnitud
magProduccionAlt  = Magnitud "produccion"
magTasaAgravio    = Magnitud "tasa_agravio"
magReservasAsedio = Magnitud "reservas_asedio"

rangoProduccionAlt, rangoTasaAgravio, rangoReservasAsedio :: RangoMag
rangoProduccionAlt  = RangoMag (fi 0) (fi 10)
rangoTasaAgravio    = RangoMag (fi (-100)) (fi 100)
rangoReservasAsedio = RangoMag (fi 0) (fi 1000)

-- | La base de la producción de un altépetl: 1 (el 100 %).
baseProduccionAlt :: Fijo
baseProduccionAlt = fi 1

-- | El valor base de una magnitud de la facción, sin modificadores.
baseFaccion :: Magnitud -> Estado Purepecha -> Fijo
baseFaccion m st =
  maybe (Fijo 0) almacenBase
    (Map.lookup (entFaccion, m) (comunMagnitudes (persistenteComun (estadoPersistente st))))

data Tasas = Tasas
  { tasaTributo  :: Int
  , tasaImpuesto :: Int
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

data PartePresupuesto
  = PEjercito | PAdministracion | PObras | PDiplomacia | PCulto
  deriving (Eq, Show, Generic, ToJSON, FromJSON)

data Presupuesto = Presupuesto
  { pbEjercito       :: Int
  , pbAdministracion :: Int
  , pbObras          :: Int
  , pbDiplomacia     :: Int
  , pbCulto          :: Int
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

type instance DerivadoDe Purepecha = ()
type instance PlanDe     Purepecha = ()
