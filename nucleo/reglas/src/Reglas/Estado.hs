{-# LANGUAGE StrictData, OverloadedStrings, TypeFamilies #-}
module Reglas.Estado where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Data.Aeson (ToJSON (..), FromJSON (..), object, withObject, (.:), (.:?), (.!=), (.=))
import Data.Aeson.Types (Parser)
import GHC.Generics (Generic)

import Motor.Base
import Motor.Estado
import Motor.Guardado ()
import Motor.Magnitudes
import Reglas.Base

data Purepecha = Purepecha
  { ppAltepetl    :: Map AltId Altepetl
  , ppPops        :: Map PopId Pop
  , ppPersonajes  :: Map PerId Personaje
  , ppFacciones   :: Map FaccionId Faccion   -- ^ toda facción declarada, también la potencial y la eliminada: los ids no se reutilizan
  } deriving (Eq, Show, Generic)

-- | Los nombres son los del 'ToJSON' genérico. Un guardado anterior a las
-- varias facciones trae @ppCazonci@, @ppTasas@ y @ppPresupuesto@ en lugar de
-- @ppFacciones@: carga con una sola facción activa y jugable, la 1, con esos
-- valores.
instance ToJSON Purepecha where
  toJSON p = object
    [ "ppAltepetl" .= ppAltepetl p, "ppPops" .= ppPops p
    , "ppPersonajes" .= ppPersonajes p, "ppFacciones" .= ppFacciones p ]

instance FromJSON Purepecha where
  parseJSON = withObject "Purepecha" $ \o -> do
    facs <- o .:? "ppFacciones" >>= \mf -> case mf of
      Just f  -> pure f
      Nothing -> do
        gob <- o .: "ppCazonci"
        tas <- o .: "ppTasas"
        pre <- o .: "ppPresupuesto"
        pure (Map.singleton (FaccionId 1) (faccionUnica gob tas pre))
    Purepecha <$> o .: "ppAltepetl" <*> o .: "ppPops" <*> o .: "ppPersonajes" <*> pure facs

-- | Una facción de las que es dueña de su propia bolsa (V5, *Qué es una
-- facción*). Su tesoro, su prestigio y su legitimidad no están aquí: son
-- magnitudes de la entidad @faccion <id>@ en el almacén común.
--
-- * @facTipo@ elige las bases de sus grupos de poder en @datos/grupos.json@.
-- * @facGobernante@ es quien gobierna; su administración mueve la eficiencia
--   de todos sus altépetl.
-- * @facDesde@ y @facHasta@ son ticks: la facción potencial se activa al
--   llegar a @facDesde@ y la activa se elimina al llegar a @facHasta@,
--   transfiriendo lo que tenía según @facTransferencia@ (V5, *Aparición y
--   desaparición de facciones*).
-- * @facJugable@: la que dirige la persona. Los sistemas no la distinguen.
data Faccion = Faccion
  { facId            :: FaccionId
  , facNombre        :: Text
  , facTipo          :: Text
  , facEstado        :: EstadoFaccion
  , facGobernante    :: PerId
  , facTasas         :: Tasas
  , facPresupuesto   :: Presupuesto
  , facJugable       :: Bool
  , facDesde         :: Maybe Int
  , facHasta         :: Maybe Int
  , facTransferencia :: Transferencia
  } deriving (Eq, Show, Generic, ToJSON)

-- | Los guardados anteriores no traen fechas ni transferencia: la facción no
-- aparece ni desaparece por fecha, y lo que tuviera se perdería.
instance FromJSON Faccion where
  parseJSON = withObject "Faccion" $ \o ->
    Faccion <$> o .: "facId" <*> o .: "facNombre" <*> o .: "facTipo" <*> o .: "facEstado"
            <*> o .: "facGobernante" <*> o .: "facTasas" <*> o .: "facPresupuesto"
            <*> o .: "facJugable" <*> o .:? "facDesde" <*> o .:? "facHasta"
            <*> o .:? "facTransferencia" .!= transferenciaNada

-- | Potencial: declarada pero todavía no existe. Activa: la recorren los
-- sistemas. Eliminada: ya no existe, y su id no se vuelve a usar.
data EstadoFaccion = Potencial | Activa | Eliminada
  deriving (Eq, Ord, Show, Generic, ToJSON, FromJSON)

-- | A dónde va lo que tenía una facción al desaparecer (documento funcional,
-- sección 14b). Los títulos y el heredero llegan con sus hitos: hoy el
-- destino es el absorbente o se pierde.
data Destino = SePierde | AlAbsorbente FaccionId
  deriving (Eq, Show, Generic, ToJSON, FromJSON)

-- | Qué pasa con cada cosa de la facción que desaparece. Los pops viajan con
-- su altépetl. Por omisión todo se pierde.
data Transferencia = Transferencia
  { trTesoro     :: Destino
  , trAltepetl   :: Destino
  , trPersonajes :: Destino
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

transferenciaNada :: Transferencia
transferenciaNada = Transferencia SePierde SePierde SePierde

-- | La facción de los guardados anteriores: el reino purépecha del escenario
-- único, activo y jugable.
faccionUnica :: PerId -> Tasas -> Presupuesto -> Faccion
faccionUnica gob tas pre =
  Faccion (FaccionId 1) "Reino purépecha" "reino_centralizado" Activa gob tas pre True
          Nothing Nothing transferenciaNada

-- | La condición del altépetl (V5, *Condición del altépetl*). @Cabecera f@
-- es la cabecera de la facción @f@: el altépetl independiente es la cabecera
-- de una facción propia. Sujeto y señorío difieren en quién gobierna, no en
-- la bolsa.
data CondicionAlt = Sujeto | Senorio | Cabecera FaccionId
  deriving (Eq, Show, Generic, ToJSON, FromJSON)

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
  , altFaccion    :: FaccionId    -- ^ la facción cuya bolsa es la suya; el tesoro de sus pops va allí
  , altCondicion  :: CondicionAlt
  } deriving (Eq, Show, Generic, ToJSON)

-- | Los guardados anteriores al hito 3 no traen obra ni edificios: cargan
-- sin obra y sin edificios. Los anteriores a las varias facciones no traen
-- facción ni condición: cargan en la facción 1, como sujeto si dependían de
-- otro altépetl y como su cabecera si no. Los nombres son los que escribe el
-- 'ToJSON' genérico.
instance FromJSON Altepetl where
  parseJSON = withObject "Altepetl" $ \o -> do
    sujeto <- o .: "altSujetoA" :: Parser (Maybe AltId)
    fac    <- o .:? "altFaccion" .!= FaccionId 1
    Altepetl <$> o .: "altId" <*> o .: "altNombre" <*> o .: "altGobernador"
             <*> o .: "altDistancia" <*> pure sujeto <*> o .: "altLealtad"
             <*> o .: "altCelda" <*> o .:? "altObra" <*> o .:? "altEdificios" .!= []
             <*> pure fac
             <*> o .:? "altCondicion" .!= maybe (Cabecera fac) (const Sujeto) sujeto

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
  , obTributos  :: Map Text TributoObra  -- ^ por material, el altépetl que lo envía como tributo en especie
  , obEnCamino  :: [Entrega]      -- ^ el material que viene en camino
  } deriving (Eq, Show, Generic, ToJSON)

