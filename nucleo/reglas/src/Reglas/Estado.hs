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

-- | Una obra en curso (V5, *Las obras*; documento funcional, sección 14i).
-- Se guarda lo hecho, no una fecha de término, que dependería del
-- presupuesto y de la gente futuros:
--
-- * las veintenas de obra transcurridas y la duración mínima D;
-- * la cuadrilla, retirada de la producción mientras dure la obra;
-- * el trabajo hecho en el sitio, en trabajador·veintena;
-- * el material acopiado, por material.
--
-- Una obra sin cuadrilla es la del primer corte: avanza una veintena de obra
-- por cada veintena en que la partida de obras llega al mínimo.
data Obra = Obra
  { obEdificio  :: Text
  , obAvance    :: Int    -- ^ veintenas de obra hechas
  , obTotal     :: Int    -- ^ D: veintenas de obra mínimas
  , obCuadrilla :: Int    -- ^ C: trabajadores retirados para la obra (0 sin cuadrilla)
  , obTrabajo   :: Fijo   -- ^ trabajo hecho en el sitio
  , obAcopio    :: Map Text Fijo  -- ^ material acopiado
  } deriving (Eq, Show, Generic, ToJSON)

-- | Las obras guardadas en el primer corte del hito 3 no traen cuadrilla,
-- trabajo ni acopio: cargan sin ellos.
instance FromJSON Obra where
  parseJSON = withObject "Obra" $ \o ->
    Obra <$> o .: "obEdificio" <*> o .: "obAvance" <*> o .: "obTotal"
         <*> o .:? "obCuadrilla" .!= 0 <*> o .:? "obTrabajo" .!= Fijo 0
         <*> o .:? "obAcopio" .!= Map.empty

data Pop = Pop
  { popId        :: PopId
  , popAltepetl  :: AltId
  , popIdentidad :: Text
  , popEstrato   :: Text
  , popTamano    :: Int
  , popLealtad   :: Fijo
  , popGradiente :: Fijo   -- ^ @gradiente_catolicismo@, de 0 (culto tradicional) a 1 (católico); 0 en el prototipo
  } deriving (Eq, Show, Generic, ToJSON)

-- | Los guardados anteriores no traen gradiente: cargan con 0, el culto
-- tradicional.
instance FromJSON Pop where
  parseJSON = withObject "Pop" $ \o ->
    Pop <$> o .: "popId" <*> o .: "popAltepetl" <*> o .: "popIdentidad" <*> o .: "popEstrato"
        <*> o .: "popTamano" <*> o .: "popLealtad" <*> o .:? "popGradiente" .!= Fijo 0

-- | Los estratos que no trabajan la tierra: la nobleza y los sacerdotes.
estratoNoTrabaja :: Text -> Bool
estratoNoTrabaja e = e == "nobleza" || e == estratoSacerdote

-- | El estrato de los sacerdotes (V5, *Las obras*: sacerdotes). Atienden los
-- templos de su tradición; no trabajan la tierra.
estratoSacerdote :: Text
estratoSacerdote = "sacerdote"

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

-- | Una celda que trabaja un altépetl: su id, cuántos trabajadores la trabajan
-- entera (ℓ) y lo que rinde entonces (y), por bien.
data CeldaTrabajo = CeldaTrabajo
  { ctCelda        :: Int
  , ctTrabajadores :: Fijo
  , ctRendimiento  :: Map Text Fijo
  } deriving (Eq, Show)

-- | El derivado del juego (paso 16). Nunca se guarda: se recalcula desde el
-- origen.
--
-- * Las celdas que trabaja cada altépetl, de la mejor a la peor.
-- * Las celdas de cada material de obra que puede extraer cada altépetl,
--   también de la mejor a la peor (con un solo bien en el rendimiento).
-- * Los fieles de cada templo local y de cada centro ceremonial, por
--   (altépetl del templo, tradición): cuántos asisten, ya con su afinidad
--   y, en los centros, con el peso de la distancia.
data DerivadoPurepecha = DerivadoPurepecha
  { dpCeldas       :: Map AltId [CeldaTrabajo]
  , dpMateriales   :: Map AltId (Map Text [CeldaTrabajo])
  , dpFielesLocal  :: Map (AltId, Text) Fijo
  , dpFielesCentro :: Map (AltId, Text) Fijo
  } deriving (Eq, Show)

derivadoPurepechaVacio :: DerivadoPurepecha
derivadoPurepechaVacio = DerivadoPurepecha Map.empty Map.empty Map.empty Map.empty

type instance DerivadoDe Purepecha = DerivadoPurepecha
type instance PlanDe     Purepecha = ()
