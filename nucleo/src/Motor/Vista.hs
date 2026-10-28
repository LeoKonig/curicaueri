{-# LANGUAGE StrictData #-}
module Motor.Vista where

import Data.Map.Strict (Map)
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

-- | Lo que el juego aporta por cada entidad visible.
data EntidadJuego = EntidadJuego
  { ejRef    :: EntRef
  , ejCampos :: Map Text ValorVista
  } deriving (Eq, Show)

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
