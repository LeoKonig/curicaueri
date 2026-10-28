{-# LANGUAGE StrictData, OverloadedStrings, TypeFamilies, LambdaCase, FlexibleContexts, FlexibleInstances, UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}
module Motor.Guardado where

import Data.Aeson
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as AT
import Data.Aeson.Types (Parser)
import qualified Data.ByteString.Lazy as BL
import Data.Foldable (toList)
import qualified Data.Map.Strict as Map
import qualified Data.Sequence as Seq
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Carga (ErrorCarga(..), CategoriaError(..))
import Motor.Estado
import Motor.Juego (Juego, derivar)
import Motor.Magnitudes
import Motor.Mapa (Mapa)

-- ---------------------------------------------------------------------------
-- Instancias JSON de los tipos del núcleo
-- ---------------------------------------------------------------------------

instance ToJSON Tick where toJSON (Tick t) = toJSON t
instance FromJSON Tick where
  parseJSON = fmap Tick . parseJSON

instance ToJSON FaccionId where toJSON (FaccionId n) = toJSON n
instance FromJSON FaccionId where
  parseJSON = fmap FaccionId . parseJSON
instance ToJSONKey FaccionId where
  toJSONKey = AT.toJSONKeyText (\(FaccionId n) -> T.pack (show n))
instance FromJSONKey FaccionId where
  fromJSONKey = FromJSONKeyTextParser $ \t ->
    case reads (T.unpack t) :: [(Int, String)] of
      [(n, "")] -> pure (FaccionId n)
      _         -> fail ("FaccionId inválido: " <> T.unpack t)

instance ToJSON Aporte where
  toJSON (Aporte s p) = object ["sumando" .= s, "porcentaje" .= p]
instance FromJSON Aporte where
  parseJSON = withObject "Aporte" $ \o ->
    Aporte <$> o .: "sumando" <*> o .: "porcentaje"

instance ToJSON Fuente where
  toJSON (Fuente t r) = object ["tipo" .= t, "ref" .= r]
instance FromJSON Fuente where
  parseJSON = withObject "Fuente" $ \o ->
    Fuente <$> o .: "tipo" <*> o .: "ref"

instance ToJSON Alcance where
  toJSON = \case
    AlcancePropia -> String "propia"
    AlcanceRuta   -> String "ruta"
    AlcanceCeldas -> String "celdas"
instance FromJSON Alcance where
  parseJSON = withText "Alcance" $ \t -> case t of
    "propia" -> pure AlcancePropia
    "ruta"   -> pure AlcanceRuta
    "celdas" -> pure AlcanceCeldas
    _        -> fail ("Alcance desconocido: " <> T.unpack t)

instance ToJSON Modificador where
  toJSON m = object
    [ "id"        .= modId m
    , "magnitud"  .= modMagnitud m
    , "entidad"   .= modEntidad m
    , "aporte"    .= modAporte m
    , "fuente"    .= modFuente m
    , "inicio"    .= modInicio m
    , "fin"       .= modFin m
    , "condicion" .= modCondicion m
    , "alcance"   .= modAlcance m
    ]
instance FromJSON Modificador where
  parseJSON = withObject "Modificador" $ \o ->
    Modificador
      <$> o .:  "id"
      <*> o .:  "magnitud"
      <*> o .:  "entidad"
      <*> o .:  "aporte"
      <*> o .:  "fuente"
      <*> o .:? "inicio"
      <*> o .:? "fin"
      <*> o .:? "condicion"
      <*> (fromMaybeDefault <$> o .:? "alcance")
    where fromMaybeDefault = maybe AlcancePropia id

instance ToJSON AlmacenMag where
  toJSON (AlmacenMag b ms) = object ["base" .= b, "mods" .= ms]
instance FromJSON AlmacenMag where
  parseJSON = withObject "AlmacenMag" $ \o ->
    AlmacenMag <$> o .: "base" <*> o .: "mods"

-- | El almacén se serializa como lista de entradas, en el orden determinista
-- de Map.toList. Son funciones y no instancias: una instancia para Almacen
-- (un sinónimo de Map) choca con la instancia de Map que ya trae aeson.
almacenAJson :: Almacen -> Value
almacenAJson m = toJSON
  [ object [ "entref" .= r, "magnitud" .= mn, "almacen" .= a ]
  | ((r, mn), a) <- Map.toList m ]

almacenDeJson :: Value -> Parser Almacen
almacenDeJson = withArray "Almacen" $ \arr ->
  Map.fromList <$> mapM unaEntrada (toList arr)
  where
    unaEntrada = withObject "entrada" $ \o -> do
      r  <- o .: "entref"
      mn <- o .: "magnitud"
      a  <- o .: "almacen"
      pure ((r, mn), a)

instance ToJSON ValorCtx where
  toJSON = \case
    CCantidad f -> object ["tag" .= ("cantidad" :: Text), "v" .= f]
    CEntero n   -> object ["tag" .= ("entero"   :: Text), "v" .= n]
    COpcion t   -> object ["tag" .= ("opcion"   :: Text), "v" .= t]
    CEntidad r  -> object ["tag" .= ("entidad"  :: Text), "v" .= r]
instance FromJSON ValorCtx where
  parseJSON = withObject "ValorCtx" $ \o -> do
    tag <- o .: "tag" :: Parser Text
    case tag of
      "cantidad" -> CCantidad <$> o .: "v"
      "entero"   -> CEntero   <$> o .: "v"
      "opcion"   -> COpcion   <$> o .: "v"
      "entidad"  -> CEntidad  <$> o .: "v"
      _          -> fail ("ValorCtx desconocido: " <> T.unpack tag)

instance ToJSON Pregunta where
  toJSON = \case
    PreguntaCantidad v lo hi -> object
      [ "tag"      .= ("cantidad" :: Text)
      , "variable" .= v, "min" .= lo, "max" .= hi ]
    PreguntaOpcion v opts -> object
      [ "tag"      .= ("opcion" :: Text)
      , "variable" .= v, "opciones" .= opts ]
instance FromJSON Pregunta where
  parseJSON = withObject "Pregunta" $ \o -> do
    tag <- o .: "tag" :: Parser Text
    case tag of
      "cantidad" -> PreguntaCantidad
                      <$> o .: "variable" <*> o .: "min" <*> o .: "max"
      "opcion"   -> PreguntaOpcion
                      <$> o .: "variable" <*> o .: "opciones"
      _          -> fail ("Pregunta desconocida: " <> T.unpack tag)

instance ToJSON Reanudacion where
  toJSON rn = object
    [ "evento"   .= rnEvento rn
    , "opcion"   .= rnOpcion rn
    , "siguiente".= rnSiguienteEfecto rn
    , "contexto" .= rnContexto rn
    ]
instance FromJSON Reanudacion where
  parseJSON = withObject "Reanudacion" $ \o ->
    Reanudacion
      <$> o .: "evento"
      <*> o .: "opcion"
      <*> o .: "siguiente"
      <*> o .: "contexto"

instance ToJSON DecisionPendiente where
  toJSON dp = object
    [ "id"        .= dpId dp
    , "pregunta"  .= dpPregunta dp
    , "reanudacion" .= dpReanudacion dp
    ]
instance FromJSON DecisionPendiente where
  parseJSON = withObject "DecisionPendiente" $ \o ->
    DecisionPendiente
      <$> o .: "id"
      <*> o .: "pregunta"
      <*> o .: "reanudacion"

instance ToJSON EntradaCronica where
  toJSON e = object
    [ "tick"      .= ecTick e
    , "tipo"      .= ecTipo e
    , "entidades" .= ecEntidades e
    , "clave"     .= ecClave e
    , "params"    .= ecParams e
    ]
instance FromJSON EntradaCronica where
  parseJSON = withObject "EntradaCronica" $ \o ->
    EntradaCronica
      <$> o .: "tick"
      <*> o .: "tipo"
      <*> o .: "entidades"
      <*> o .: "clave"
      <*> o .: "params"

instance ToJSON Disparo where
  toJSON x = object [ "tick" .= diTick x, "situacion" .= diSituacion x, "tipo" .= diTipo x, "fase" .= diFase x ]
instance FromJSON Disparo where
  parseJSON = withObject "Disparo" $ \o ->
    Disparo <$> o .: "tick" <*> o .: "situacion" <*> o .: "tipo" <*> o .: "fase"

instance ToJSON EstadoDirector where
  toJSON d = object
    [ "fase" .= edFase d, "sistemas" .= edSistemas d, "intensidades" .= edIntensidades d
    , "ultima" .= edUltima d, "historial" .= edHistorial d, "plazos" .= edPlazos d
    , "proxima_decision" .= edProximaDecision d ]
instance FromJSON EstadoDirector where
  parseJSON = withObject "EstadoDirector" $ \o ->
    EstadoDirector <$> o .: "fase" <*> o .: "sistemas" <*> o .: "intensidades"
                   <*> o .: "ultima" <*> o .: "historial" <*> o .: "plazos"
                   <*> (maybe 1 id <$> o .:? "proxima_decision")

instance (ToJSON (PlanDe s)) => ToJSON (Comun s) where
  toJSON c = object
    [ "magnitudes" .= almacenAJson (comunMagnitudes c)
    , "decisiones" .= comunDecisiones c
    , "planes"     .= comunPlanes c
    , "cronica"    .= toJSON (toList (comunCronica c))
    , "calendario" .= comunCalendario c
    , "director"   .= comunDirector c
    ]
instance (FromJSON (PlanDe s)) => FromJSON (Comun s) where
  parseJSON = withObject "Comun" $ \o ->
    Comun
      <$> (o .: "magnitudes" >>= almacenDeJson)
      <*> o .: "decisiones"
      <*> o .: "planes"
      <*> fmap Seq.fromList (o .: "cronica")
      <*> o .: "calendario"
      <*> (maybe directorInicial id <$> o .:? "director")   -- guardados anteriores al director

instance (ToJSON s, ToJSON (PlanDe s)) => ToJSON (Persistente s) where
  toJSON p = object
    [ "comun" .= persistenteComun p
    , "juego" .= persistenteJuego p
    ]
instance (FromJSON s, FromJSON (PlanDe s)) => FromJSON (Persistente s) where
  parseJSON = withObject "Persistente" $ \o ->
    Persistente <$> o .: "comun" <*> o .: "juego"

-- ---------------------------------------------------------------------------
-- Estado en disco: tick, persistente, origen. El derivado se recalcula.
-- ---------------------------------------------------------------------------

data EstadoEnDisco s = EstadoEnDisco
  { edTick    :: Tick
  , edPersist :: Persistente s
  , edOrigenT :: Tick
  , edOrigenP :: Persistente s
  }

instance (ToJSON s, ToJSON (PlanDe s)) => ToJSON (EstadoEnDisco s) where
  toJSON e = object
    [ "version" .= (1 :: Int)
    , "tick"    .= edTick e
    , "persist" .= edPersist e
    , "origenT" .= edOrigenT e
    , "origenP" .= edOrigenP e
    ]
instance (FromJSON s, FromJSON (PlanDe s)) => FromJSON (EstadoEnDisco s) where
  parseJSON = withObject "EstadoEnDisco" $ \o -> do
    v <- o .: "version" :: Parser Int
    case v of
      1 -> EstadoEnDisco <$> o .: "tick" <*> o .: "persist"
                         <*> o .: "origenT" <*> o .: "origenP"
      _ -> fail ("versión de guardado desconocida: " <> show v)

-- ---------------------------------------------------------------------------
-- guardar / cargar
-- ---------------------------------------------------------------------------

guardar :: (ToJSON s, ToJSON (PlanDe s)) => Estado s -> BL.ByteString
guardar est = A.encode $ EstadoEnDisco
  (estadoTick est)
  (estadoPersistente est)
  (origenTick (estadoOrigen est))
  (origenPersistente (estadoOrigen est))

-- | La ley: `derivado <$> cargar j m (guardar s) == Right (derivado s)`
-- para todo estado s, incluso a mitad de una veintena.
cargar :: (FromJSON s, FromJSON (PlanDe s))
       => Juego s c -> Mapa -> BL.ByteString -> Either ErrorCarga (Estado s)
cargar j m bs = do
  ed <- case A.eitherDecode bs of
    Left err -> Left (ErrorCarga ErrorEstructura "" "" (T.pack err))
    Right x  -> Right x
  let d = derivar j m (edOrigenT ed) (edOrigenP ed)
  pure (Estado (edTick ed) (edPersist ed)
               (Origen (edOrigenT ed) (edOrigenP ed)) d)
