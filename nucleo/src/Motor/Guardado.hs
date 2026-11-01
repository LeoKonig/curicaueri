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
import Motor.Recorrido (grafoDe)

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

-- | La condición de un modificador se guarda con sus umbrales y ticks tal
-- cual (no con las fechas del guion): lo guardado no depende del calendario.
instance ToJSON Condicion where
  toJSON = \case
    Siempre       -> object ["tipo" .= ("siempre" :: Text)]
    Mayor r m u   -> object ["tipo" .= ("mayor" :: Text), "entidad" .= r, "magnitud" .= m, "umbral" .= u]
    Menor r m u   -> object ["tipo" .= ("menor" :: Text), "entidad" .= r, "magnitud" .= m, "umbral" .= u]
    DesdeTick n   -> object ["tipo" .= ("desde_tick" :: Text), "tick" .= n]
    Todas cs      -> object ["tipo" .= ("todas" :: Text), "condiciones" .= cs]
    Alguna cs     -> object ["tipo" .= ("alguna" :: Text), "condiciones" .= cs]
    No c          -> object ["tipo" .= ("no" :: Text), "condicion" .= c]
instance FromJSON Condicion where
  parseJSON = withObject "Condicion" $ \o -> do
    t <- o .: "tipo" :: Parser Text
    case t of
      "siempre"    -> pure Siempre
      "mayor"      -> Mayor <$> o .: "entidad" <*> o .: "magnitud" <*> o .: "umbral"
      "menor"      -> Menor <$> o .: "entidad" <*> o .: "magnitud" <*> o .: "umbral"
      "desde_tick" -> DesdeTick <$> o .: "tick"
      "todas"      -> Todas <$> o .: "condiciones"
      "alguna"     -> Alguna <$> o .: "condiciones"
      "no"         -> No <$> o .: "condicion"
      _            -> fail ("Condicion desconocida: " <> T.unpack t)

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
  toJSON m = object $
    [ "id"        .= modId m
    , "magnitud"  .= modMagnitud m
    , "entidad"   .= modEntidad m
    , "aporte"    .= modAporte m
    , "fuente"    .= modFuente m
    , "inicio"    .= modInicio m
    , "fin"       .= modFin m
    , "condicion" .= modCondicion m
    , "alcance"   .= modAlcance m
    ] ++ [ "detalle" .= [ object ["nombre" .= n, "valor" .= v] | (n, v) <- modDetalle m ] | not (null (modDetalle m)) ]
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
      <*> (maybe (pure []) (mapM (withObject "detalle" (\d -> (,) <$> d .: "nombre" <*> d .: "valor"))) =<< o .:? "detalle")
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

-- Las monedas se guardan como lista: EntRef no es clave de objeto JSON.
monedasAJson :: Map.Map EntRef EstadoMonetario -> Value
monedasAJson m = toJSON
  [ object [ "entidad" .= e, "moneda" .= emMoneda em, "desde" .= emDesde em
           , "historial" .= [ object [ "tick" .= t, "precio" .= p ] | (t, p) <- emHistorial em ] ]
  | (e, em) <- Map.toAscList m ]

monedasDeJson :: Value -> Parser (Map.Map EntRef EstadoMonetario)
monedasDeJson = withArray "monedas" $ \xs -> Map.fromList <$> mapM leerMoneda (toList xs)
  where
    leerMoneda = withObject "moneda" $ \o -> do
      e <- o .: "entidad"
      hist <- o .: "historial" >>= mapM (withObject "precio" (\h -> (,) <$> h .: "tick" <*> h .: "precio"))
      em <- EstadoMonetario <$> o .: "moneda" <*> o .: "desde" <*> pure hist
      pure (e, em)

