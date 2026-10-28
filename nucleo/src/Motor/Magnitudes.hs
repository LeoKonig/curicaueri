{-# LANGUAGE StrictData #-}
module Motor.Magnitudes where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Motor.Base
import Data.Aeson (withText)
import qualified Data.Aeson as A

-- | Un modificador aporta (sumando, porcentaje).
data Aporte = Aporte { sumando :: Fijo, porcentaje :: Fijo }
  deriving (Eq, Show)

instance Semigroup Aporte where
  Aporte a p <> Aporte a' p' = Aporte (a .+. a') (p .+. p')

instance Monoid Aporte where
  mempty = Aporte (Fijo 0) (Fijo 0)

newtype Magnitud = Magnitud Text
  deriving (Eq, Ord, Show)

data Fuente = Fuente { fuenteTipo :: Text, fuenteRef :: Text }
  deriving (Eq, Show)

data Alcance = AlcancePropia | AlcanceRuta | AlcanceCeldas
  deriving (Eq, Show)

data Modificador = Modificador
  { modId        :: Int
  , modMagnitud  :: Magnitud
  , modEntidad   :: EntRef
  , modAporte    :: Aporte
  , modFuente    :: Fuente
  , modInicio    :: Maybe Tick
  , modFin       :: Maybe Tick
  , modCondicion :: Maybe Text      -- TODO: tipo real
  , modAlcance   :: Alcance
  } deriving (Eq, Show)

data RangoMag = RangoMag { minMag :: Fijo, maxMag :: Fijo }
  deriving (Eq, Show)

-- | La explicación es el cálculo: no hay otra ruta al valor efectivo.
valorEfectivo :: RangoMag -> Fijo -> [Modificador] -> Fijo
valorEfectivo (RangoMag lo hi) base mods =
  let Aporte sa sp = foldMap modAporte mods
      v = (base .+. sa) .*. (uno .+. sp)
  in rangoFijo lo hi v

-- | Un modificador cuenta en el tick t si ya empezó y aún no terminó:
-- inicio ≤ t < fin. Sin inicio, cuenta desde siempre; sin fin, para siempre.
activoEn :: Tick -> Modificador -> Bool
activoEn t m = maybe True (<= t) (modInicio m) && maybe True (t <) (modFin m)

-- | Almacén: base y modificadores por (entidad, magnitud).
data AlmacenMag = AlmacenMag
  { almacenBase :: Fijo
  , almacenMods :: [Modificador]
  } deriving (Eq, Show)

type Almacen = Map (EntRef, Magnitud) AlmacenMag

data DefMagnitud = DefMagnitud
  { dmId                  :: Text        -- id estable, p.ej. "faccion.legitimidad"
  , dmRango               :: RangoMag
  , dmClave               :: Text        -- clave de localización, p.ej. "m.faccion.legitimidad"
  , dmFormato             :: Maybe Text  -- "entero" | "porcentaje" | ...
  , dmEscritoresMultiples :: Bool        -- default False
  } deriving (Eq, Show)

-- | Valor efectivo en el tick t: solo cuentan los modificadores activos.
valorEn :: Tick -> RangoMag -> AlmacenMag -> Fijo
valorEn t r x = valorEfectivo r (almacenBase x) (filter (activoEn t) (almacenMods x))

-- | Id para un modificador nuevo: uno más que el mayor del almacén. Es
-- determinista porque solo depende del almacén.
siguienteModId :: Almacen -> Int
siguienteModId alm =
  1 + maximum (0 : [ modId m | x <- Map.elems alm, m <- almacenMods x ])

-- | Añade un modificador a su (entidad, magnitud), con un id nuevo.
-- Devuelve también el id asignado, para quien quiera terminarlo después.
agregarModificador :: Modificador -> Almacen -> (Almacen, Int)
agregarModificador m alm =
  let i  = siguienteModId alm
      m' = m { modId = i }
      upd Nothing  = Just (AlmacenMag (Fijo 0) [m'])
      upd (Just x) = Just x { almacenMods = almacenMods x ++ [m'] }
  in (Map.alter upd (modEntidad m, modMagnitud m) alm, i)

-- | Quita los modificadores que ya terminaron (fin ≤ t) y los devuelve en
-- orden de (entidad, magnitud, id), para que cada uno emita su hecho.
expirar :: Tick -> Almacen -> (Almacen, [Modificador])
expirar t alm =
  let terminado m = maybe False (<= t) (modFin m)
      vencidos = [ m | x <- Map.elems alm, m <- almacenMods x, terminado m ]
      alm' = Map.map (\x -> x { almacenMods = filter (not . terminado) (almacenMods x) }) alm
  in (alm', vencidos)

sumarBase :: EntRef -> Magnitud -> Fijo -> Almacen -> Almacen
sumarBase e m delta = Map.alter upd (e, m)
  where
    upd Nothing  = Just (AlmacenMag delta [])
    upd (Just x) = Just x { almacenBase = almacenBase x .+. delta }

fijarBase :: EntRef -> Magnitud -> Fijo -> Almacen -> Almacen
fijarBase e m v = Map.alter upd (e, m)
  where
    upd Nothing  = Just (AlmacenMag v [])
    upd (Just x) = Just x { almacenBase = v }

instance A.FromJSON Magnitud where
  parseJSON = withText "Magnitud" (pure . Magnitud)
instance A.ToJSON Magnitud where
  toJSON (Magnitud m) = A.toJSON m