-- | Un pedido de tributo en especie (V5, *Las obras*, etapa 2): el altépetl
-- que extrae el material con sus propios trabajadores y cuántos pone.
data TributoObra = TributoObra
  { toFuente    :: AltId
  , toCuadrilla :: Int
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

-- | Material que viene en camino a una obra: llega el día @enLlega@ y se
-- cobra su transporte al tesoro al llegar.
data Entrega = Entrega
  { enMaterial :: Text
  , enCantidad :: Fijo
  , enDe       :: AltId
  , enLlega    :: Int
  , enCosto    :: Fijo
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

-- | Las obras guardadas en el primer corte del hito 3 no traen cuadrilla,
-- trabajo ni acopio: cargan sin ellos.
instance FromJSON Obra where
  parseJSON = withObject "Obra" $ \o ->
    Obra <$> o .: "obEdificio" <*> o .: "obAvance" <*> o .: "obTotal"
         <*> o .:? "obCuadrilla" .!= 0 <*> o .:? "obTrabajo" .!= Fijo 0
         <*> o .:? "obAcopio" .!= Map.empty <*> o .:? "obTributos" .!= Map.empty
         <*> o .:? "obEnCamino" .!= []

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
  , perFaccion :: FaccionId     -- ^ la facción a la que sirve; solo ella puede nombrarlo
  } deriving (Eq, Show, Generic, ToJSON)

-- | Los guardados anteriores no traen facción: sirven a la 1.
instance FromJSON Personaje where
  parseJSON = withObject "Personaje" $ \o ->
    Personaje <$> o .: "perId" <*> o .: "perNombre" <*> o .: "perAdmin" <*> o .: "perMando"
              <*> o .: "perEdad" <*> o .: "perVivo" <*> o .:? "perGrupo"
              <*> o .:? "perFaccion" .!= FaccionId 1

-- | El tesoro, el prestigio y la legitimidad de una facción son magnitudes de
-- la entidad @faccion <id>@, en el almacén común. Así los sistemas los
-- declaran como escritos o leídos, y el validador de orden los ve.
entFac :: FaccionId -> EntRef
entFac (FaccionId i) = EntRef "faccion" i

-- | La facción de un altépetl; 1 si el altépetl no existe.
facDeAlt :: Purepecha -> AltId -> FaccionId
facDeAlt p a = maybe (FaccionId 1) altFaccion (Map.lookup a (ppAltepetl p))

-- | Las facciones activas, por id.
activas :: Purepecha -> [Faccion]
activas = filter ((== Activa) . facEstado) . Map.elems . ppFacciones

-- | La facción que dirige la persona: la jugable activa de menor id.
jugableDe :: Purepecha -> Maybe FaccionId
jugableDe p = case [ facId f | f <- activas p, facJugable f ] of
  (f : _) -> Just f
  []      -> Nothing

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

-- | El valor base de una magnitud de una facción, sin modificadores.
baseFaccion :: FaccionId -> Magnitud -> Estado Purepecha -> Fijo
baseFaccion f m st =
  maybe (Fijo 0) almacenBase
    (Map.lookup (entFac f, m) (comunMagnitudes (persistenteComun (estadoPersistente st))))

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
  , dpDistancias   :: Map AltId (Map AltId Fijo)  -- ^ de cada altépetl con obra a los que pueden enviarle tributo
  } deriving (Eq, Show)

derivadoPurepechaVacio :: DerivadoPurepecha
derivadoPurepechaVacio = DerivadoPurepecha Map.empty Map.empty Map.empty Map.empty Map.empty

type instance DerivadoDe Purepecha = DerivadoPurepecha
type instance PlanDe     Purepecha = ()
