{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | El guion de un escenario: sus fases (los actos), las situaciones que se
-- le pueden presentar al jugador y los parámetros del director que marca el
-- ritmo. Todo es dato: cambiar un acto es editar el guion, no el código.
--
-- Ver V5, *Actos modulares*, y el documento funcional, sección 11b.
module Motor.Guion
  ( -- * Tipos
    Condicion (..)
  , Fase (..)
  , Situacion (..)
  , ParamsDirector (..)
  , paramsPorOmision
  , Guion (..)
  , guionVacio
  , Entorno (..)
  , entornoSimple
    -- * Carga
  , cargarGuion
  ) where

import Data.Aeson (Value)
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import Data.Int (Int64)
import Data.List (nub)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Calendario (Fecha (..), diaJuliano)
import Motor.Carga (CategoriaError (..), ErrorCarga (..), Validacion (..), falla)
import Motor.Efectos (Programa, compilarPrograma)
import Motor.Magnitudes (Condicion (..), Magnitud (..))
import Motor.Mapa (Mapa)
import Motor.Moneda (Economia, economiaVacia)

-- | Una fase del escenario. Empieza cuando llega su día o se cumple su
-- condición, lo que ocurra primero, y nunca vuelve atrás. Mientras dura,
-- solo corren los sistemas que declara, con las intensidades que declara.
data Fase = Fase
  { faId          :: Text
  , faDesde       :: Maybe Int64            -- ^ tick en que empieza, si es por fecha
  , faCondicion   :: Maybe Condicion        -- ^ o la condición que la adelanta
  , faSistemas    :: Maybe [Text]           -- ^ sistemas activos (Nothing: todos)
  , faIntensidades :: Map Text Fijo         -- ^ intensidad de cada fuente de presión
  } deriving (Eq, Show)

-- | Una decisión que se le puede presentar al jugador.
data Situacion = Situacion
  { siId           :: Text
  , siTipo         :: Text                  -- ^ del vocabulario cerrado del guion
  , siPeso         :: Fijo
  , siEnfriamiento :: Int                   -- ^ días mínimos entre dos apariciones
  , siPlazo        :: Int                   -- ^ días para responder; después, la primera opción
  , siFases        :: [Text]                -- ^ fases en que puede salir (vacío: todas)
  , siCondicion    :: Condicion
  , siOpciones     :: [(Text, Programa)]    -- ^ al menos una; la primera es la de omisión
  } deriving (Eq, Show)

-- | El ritmo. Probabilidad diaria de presentar una situación:
--   0 durante @espaciado@ días tras la anterior; después
--   min(probMax, probBase + tension · días de más).
-- El peso de cada situación elegible se multiplica por
--   1 / (1 + penalVariedad · veces que su tipo salió en las últimas
--   @ventanaVariedad@ situaciones), y por (1 + bonoNovedad) si su tipo
--   aún no salió en la década en curso.
data ParamsDirector = ParamsDirector
  { pdEspaciado       :: Int
  , pdProbBase        :: Fijo
  , pdTension         :: Fijo
  , pdProbMax         :: Fijo
  , pdVentanaVariedad :: Int
  , pdPenalVariedad   :: Fijo
  , pdBonoNovedad     :: Fijo
  , pdDiasDecada      :: Int
  } deriving (Eq, Show)

-- | V5: al menos 60 días entre eventos.
paramsPorOmision :: ParamsDirector
paramsPorOmision = ParamsDirector 60 (Fijo 100) (Fijo 20) (Fijo 2000) 4 uno uno 3650

data Guion = Guion
  { guTipos       :: [Text]
  , guFases       :: [Fase]
  , guSituaciones :: [Situacion]
  , guDirector    :: ParamsDirector
  } deriving (Eq, Show)

guionVacio :: Guion
guionVacio = Guion [] [] [] paramsPorOmision

-- | Lo inmutable de la partida (documento funcional, sección 1): no cambia
-- durante la partida y no se guarda con el estado.
data Entorno = Entorno
  { entMapa     :: Mapa
  , entGuion    :: Guion
  , entEconomia :: Economia   -- ^ bienes que pueden ser moneda (Motor.Moneda)
  }

entornoSimple :: Mapa -> Entorno
entornoSimple m = Entorno m guionVacio economiaVacia

-- ---------------------------------------------------------------------------
-- Carga
-- ---------------------------------------------------------------------------

-- | Carga un guion desde JSON. Las fechas se convierten a ticks con la fecha
-- juliana del tick 0. Acumula todos los errores: tipos fuera del vocabulario,
-- fases o sistemas desconocidos, situaciones sin opciones, efectos mal
-- escritos (que se compilan aquí, no a mitad de la partida).
cargarGuion :: Text -> Fecha -> Value -> Validacion Guion
cargarGuion archivo inicio v = case A.parseEither leer v of
  Left err -> falla (ErrorCarga ErrorEstructura archivo "" (T.pack err))
  Right (tipos, fases, sits, params) -> do
    let idsFases = map faId fases
    sits' <- traverse (validarSituacion tipos idsFases) sits
    _ <- traverse (\i -> if length (filter (== i) idsFases) > 1
                           then falla (ErrorCarga ErrorEsquema archivo ("fases." <> i) "fase repetida")
                           else pure ()) (nub idsFases)
    pure (Guion tipos fases sits' params)
  where
    leer = A.withObject "guion" $ \o -> do
      tipos <- o A..: "tipos"
      fases <- maybe (pure []) (mapM fase) =<< o A..:? "fases"
      sits <- maybe (pure []) (mapM situacion) =<< o A..:? "situaciones"
      params <- maybe (pure paramsPorOmision) director =<< o A..:? "director"
      pure (tipos, fases, sits, params)

    fase = A.withObject "fase" $ \o -> do
      fid <- o A..: "id"
      desdeFecha <- o A..:? "desde_fecha"
      desde <- traverse fechaATick desdeFecha
      cond <- traverse condicion =<< o A..:? "condicion"
      sistemas <- o A..:? "sistemas"
      ints <- maybe (pure Map.empty) (fmap Map.fromList . mapM (\(k, x) -> (,) k <$> A.parseJSON x) . Map.toList)
                =<< (o A..:? "intensidades" :: A.Parser (Maybe (Map Text Value)))
      pure (Fase fid desde cond sistemas ints)

    fechaATick t = case map (reads . T.unpack) (T.splitOn "-" t) of
      [[(y, "")], [(m, "")], [(d, "")]] ->
        pure (fromIntegral (diaJuliano (Fecha y m d) - diaJuliano inicio))
      _ -> fail ("fecha inválida (se espera AAAA-MM-DD): " <> T.unpack t)

    situacion = A.withObject "situacion" $ \o -> do
      sid <- o A..: "id"
      tipo <- o A..: "tipo"
      peso <- maybe (pure uno) pure =<< o A..:? "peso"
      enfr <- maybe (pure 365) pure =<< o A..:? "enfriamiento"
      plazo <- maybe (pure 40) pure =<< o A..:? "plazo"
      fases <- maybe (pure []) pure =<< o A..:? "fases"
      cond <- maybe (pure Siempre) condicion =<< o A..:? "condicion"
      opciones <- o A..: "opciones" >>= mapM (A.withObject "opcion" $ \op -> (,) <$> op A..: "id" <*> op A..: "efectos")
      pure (sid, tipo, peso, enfr, plazo, fases, cond, opciones :: [(Text, [Value])])

    condicion = A.withObject "condicion" $ \o -> do
      t <- o A..: "tipo" :: A.Parser Text
      case t of
        "siempre" -> pure Siempre
        "mayor"   -> Mayor <$> o A..: "entidad" <*> (Magnitud <$> o A..: "magnitud") <*> o A..: "valor"
        "menor"   -> Menor <$> o A..: "entidad" <*> (Magnitud <$> o A..: "magnitud") <*> o A..: "valor"
        "desde_fecha" -> DesdeTick <$> (o A..: "fecha" >>= fechaATick)
        "todas"   -> Todas <$> (o A..: "de" >>= mapM condicion)
        "alguna"  -> Alguna <$> (o A..: "de" >>= mapM condicion)
        "no"      -> No <$> (o A..: "de" >>= condicion)
        _         -> fail ("condición desconocida: " <> T.unpack t)

    director = A.withObject "director" $ \o -> do
      let d = paramsPorOmision
          campo :: A.FromJSON a => A.Key -> a -> A.Parser a
          campo k x = maybe x id <$> o A..:? k
      ParamsDirector
        <$> campo "espaciado" (pdEspaciado d)
        <*> campo "prob_base" (pdProbBase d)
        <*> campo "tension" (pdTension d)
        <*> campo "prob_max" (pdProbMax d)
        <*> campo "ventana_variedad" (pdVentanaVariedad d)
        <*> campo "penal_variedad" (pdPenalVariedad d)
        <*> campo "bono_novedad" (pdBonoNovedad d)
        <*> campo "dias_decada" (pdDiasDecada d)

    -- Aplicativo y no monádico: así se acumulan todos los errores de una
    -- situación (tipo, fases, opciones, efectos) en vez de parar en el primero.
    validarSituacion tipos idsFases (sid, tipo, peso, enfr, plazo, fases, cond, opciones) =
      let ruta = "situaciones." <> sid
          tipoOk = if tipo `elem` tipos then pure ()
                   else falla (ErrorCarga ErrorReferencia archivo ruta
                                ("tipo «" <> tipo <> "» fuera del vocabulario: " <> T.intercalate ", " tipos))
          fasesOk = traverse (\f -> if f `elem` idsFases then pure ()
                                     else falla (ErrorCarga ErrorReferencia archivo ruta ("fase desconocida: " <> f))) fases
          opcionesOk = if null opciones then falla (ErrorCarga ErrorEsquema archivo ruta "sin opciones") else pure ()
          progs = traverse (\(oid, efs) -> case compilarPrograma efs of
                               Left err -> falla (ErrorCarga ErrorEsquema archivo (ruta <> ".opciones." <> oid) err)
                               Right p  -> pure (oid, p)) opciones
      in (\_ _ _ ps -> Situacion sid tipo peso enfr plazo fases cond ps) <$> tipoOk <*> fasesOk <*> opcionesOk <*> progs
