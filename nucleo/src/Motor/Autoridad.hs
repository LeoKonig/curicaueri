{-# LANGUAGE StrictData, OverloadedStrings, LambdaCase #-}
-- | Ejes de poder y requisitos de autoridad de los comandos (V5, *Facciones,
-- poder y autoridad*).
--
-- En el prototipo esto no cambia nada del juego: todos los comandos usan el
-- requisito por omisión (@{"eje": "todo", "clase": "exclusivo"}@), que el
-- soberano siempre cumple, y ninguna fórmula lee los ejes. Existe desde ahora
-- para que los comandos del juego completo nazcan con su requisito puesto y
-- los del prototipo no se enteren.
--
-- Los ejes son datos (@datos/ejes.json@): cambiar de cinco a cuatro o seis es
-- cambiar ese archivo. Cada escenario dice cuáles están activos.
module Motor.Autoridad
  ( -- * Requisitos
    ClaseAutoridad (..)
  , Requisito (..)
  , requisitoPorOmision
  , ejeTodo
    -- * Ejes
  , Eje (..)
  , cargarEjes
  , ejesActivos
  , validarRequisitos
  ) where

import Data.Aeson (Value)
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import Data.List (nub)
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Carga (CategoriaError (..), ErrorCarga (..), Validacion (..), falla)

-- | Exclusivo: un solo titular por entidad y eje puede ejecutarlo.
-- Concurrente: cualquier titular, y los efectos se suman.
data ClaseAutoridad = Exclusivo | Concurrente
  deriving (Eq, Show)

-- | El eje principal que habilita un comando y su clase. Si un comando toca
-- dos ejes, solo el principal habilita; el otro modifica costo o efecto.
data Requisito = Requisito
  { reqEje   :: Text
  , reqClase :: ClaseAutoridad
  } deriving (Eq, Show)

-- | El eje comodín: lo cumple quien es soberano de la entidad.
ejeTodo :: Text
ejeTodo = "todo"

requisitoPorOmision :: Requisito
requisitoPorOmision = Requisito ejeTodo Exclusivo

instance A.ToJSON ClaseAutoridad where
  toJSON Exclusivo   = A.String "exclusivo"
  toJSON Concurrente = A.String "concurrente"

instance A.FromJSON ClaseAutoridad where
  parseJSON = A.withText "clase" $ \case
    "exclusivo"   -> pure Exclusivo
    "concurrente" -> pure Concurrente
    t             -> fail ("clase de autoridad desconocida: " <> T.unpack t)

instance A.ToJSON Requisito where
  toJSON r = A.object ["eje" A..= reqEje r, "clase" A..= reqClase r]

-- | Los dos campos son opcionales: lo que falte toma el valor por omisión.
instance A.FromJSON Requisito where
  parseJSON = A.withObject "requiere" $ \o ->
    Requisito <$> (maybe (reqEje requisitoPorOmision) id <$> o A..:? "eje")
              <*> (maybe (reqClase requisitoPorOmision) id <$> o A..:? "clase")

-- | Un eje de poder. Su capacidad es una magnitud de la facción; la eficacia
-- de un comando es esa capacidad dividida entre la referencia (100 para los
-- ejes nuevos, 50 para la legitimidad, que reutiliza su magnitud).
data Eje = Eje
  { ejId         :: Text
  , ejClave      :: Text      -- ^ clave de texto para la interfaz
  , ejMagnitud   :: Text      -- ^ magnitud de la facción que mide su capacidad
  , ejReferencia :: Fijo
  , ejBase       :: Fijo      -- ^ base por omisión de la magnitud
  } deriving (Eq, Show)

instance A.ToJSON Eje where
  toJSON e = A.object
    [ "id" A..= ejId e, "clave" A..= ejClave e, "magnitud" A..= ejMagnitud e
    , "referencia" A..= ejReferencia e, "base" A..= ejBase e ]

-- | Carga @ejes.json@. Acumula los errores: ids repetidos, el id reservado
-- "todo", referencias que no son positivas.
cargarEjes :: Text -> Value -> Validacion [Eje]
cargarEjes archivo v = case A.parseEither leer v of
  Left err -> falla (ErrorCarga ErrorEstructura archivo "" (T.pack err))
  -- Aplicativo y no monádico, para no parar en el primer error.
  Right es ->
    let ids = map ejId es
        repetidos = traverse (\i -> if length (filter (== i) ids) > 1
                                      then falla (ErrorCarga ErrorEsquema archivo ("ejes." <> i) "eje repetido")
                                      else pure ()) (nub ids)
    in repetidos *> traverse validar es
  where
    leer = A.withObject "ejes" $ \o -> o A..: "ejes" >>= mapM eje
    eje = A.withObject "eje" $ \o -> do
      i <- o A..: "id"
      Eje i <$> (maybe ("eje." <> i) id <$> o A..:? "clave")
            <*> o A..: "magnitud"
            <*> o A..: "referencia"
            <*> (maybe (desdeEntero 100) id <$> o A..:? "base")
    validar e =
      let ruta = "ejes." <> ejId e
          noReservado = if ejId e == ejeTodo
                          then falla (ErrorCarga ErrorEsquema archivo ruta "«todo» está reservado para el requisito por omisión")
                          else pure ()
          refPositiva = if ejReferencia e > Fijo 0 then pure ()
                        else falla (ErrorCarga ErrorRango archivo ruta "la referencia debe ser positiva")
      in e <$ noReservado <* refPositiva

-- | Los ejes que un escenario declara activos (@Nothing@: todos), en el orden
-- del archivo de ejes. Un id que no existe es un error de carga.
ejesActivos :: Text -> [Eje] -> Maybe [Text] -> Validacion [Eje]
ejesActivos _ es Nothing = pure es
ejesActivos archivo es (Just ids) =
  filter ((`elem` ids) . ejId) es
    <$ traverse (\i -> if i `elem` map ejId es then pure ()
                       else falla (ErrorCarga ErrorReferencia archivo "ejes_activos" ("eje desconocido: " <> i))) ids

-- | Cada requisito nombra "todo" o un eje declarado.
validarRequisitos :: Text -> [Eje] -> [(Text, Requisito)] -> Validacion ()
validarRequisitos archivo es reqs =
  () <$ traverse (\(cmd, r) ->
    if reqEje r == ejeTodo || reqEje r `elem` map ejId es then pure ()
    else falla (ErrorCarga ErrorReferencia archivo ("comandos." <> cmd <> ".requiere")
                  ("eje desconocido: " <> reqEje r))) reqs