instance (ToJSON (PlanDe s)) => ToJSON (Comun s) where
  toJSON c = object
    [ "magnitudes" .= almacenAJson (comunMagnitudes c)
    , "decisiones" .= comunDecisiones c
    , "planes"     .= comunPlanes c
    , "cronica"    .= toJSON (toList (comunCronica c))
    , "calendario" .= comunCalendario c
    , "director"   .= comunDirector c
    , "monedas"    .= monedasAJson (comunMonedas c)
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
      <*> (maybe (pure Map.empty) monedasDeJson =<< o .:? "monedas")   -- guardados anteriores a la moneda

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

-- | La versión del formato de guardado. Sube cuando un guardado anterior ya no
-- puede cargarse con valores por defecto. No hay migraciones: V5 pide que un
-- guardado antiguo se migre «si hay migración» y, si no, se rechace con un
-- aviso claro, y mientras no haya partidas reales que conservar no se escribe
-- ninguna.
--
-- * 1: el formato inicial.
-- * 2: cambió la forma del estado del juego (el tesoro, el prestigio y la
--   legitimidad pasaron al almacén de magnitudes y el estado guarda al
--   cazonci); los guardados de la 1 se rechazan.
versionGuardado :: Int
versionGuardado = 2

data EstadoEnDisco s = EstadoEnDisco
  { edTick    :: Tick
  , edPersist :: Persistente s
  , edOrigenT :: Tick
  , edOrigenP :: Persistente s
  }

instance (ToJSON s, ToJSON (PlanDe s)) => ToJSON (EstadoEnDisco s) where
  toJSON e = object
    [ "version" .= versionGuardado
    , "tick"    .= edTick e
    , "persist" .= edPersist e
    , "origenT" .= edOrigenT e
    , "origenP" .= edOrigenP e
    ]
instance (FromJSON s, FromJSON (PlanDe s)) => FromJSON (EstadoEnDisco s) where
  parseJSON = withObject "EstadoEnDisco" $ \o -> do
    v <- o .: "version" :: Parser Int
    if v == versionGuardado
      then EstadoEnDisco <$> o .: "tick" <*> o .: "persist"
                         <*> o .: "origenT" <*> o .: "origenP"
      else fail ("versión de guardado desconocida: " <> show v)

-- ---------------------------------------------------------------------------
-- guardar / cargar
-- ---------------------------------------------------------------------------

guardar :: (ToJSON s, ToJSON (PlanDe s)) => Estado s -> BL.ByteString
guardar est = A.encode $ EstadoEnDisco
  (estadoTick est)
  (estadoPersistente est)
  (origenTick (estadoOrigen est))
  (origenPersistente (estadoOrigen est))

-- | Rechaza un guardado de otra versión con un aviso que dice qué pasó y qué
-- hacer, en lugar del error de estructura que daría después. Un guardado sin
-- versión, o cuya versión no es un entero, sí es un error de estructura.
comprobarVersionGuardado :: A.Value -> Either ErrorCarga ()
comprobarVersionGuardado v =
  case AT.parseEither (withObject "guardado" (\o -> o .:? "version")) v of
    Left err -> Left (estructura (T.pack err))
    Right Nothing -> Left (estructura "el guardado no declara su versión")
    Right (Just k)
      | k == versionGuardado -> Right ()
      | k < versionGuardado ->
          Left (ErrorCarga ErrorVersion "" "version"
            ("esta partida es de la versión " <> tshow k <> " del guardado y este juego lee la "
             <> tshow versionGuardado <> ". No hay migración para esa versión: "
             <> "las partidas anteriores se descartan, empieza una nueva."))
      | otherwise ->
          Left (ErrorCarga ErrorVersion "" "version"
            ("esta partida es de la versión " <> tshow k <> " del guardado, posterior a la "
             <> tshow versionGuardado <> " que lee este juego: actualiza el juego."))
  where
    estructura = ErrorCarga ErrorEstructura "" "version"
    tshow = T.pack . show

-- | La ley: `derivado <$> cargar j m (guardar s) == Right (derivado s)`
-- para todo estado s, incluso a mitad de una veintena.
cargar :: (FromJSON s, FromJSON (PlanDe s))
       => Juego s c -> Mapa -> BL.ByteString -> Either ErrorCarga (Estado s)
cargar j m bs = do
  crudo <- case A.eitherDecode bs of
    Left err -> Left (ErrorCarga ErrorEstructura "" "" (T.pack err))
    Right x  -> Right (x :: A.Value)
  comprobarVersionGuardado crudo
  ed <- case A.fromJSON crudo of
    A.Error err -> Left (ErrorCarga ErrorEstructura "" "" (T.pack err))
    A.Success x -> Right x
  let d = derivar j (grafoDe m) (edOrigenT ed) (edOrigenP ed)
  pure (Estado (edTick ed) (edPersist ed)
               (Origen (edOrigenT ed) (edOrigenP ed)) d)
