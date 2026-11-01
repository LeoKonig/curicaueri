{-# LANGUAGE StrictData #-}
module Motor.Magnitudes where

import Data.Int (Int64)
import Data.IntSet (IntSet)
import qualified Data.IntSet as IntSet
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

-- | Condiciones sobre el estado visible. Un lenguaje pequeño y cerrado: se
-- valida al cargar y se evalúa sin efectos. Lo usan el guion (fases y
-- situaciones) y los modificadores condicionales; no hay otro lenguaje de
-- condiciones. Vive aquí, y no en "Motor.Guion", porque el modificador la
-- necesita y el guion ya importa este módulo.
data Condicion
  = Siempre
  | Mayor EntRef Magnitud Fijo        -- ^ valor efectivo > umbral
  | Menor EntRef Magnitud Fijo        -- ^ valor efectivo < umbral
  | DesdeTick Int64                  -- ^ a partir de un día (en el JSON, "desde_fecha")
  | Todas [Condicion]
  | Alguna [Condicion]
  | No Condicion
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
  , modCondicion :: Maybe Condicion -- ^ si la tiene, cuenta solo mientras está vigente (ver 'cuentaEn')
  , modAlcance   :: Alcance
  , modDetalle   :: [(Text, Fijo)]  -- ^ de qué salió su valor (copias, fieles…), para el desglose; vacío por omisión.
                                    --   No forma parte de su identidad: esa es la fuente.
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

-- | ¿Cuenta el modificador en el tick t? Tiene que estar en su ventana y,
-- si es condicional, su id tiene que estar entre los vigentes: el conjunto
-- que el paso 16 calcula al empezar la veintena (@derivadoVigentes@). La
-- condición no se evalúa aquí: vale toda la veintena, igual que el resto del
-- derivado (documento funcional, sección 6).
cuentaEn :: IntSet -> Tick -> Modificador -> Bool
cuentaEn vig t m =
  activoEn t m && maybe True (const (modId m `IntSet.member` vig)) (modCondicion m)

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

-- | Valor efectivo en el tick t: solo cuentan los modificadores que
-- 'cuentaEn' acepta, dados los vigentes del derivado.
valorEn :: IntSet -> Tick -> RangoMag -> AlmacenMag -> Fijo
valorEn vig t r x = valorEfectivo r (almacenBase x) (filter (cuentaEn vig t) (almacenMods x))

-- | Evalúa una condición sobre el almacén. Los valores que lee son efectivos,
-- con los modificadores condicionales que digan @vig@. Una magnitud que no
-- existe vale 0; si falta en el catálogo, no se acota.
evaluarCondicion :: Map Magnitud DefMagnitud -> IntSet -> Tick -> Almacen -> Condicion -> Bool
evaluarCondicion cat vig t alm = go
  where
    sinRango = RangoMag (Fijo minBound) (Fijo maxBound)
    valor r m = case Map.lookup (r, m) alm of
      Nothing -> Fijo 0
      Just x  -> valorEn vig t (maybe sinRango dmRango (Map.lookup m cat)) x
    go = \c -> case c of
      Siempre     -> True
      Mayor r m u -> valor r m > u
      Menor r m u -> valor r m < u
      DesdeTick n -> let Tick tt = t in tt >= n
      Todas cs    -> all go cs
      Alguna cs   -> any go cs
      No c'       -> not (go c')

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
