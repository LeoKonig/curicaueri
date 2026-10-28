{-# LANGUAGE StrictData, OverloadedStrings, LambdaCase #-}
-- | El protocolo entre el núcleo y el cliente: el único contrato entre los dos.
--
-- Una línea de JSON por mensaje, con el campo @"tipo"@ que dice qué mensaje es.
-- Los nombres de los campos están escritos a mano, no derivados de los nombres
-- de Haskell: renombrar un campo aquí no debe romper el cliente sin que una
-- prueba lo note. Cada mensaje tiene su archivo dorado en
-- @pruebas_compartidas/protocolo/@, que leen las pruebas de los dos lados.
--
-- Reglas de compatibilidad (V5, *Versión del protocolo*):
--
-- * cambio aditivo (un mensaje nuevo, un campo opcional nuevo, un tipo de hecho
--   nuevo que el cliente puede ignorar): la versión no sube;
-- * cambio que rompe (quitar o renombrar un campo, cambiar su tipo o su
--   significado): la versión sube y versiones distintas se rechazan.
module Motor.Protocolo
  ( versionProtocolo
    -- * Mensajes
  , MensajeNucleo (..)
  , MensajeCliente (..)
  , Control (..)
    -- * Contenido
  , Reloj (..)
  , CatalogoCliente (..)
  , DeclMagnitud (..)
  , DeclComando (..)
  , DeclParametro (..)
  , TipoParametro (..)
  , MapaCliente (..)
    -- * Construcción
  , relojDe
  , declMagnitudes
  , mapaCliente
    -- * Agentes externos
  , versionAgente
  , turnoAgente
  , PlanAgente (..)
  , semillaAgente
    -- * Línea
  , aLinea
  , deLinea
  , verificarVersion
  ) where

import Motor.Autoridad (Eje, Requisito)
import Data.Aeson (FromJSON (..), ToJSON (..), Value, object, withObject, (.:), (.=))
import qualified Data.Aeson as A
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Types as A
import qualified Data.ByteString.Lazy as BL
import qualified Data.IntMap.Strict as IntMap
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Data.Int (Int64)
import qualified Data.Text as T

import Motor.Base
import Motor.Calendario
import Motor.Hechos
import Motor.Magnitudes
import Motor.Mapa
import Motor.Vista
import Motor.Estado (Pregunta (..))
import Motor.Proyeccion (Diferencia (..))

versionProtocolo :: Int
versionProtocolo = 2   -- 2: reloj y catálogo con calendario genérico (periodos)

-- ---------------------------------------------------------------------------
-- Mensajes
-- ---------------------------------------------------------------------------

-- | Del núcleo al cliente.
data MensajeNucleo
  = NHola Int
  | NCatalogo CatalogoCliente
  | NMapa MapaCliente
  | NInstantanea Reloj Vista
  | NCambios Reloj Cambios [Hecho]
  | NReloj Reloj                        -- ^ tras una pausa o un cambio de velocidad
  | NError (Maybe Int) Text             -- ^ secuencia del comando, si la hay, y motivo
  | NPrediccion Int Tick [Diferencia]   -- ^ secuencia de la consulta, horizonte y diferencias
  | NAviso Text                         -- ^ información para el jugador (partida guardada…)
  | NDecision Int Text Text Pregunta (Maybe Tick)  -- ^ id, situación, tipo, pregunta y plazo
  | NDecisionCerrada Int                -- ^ ya no espera respuesta (respondida o vencida)
  deriving (Eq, Show)

-- | Del cliente al núcleo. El comando viaja como JSON opaco: lo decodifica el
-- juego, porque el motor no conoce sus tipos.
data MensajeCliente
  = CHola Int
  | CComando Int Value                  -- ^ secuencia y comando del juego
  | CConsulta Int Value                 -- ^ como un comando, pero solo pide la predicción
  | CResponder Int Int Text             -- ^ secuencia, decisión y respuesta (opción o cantidad)
  | CControl Control
  deriving (Eq, Show)

-- | No entra al registro de comandos: cambia cuándo corre el siguiente tick,
-- no lo que pasa en él.
data Control = Pausa Bool | Velocidad Int | Guardar Text | Cargar Text
  deriving (Eq, Show)

-- ---------------------------------------------------------------------------
-- Contenido
-- ---------------------------------------------------------------------------

-- | Lo que necesita la barra superior: fecha europea, veintena y velocidad.
data Reloj = Reloj
  { rTick      :: Tick
  , rFecha     :: Fecha
  , rCalendarioVisible :: Text      -- ^ "juliano" o "gregoriano"
  , rPeriodo   :: InfoPeriodo
  , rVelocidad :: Int
  , rPausado   :: Bool
  } deriving (Eq, Show)

data CatalogoCliente = CatalogoCliente
  { ccMagnitudes :: [DeclMagnitud]
  , ccComandos   :: [DeclComando]
  , ccVelocidades :: [Int]              -- ^ milisegundos por día, de la velocidad 1 a la 5
  , ccCalendario :: CalendarioInterno   -- ^ para que el cliente nombre los periodos
  , ccEjes       :: [Eje]               -- ^ ejes de poder activos en el escenario (puede ser vacío)
  } deriving (Eq, Show)

data DeclMagnitud = DeclMagnitud
  { dmcId :: Text, dmcClave :: Text, dmcFormato :: Maybe Text, dmcMin :: Fijo, dmcMax :: Fijo }
  deriving (Eq, Show)

-- | Un comando declarado. El cliente arma el formulario a partir de esto, sin
-- código propio por comando.
data DeclComando = DeclComando
  { dcTipo        :: Text
  , dcClave       :: Text
  , dcParametros  :: [DeclParametro]
  , dcImplementado :: Bool
  , dcRequiere    :: Requisito          -- ^ eje y clase de autoridad (V5, *Permiso y capacidad*)
  } deriving (Eq, Show)

data DeclParametro = DeclParametro { dpNombre :: Text, dpTipo :: TipoParametro }
  deriving (Eq, Show)

data TipoParametro = PEntero Int Int | POpcion [Text]
  deriving (Eq, Show)

-- | El mapa como lo necesita el cliente para dibujarlo. El núcleo da el grafo
-- y los terrenos; la geometría es del cliente (V5, *El mapa como grafo*).
data MapaCliente = MapaCliente
  { mcProveedor :: Text
  , mcAncho     :: Int
  , mcAlto      :: Int
  , mcCeldas    :: [(Int, Text)]        -- ^ id y terreno
  } deriving (Eq, Show)

-- | El reloj de un tick: fecha visible desde la fecha del tick 0 y periodo
-- según el calendario interno del escenario.
relojDe :: CalendarioVisible -> Fecha -> CalendarioInterno -> Int -> Bool -> Tick -> Reloj
relojDe visible inicio cal velocidad pausado t =
  let (f, nombre) = fechaVisible visible inicio t
  in Reloj t f nombre (infoPeriodo cal t) velocidad pausado

declMagnitudes :: Map Magnitud DefMagnitud -> [DeclMagnitud]
declMagnitudes cat =
  [ DeclMagnitud (dmId d) (dmClave d) (dmFormato d) (minMag (dmRango d)) (maxMag (dmRango d))
  | d <- Map.elems cat ]

mapaCliente :: Int -> Int -> Mapa -> MapaCliente
mapaCliente ancho alto m =
  MapaCliente "hexagonal" ancho alto
    [ (i, t) | (i, c) <- IntMap.toList (mapaCeldas m), let Terreno t = celdaTerreno c ]

-- ---------------------------------------------------------------------------
-- Codificación
-- ---------------------------------------------------------------------------

tipo :: Text -> A.Pair
tipo t = "tipo" .= t

instance ToJSON MensajeNucleo where
  toJSON = \case
    NHola v -> object [tipo "hola", "version" .= v]
    NCatalogo c -> object [ tipo "catalogo"
                          , "magnitudes" .= ccMagnitudes c
                          , "comandos"   .= ccComandos c
                          , "velocidades" .= ccVelocidades c
                          , "calendario" .= ccCalendario c
                          , "ejes" .= ccEjes c ]
    NMapa m -> object [ tipo "mapa"
                      , "proveedor" .= mcProveedor m
                      , "ancho" .= mcAncho m, "alto" .= mcAlto m
                      , "celdas" .= [ object ["id" .= i, "terreno" .= t] | (i, t) <- mcCeldas m ] ]
    NInstantanea r v -> object [ tipo "instantanea"
                               , "reloj" .= r
                               , "entidades" .= map entidadJ (Map.elems (vEntidades v)) ]
    NCambios r c hs -> object [ tipo "cambios"
                              , "reloj" .= r
                              , "actualizadas" .= map entidadJ (cActualizadas c)
                              , "eliminadas" .= cEliminadas c
                              , "hechos" .= map hechoJ hs ]
    NReloj r -> object [tipo "reloj", "reloj" .= r]
    NError s m -> object [tipo "error", "secuencia" .= s, "motivo" .= m]
    NPrediccion s h ds -> object [ tipo "prediccion", "secuencia" .= s, "horizonte" .= tickJ h
                                 , "diferencias" .= map diferenciaJ ds ]
    NAviso t -> object [tipo "aviso", "texto" .= t]
    NDecision i sit tp preg plazo -> object
      [ tipo "decision", "id" .= i, "situacion" .= sit, "tipo_situacion" .= tp
      , "pregunta" .= preguntaJ preg, "plazo" .= fmap tickJ plazo ]
    NDecisionCerrada i -> object [tipo "decision_cerrada", "id" .= i]

instance FromJSON MensajeCliente where
  parseJSON = withObject "mensaje" $ \o -> do
    t <- o .: "tipo" :: A.Parser Text
    case t of
      "hola"    -> CHola <$> o .: "version"
      "comando" -> CComando <$> o .: "secuencia" <*> o .: "comando"
      "consulta" -> CConsulta <$> o .: "secuencia" <*> o .: "comando"
      "responder" -> CResponder <$> o .: "secuencia" <*> o .: "decision" <*> o .: "respuesta"
      "control" -> do
        accion <- o .: "accion" :: A.Parser Text
        case accion of
          "pausa"     -> CControl . Pausa <$> o .: "valor"
          "velocidad" -> CControl . Velocidad <$> o .: "valor"
          "guardar"   -> CControl . Guardar <$> o .: "nombre"
          "cargar"    -> CControl . Cargar <$> o .: "nombre"
          _           -> fail ("control desconocido: " <> T.unpack accion)
      _ -> fail ("mensaje desconocido: " <> T.unpack t)

-- | Solo para las pruebas y para un cliente escrito en Haskell.
instance ToJSON MensajeCliente where
  toJSON = \case
    CHola v -> object [tipo "hola", "version" .= v]
    CComando s c -> object [tipo "comando", "secuencia" .= s, "comando" .= c]
    CConsulta s c -> object [tipo "consulta", "secuencia" .= s, "comando" .= c]
    CResponder s d r -> object [tipo "responder", "secuencia" .= s, "decision" .= d, "respuesta" .= r]
    CControl (Guardar n) -> object [tipo "control", "accion" .= ("guardar" :: Text), "nombre" .= n]
    CControl (Cargar n) -> object [tipo "control", "accion" .= ("cargar" :: Text), "nombre" .= n]
    CControl (Pausa b) -> object [tipo "control", "accion" .= ("pausa" :: Text), "valor" .= b]
    CControl (Velocidad n) -> object [tipo "control", "accion" .= ("velocidad" :: Text), "valor" .= n]

instance ToJSON Reloj where
  toJSON r = object
    [ "tick" .= tickJ (rTick r)
    , "fecha" .= object [ "anio" .= fAnio f, "mes" .= fMes f, "dia" .= fDia f
                        , "calendario" .= rCalendarioVisible r ]
    , "fuera_de_periodo" .= ipFuera iv
    , "periodo" .= ipPeriodo iv
    , "dia" .= ipDia iv
    , "dias_para_periodo" .= ipDiasParaSiguiente iv
    , "velocidad" .= rVelocidad r
    , "pausado" .= rPausado r ]
    where f = rFecha r; iv = rPeriodo r

instance ToJSON DeclMagnitud where
  toJSON d = object [ "id" .= dmcId d, "clave" .= dmcClave d, "formato" .= dmcFormato d
                    , "min" .= dmcMin d, "max" .= dmcMax d ]

instance ToJSON DeclComando where
  toJSON d = object [ "tipo" .= dcTipo d, "clave" .= dcClave d
                    , "parametros" .= dcParametros d, "implementado" .= dcImplementado d
                    , "requiere" .= dcRequiere d ]

instance ToJSON DeclParametro where
  toJSON p = case dpTipo p of
    PEntero lo hi -> object ["nombre" .= dpNombre p, "tipo" .= ("entero" :: Text), "min" .= lo, "max" .= hi]
    POpcion os    -> object ["nombre" .= dpNombre p, "tipo" .= ("opcion" :: Text), "opciones" .= os]

-- Vista -----------------------------------------------------------------------
--
-- Funciones y no instancias: la forma en que la vista viaja por el socket es
-- asunto del protocolo, no de los tipos (V5: toda la serialización vive en el
-- módulo del protocolo). Así el formato del guardado y el del cable pueden
-- evolucionar por separado.

tickJ :: Tick -> Value
tickJ (Tick t) = toJSON t

valorJ :: ValorVista -> Value
valorJ = \case
  VTexto t   -> object ["t" .= ("texto" :: Text), "v" .= t]
  VClave (ClaveLoc c) a -> object ["t" .= ("clave" :: Text), "c" .= c, "a" .= map valorJ a]
  VEntero n  -> object ["t" .= ("entero" :: Text), "v" .= n]
  VFijo f    -> object ["t" .= ("fijo" :: Text), "v" .= f]
  VBool b    -> object ["t" .= ("bool" :: Text), "v" .= b]
  VRef r     -> object ["t" .= ("ref" :: Text), "v" .= r]
  VLista xs  -> object ["t" .= ("lista" :: Text), "v" .= map valorJ xs]
  VNulo      -> object ["t" .= ("nulo" :: Text)]

aporteJ :: AporteVista -> Value
aporteJ a = object
  [ "fuente" .= (let ClaveLoc c = avFuente a in c), "args" .= map valorJ (avArgumentos a)
  , "sumando" .= sumando (avAporte a), "porcentaje" .= porcentaje (avAporte a)
  , "vence" .= fmap tickJ (avVence a) ]

magnitudJ :: MagnitudVista -> Value
magnitudJ m = object ["base" .= mvBase m, "efectivo" .= mvEfectivo m, "aportes" .= map aporteJ (mvAportes m)]

entidadJ :: EntidadVista -> Value
entidadJ e = object
  [ "ref" .= evRef e
  , "campos" .= objetoDe [ (k, valorJ v) | (k, v) <- Map.toList (evCampos e) ]
  , "magnitudes" .= objetoDe [ (n, magnitudJ v) | (Magnitud n, v) <- Map.toList (evMagnitudes e) ] ]

preguntaJ :: Pregunta -> Value
preguntaJ (PreguntaOpcion _ os) = object ["tipo" .= ("opcion" :: Text), "opciones" .= os]
preguntaJ (PreguntaCantidad _ lo hi) = object ["tipo" .= ("cantidad" :: Text), "min" .= lo, "max" .= hi]

diferenciaJ :: Diferencia -> Value
diferenciaJ d = object
  [ "ref" .= dRef d, "nombre" .= dNombre d
  , "clase" .= (if dEsMagnitud d then "magnitud" else "campo" :: Text)
  , "antes" .= fmap valorJ (dAntes d), "despues" .= fmap valorJ (dDespues d) ]

hechoJ :: Hecho -> Value
hechoJ h = object [ "tipo" .= hechoTipo h, "tick" .= tickJ (hechoTick h)
                  , "entidades" .= hechoEntidades h, "params" .= hechoParams h ]

objetoDe :: [(Text, Value)] -> Value
objetoDe kvs = A.Object (KM.fromList [ (K.fromText k, v) | (k, v) <- kvs ])

-- ---------------------------------------------------------------------------
-- Agentes externos (documento funcional, sección 14)
-- ---------------------------------------------------------------------------
--
-- Un agente externo es otro programa (en Mercury, en Python…) que habla con
-- la cáscara por su entrada y su salida estándar, una línea de JSON por
-- mensaje. Al empezar cada periodo, la cáscara le manda un `agente_turno` con
-- la vista de su facción y espera un `agente_plan` con comandos. Los comandos
-- entran por la misma cola que los del jugador y se validan igual.

versionAgente :: Int
versionAgente = 1

-- | Semilla del agente para un turno: depende de la semilla de la partida,
-- la facción y el tick, así que un agente determinista da la misma respuesta
-- al repetir la partida. Cabe en 31 bits para cualquier lenguaje.
semillaAgente :: Semilla -> FaccionId -> Tick -> Int
semillaAgente (Semilla s) (FaccionId f) (Tick t) =
  fromIntegral ((fromIntegral s * 1000003 + fromIntegral f * 7919 + t) `mod` 2147483647)

turnoAgente :: Semilla -> FaccionId -> Tick -> Reloj -> Vista -> Value
turnoAgente sem f@(FaccionId n) t r v = object
  [ tipo "agente_turno", "version" .= versionAgente
  , "faccion" .= n, "tick" .= tickJ t, "semilla" .= semillaAgente sem f t
  , "reloj" .= r
  , "entidades" .= map entidadJ (Map.elems (vEntidades v)) ]

-- | La respuesta del agente. Los comandos viajan como JSON opaco: los
-- decodifica el juego, igual que los del jugador.
data PlanAgente = PlanAgente
  { paTick     :: Int64
  , paComandos :: [Value]
  , paNota     :: Maybe Text      -- ^ por qué decidió eso, para el registro
  } deriving (Eq, Show)

instance FromJSON PlanAgente where
  parseJSON = withObject "agente_plan" $ \o -> do
    t <- o .: "tipo" :: A.Parser Text
    if t /= "agente_plan" then fail ("se esperaba agente_plan y llegó " <> T.unpack t) else
      PlanAgente <$> o .: "tick" <*> o .: "comandos" <*> o A..:? "nota"

instance ToJSON PlanAgente where
  toJSON p = object [tipo "agente_plan", "tick" .= paTick p, "comandos" .= paComandos p, "nota" .= paNota p]

-- ---------------------------------------------------------------------------
-- Línea
-- ---------------------------------------------------------------------------

-- | Un mensaje como una línea, sin el salto final (lo añade la cáscara).
aLinea :: ToJSON m => m -> BL.ByteString
aLinea = A.encode

deLinea :: FromJSON m => BL.ByteString -> Either Text m
deLinea bs = either (Left . T.pack) Right (A.eitherDecode bs)

verificarVersion :: Int -> Either Text ()
verificarVersion v
  | v == versionProtocolo = Right ()
  | otherwise = Left ("versión de protocolo incompatible: cliente " <> T.pack (show v)
                      <> ", núcleo " <> T.pack (show versionProtocolo))
