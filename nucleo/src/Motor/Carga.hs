{-# LANGUAGE StrictData, OverloadedStrings, TypeFamilies #-}
{-# OPTIONS_GHC -Wno-orphans #-}
module Motor.Carga where

import Data.Aeson (Value, withObject, withText, (.:), (.:?))
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as KM
import Data.Foldable (toList)
import Data.List (nub)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Efectos (Programa, compilarPrograma)
import Motor.Magnitudes
import Motor.Mapa (Terreno(..), Recurso(..))
import Motor.Sistema (Sistema(..), NombreSistema)
import Motor.Vista (ClaveLoc(..))

-- ---------------------------------------------------------------------------
-- Validación acumulativa
-- ---------------------------------------------------------------------------

data Validacion a = Validacion
  { valErrores :: [ErrorCarga]
  , valValor   :: Maybe a
  } deriving (Show)

instance Functor Validacion where
  fmap f (Validacion es mv) = Validacion es (fmap f mv)

instance Applicative Validacion where
  pure x = Validacion [] (Just x)
  Validacion es1 f <*> Validacion es2 v =
    Validacion (es1 ++ es2) (f <*> v)

instance Monad Validacion where
  Validacion es1 mv >>= k = case mv of
    Nothing -> Validacion es1 Nothing
    Just x  -> let Validacion es2 r = k x
               in Validacion (es1 ++ es2) r

falla :: ErrorCarga -> Validacion a
falla e = Validacion [e] Nothing

data CategoriaError
  = ErrorEsquema
  | ErrorReferencia
  | ErrorRango
  | ErrorVersion
  | ErrorEstructura
  deriving (Eq, Show)

data ErrorCarga = ErrorCarga
  { errCategoria :: CategoriaError
  , errArchivo   :: Text
  , errRuta      :: Text
  , errMensaje   :: Text
  } deriving (Eq, Show)

-- ---------------------------------------------------------------------------
-- Archivos y catálogo
-- ---------------------------------------------------------------------------

data ArchivoJSON = ArchivoJSON
  { ajNombre         :: Text
  , ajVersionEsquema :: Int
  , ajContenido      :: Value
  } deriving (Show)

data Personalidad = Personalidad
  { persId           :: Text
  , persAgresividad  :: Int
  , persUmbralAtaque :: Fijo
  } deriving (Eq, Show)

data Catalogo = Catalogo
  { catMagnitudes     :: Map Magnitud DefMagnitud
  , catHechos         :: Set Text
  , catConstantes     :: Map Text Fijo
  , catPersonalidades :: Map Text Personalidad
  , catSistemas       :: [Text]
  , catProgramas      :: Map (Text, Text) Programa   -- (evento, opción) -> programa compilado
  } deriving (Eq, Show)

instance Semigroup Catalogo where
  a <> b = Catalogo
    { catMagnitudes     = Map.union (catMagnitudes b) (catMagnitudes a)   -- el último archivo gana
    , catHechos         = catHechos a <> catHechos b
    , catConstantes     = Map.union (catConstantes b) (catConstantes a)
    , catPersonalidades = Map.union (catPersonalidades b) (catPersonalidades a)
    , catSistemas       = catSistemas a <> catSistemas b
    , catProgramas      = Map.union (catProgramas b) (catProgramas a)
    }
instance Monoid Catalogo where
  mempty = Catalogo Map.empty Set.empty Map.empty Map.empty [] Map.empty

versionActual :: Int
versionActual = 1

-- ---------------------------------------------------------------------------
-- FromJSON
-- ---------------------------------------------------------------------------

-- | Fijo desde string ("3", "1.5", "-2.25") o número JSON. Los strings y
-- los números pasan por la misma `desdeDecimal`, así que el criterio de
-- "más de cuatro decimales falla al cargar" es único.
instance A.FromJSON ClaveLoc where
  parseJSON = withText "ClaveLoc" (pure . ClaveLoc)

instance A.FromJSON Terreno where
  parseJSON = withText "Terreno" (pure . Terreno)

instance A.FromJSON Recurso where
  parseJSON = withText "Recurso" (pure . Recurso)

instance A.FromJSON RangoMag where
  parseJSON = withObject "RangoMag" $ \o ->
    RangoMag <$> o .: "min" <*> o .: "max"

instance A.FromJSON DefMagnitud where
  parseJSON = withObject "DefMagnitud" $ \o ->
    DefMagnitud
      <$> o .: "id"
      <*> o .: "rango"
      <*> o .: "clave"
      <*> o .:? "formato"
      <*> (fromMaybe False <$> o .:? "escritores_multiples")

instance A.FromJSON Personalidad where
  parseJSON = withObject "Personalidad" $ \o ->
    Personalidad
      <$> o .: "id"
      <*> o .: "agresividad"
      <*> o .: "umbral_ataque"

-- ---------------------------------------------------------------------------
-- Carga y ensamblaje
-- ---------------------------------------------------------------------------

cargarArchivo :: Text -> Value -> Validacion ArchivoJSON
cargarArchivo nombre v =
  case A.parseMaybe (withObject "archivo" (.: "version_esquema")) v of
    Just ver -> pure (ArchivoJSON nombre ver v)
    Nothing  -> falla (ErrorCarga ErrorEstructura nombre "version_esquema"
                                "campo faltante o inválido")

cargarDatos :: [(Text, Value)] -> Validacion Catalogo
cargarDatos crudos = do
  archivos   <- traverse (uncurry cargarArchivo) crudos
  archivos'  <- traverse validarVersion archivos
  archivos'' <- traverse aplicarMigracion archivos'
  cats       <- traverse validarArchivo archivos''
  pure (mconcat cats)

validarVersion :: ArchivoJSON -> Validacion ArchivoJSON
validarVersion a
  | ajVersionEsquema a > versionActual =
      falla (ErrorCarga ErrorVersion (ajNombre a) ""
             ("versión de esquema " <> T.pack (show (ajVersionEsquema a))
              <> " mayor que la del núcleo ("
              <> T.pack (show versionActual) <> ")"))
  | otherwise = pure a

-- | Cadena de migraciones puras JSON_n → JSON_(n+1). En Hito 1a es identidad;
-- los eslabones se añaden con el primer cambio de esquema que los pida.
aplicarMigracion :: ArchivoJSON -> Validacion ArchivoJSON
aplicarMigracion = pure

validarArchivo :: ArchivoJSON -> Validacion Catalogo
validarArchivo a = mconcat <$> sequenceA
  [ validarMagnitudes      n v
  , validarPersonalidadesV n v
  , validarConstantesV     n v
  , validarHechosV         n v
  , validarEventosV        n v
  ]
  where
    n = ajNombre a
    v = ajContenido a

-- | Una sección ausente no es error. Una sección presente pero mal formada sí,
-- y cada elemento mal formado da su propio error sin tapar a los demás.
buscar :: Text -> Value -> Maybe Value
buscar clave (A.Object o) = KM.lookup (K.fromText clave) o
buscar _ _                = Nothing

parsearCon :: A.FromJSON a => Text -> Text -> Value -> Validacion a
parsearCon archivo ruta v = case A.parseEither A.parseJSON v of
  Right x -> pure x
  Left e  -> falla (ErrorCarga ErrorEsquema archivo ruta (T.pack e))

lista :: A.FromJSON a => Text -> Text -> Value -> Validacion [a]
lista archivo clave v = case buscar clave v of
  Nothing           -> pure []
  Just (A.Array xs) -> traverse elemento (zip [0 :: Int ..] (toList xs))
  Just _            -> falla (ErrorCarga ErrorEstructura archivo clave "se esperaba una lista")
  where
    elemento (i, x) = parsearCon archivo (clave <> "[" <> T.pack (show i) <> "]") x

objeto :: A.FromJSON a => Text -> Text -> Value -> Validacion [(Text, a)]
objeto archivo clave v = case buscar clave v of
  Nothing            -> pure []
  Just (A.Object o)  -> traverse campo (KM.toList o)
  Just _             -> falla (ErrorCarga ErrorEstructura archivo clave "se esperaba un objeto")
  where
    campo (k, x) = (,) (K.toText k) <$> parsearCon archivo (clave <> "." <> K.toText k) x

validarMagnitudes :: Text -> Value -> Validacion Catalogo
validarMagnitudes archivo v = do
  defs  <- lista archivo "magnitudes" v
  defs' <- traverse checkRango defs
  pure mempty { catMagnitudes = Map.fromList [(Magnitud (dmId d), d) | d <- defs'] }
  where
    checkRango d
      | minMag r > maxMag r =
          falla (ErrorCarga ErrorRango archivo (dmId d)
                 ("rango invertido: min=" <> T.pack (show (minMag r))
                  <> " max=" <> T.pack (show (maxMag r))))
      | otherwise = pure d
      where r = dmRango d

validarPersonalidadesV :: Text -> Value -> Validacion Catalogo
validarPersonalidadesV archivo v = do
  ps  <- lista archivo "personalidades" v
  ps' <- traverse validarPersonalidad ps
  pure mempty { catPersonalidades = Map.fromList [(persId p, p) | p <- ps'] }

validarPersonalidad :: Personalidad -> Validacion Personalidad
validarPersonalidad p
  | persAgresividad p < 0 || persAgresividad p > 100 =
      falla (ErrorCarga ErrorRango "" (persId p)
             ("agresividad fuera de rango: "
              <> T.pack (show (persAgresividad p))))
  | persUmbralAtaque p <= Fijo 0 =
      falla (ErrorCarga ErrorRango "" (persId p)
             "umbral_ataque debe ser positivo")
  | otherwise = pure p

validarConstantesV :: Text -> Value -> Validacion Catalogo
validarConstantesV archivo v = do
  cs <- objeto archivo "constantes" v
  pure mempty { catConstantes = Map.fromList cs }

validarHechosV :: Text -> Value -> Validacion Catalogo
validarHechosV archivo v = do
  hs <- lista archivo "hechos" v
  pure mempty { catHechos = Set.fromList hs }


-- | Eventos: cada opción se compila a un Programa al cargar. Un efecto mal
-- escrito detiene la carga con su ruta exacta, no aparece en el tick 47.
data EventoJSON = EventoJSON Text [OpcionJSON]
data OpcionJSON = OpcionJSON Text [Value]

instance A.FromJSON EventoJSON where
  parseJSON = withObject "evento" $ \o -> EventoJSON <$> o .: "id" <*> o .: "opciones"
instance A.FromJSON OpcionJSON where
  parseJSON = withObject "opcion" $ \o -> OpcionJSON <$> o .: "id" <*> o .: "efectos"

validarEventosV :: Text -> Value -> Validacion Catalogo
validarEventosV archivo v = do
  evs   <- lista archivo "eventos" v
  pares <- concat <$> traverse compilarEvento evs
  pure mempty { catProgramas = Map.fromList pares }
  where
    compilarEvento (EventoJSON eid ops) = traverse (compilarOpcion eid) ops
    compilarOpcion eid (OpcionJSON oid efs) = case compilarPrograma efs of
      Left err -> falla (ErrorCarga ErrorEsquema archivo
                          ("eventos." <> eid <> ".opciones." <> oid) err)
      Right p  -> pure ((eid, oid), p)

-- ---------------------------------------------------------------------------
-- Orden de sistemas
-- ---------------------------------------------------------------------------

data AvisoOrden
  = EscrituraDuplicada NombreSistema NombreSistema Magnitud
  | LecturaDeTicAnterior NombreSistema NombreSistema Magnitud
  deriving (Eq, Show)

-- | Validación estática del orden de sistemas, sobre la lista en el orden
-- en que corren en el tick.
--
-- Reglas:
--
-- * 'EscrituraDuplicada': dos sistemas que pueden coincidir en un tick
--   escriben la misma magnitud. Como todas las cadencias coinciden en algún
--   tick (diario corre siempre; veintena y anual se solapan en el día 0,
--   que también es día de veintena), se comprueba cualquier par. Se exceptúan
--   las magnitudes con @escritores_multiples = true@.
-- * 'LecturaDeTicAnterior': un sistema lee una magnitud que escribe un
--   sistema posterior en la lista. Es válido (se lee el valor del tick
--   anterior), pero debe ser deliberado y por eso se marca.
validarOrdenSistemas :: Map Magnitud DefMagnitud -> [Sistema s] -> [AvisoOrden]
validarOrdenSistemas catalogo sistemas = nub $ concat
  [ [ EscrituraDuplicada (sisNombre a) (sisNombre b) m
    | (ia, a) <- indexed
    , (ib, b) <- indexed
    , ia < ib
    , m <- Set.toList (sisEscribe a `Set.intersection` sisEscribe b)
    , not (esMulti m)
    ]
  , [ LecturaDeTicAnterior (sisNombre a) (sisNombre b) m
    | (ia, a) <- indexed
    , (ib, b) <- indexed
    , ia < ib
    , m <- Set.toList (sisLee a `Set.intersection` sisEscribe b)
    ]
  ]
  where
    indexed = zip [0 :: Int ..] sistemas
    esMulti m = maybe False dmEscritoresMultiples (Map.lookup m catalogo)

-- | Por ahora identidad. La regla "el último gana para entidades, unión para
-- modificadores" y @"eliminar": true@ se implementa con el primer mod real.
aplicarMods :: [ArchivoJSON] -> [ArchivoJSON]
aplicarMods = id
