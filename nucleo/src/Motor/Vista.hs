{-# LANGUAGE StrictData #-}
module Motor.Vista where

import Data.Map.Strict (Map)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import Motor.Base (EntRef, Fijo, Tick)
import Motor.Magnitudes (Aporte, Magnitud)

newtype ClaveLoc = ClaveLoc Text
  deriving (Eq, Ord, Show)

-- | Valor visible: el cliente lo interpreta; el núcleo no localiza.
data ValorVista
  = VTexto Text
  | VClave ClaveLoc [ValorVista]
  | VEntero Int
  | VFijo Fijo
  | VBool Bool
  | VRef EntRef
  | VLista [ValorVista]
  | VNulo
  deriving (Eq, Show)

data AporteVista = AporteVista
  { avFuente     :: ClaveLoc
  , avArgumentos :: [ValorVista]
  , avAporte     :: Aporte
  , avVence      :: Maybe Tick
  } deriving (Eq, Show)

data MagnitudVista = MagnitudVista
  { mvBase     :: Fijo
  , mvAportes  :: [AporteVista]
  , mvEfectivo :: Fijo
  } deriving (Eq, Show)

-- | Lo que el juego aporta por cada entidad. Una entidad con dueño es
-- detalle de otra (un pop de su altépetl): solo se ve si el cliente pidió el
-- detalle de su dueño ('Interes').
--
-- Los campos son perezosos (es lo único perezoso de la vista): el motor mira
-- primero la referencia y el dueño, que cuestan poco, y solo arma los campos
-- de lo que se ve. Proyectar 150 000 pops que nadie mira cuesta crear sus
-- constructores, no sus campos.
data EntidadJuego = EntidadJuego
  { ejRef    :: EntRef
  , ejDueno  :: Maybe EntRef
  , ejCampos :: ~(Map Text ValorVista)
  } deriving (Eq, Show)

-- | De qué entidades pidió el cliente el detalle (V5, *Escala de la
-- simulación*: enviar solo lo que se mira). 'Todo' ve también todo el
-- detalle: es la vista del agente y de las pruebas.
data Interes = Todo | Detalle (Set EntRef)
  deriving (Eq, Show)

-- | ¿Se ve esta entidad con este interés?
seVe :: Interes -> EntidadJuego -> Bool
seVe _ (EntidadJuego _ Nothing _) = True
seVe Todo _ = True
seVe (Detalle ds) (EntidadJuego _ (Just d) _) = d `Set.member` ds

-- | Lo que el motor publica: campos del juego + magnitudes del almacén.
data EntidadVista = EntidadVista
  { evRef        :: EntRef
  , evCampos     :: Map Text ValorVista
  , evMagnitudes :: Map Magnitud MagnitudVista
  } deriving (Eq, Show)

data Vista = Vista
  { vTick      :: Tick
  , vEntidades :: Map EntRef EntidadVista
  } deriving (Eq, Show)

-- | Cambios de un tick. Entidades actualizadas completas; eliminadas por ref.
data Cambios = Cambios
  { cTick          :: Tick
  , cActualizadas  :: [EntidadVista]
  , cEliminadas    :: [EntRef]
  } deriving (Eq, Show)
