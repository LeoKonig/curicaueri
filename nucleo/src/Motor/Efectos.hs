{-# LANGUAGE StrictData, OverloadedStrings, LambdaCase #-}
module Motor.Efectos where

import Data.Aeson (Value, withObject, (.:))
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import qualified Data.Map.Strict as Map
import Data.Text (Text)

import Motor.Base
import Motor.Estado
import Motor.Hechos
import Motor.Magnitudes

-- ---------------------------------------------------------------------------
-- Efectos builtin. Los efectos propios del juego se añaden en 1b como
--   EExt Text Value
-- con un handler en Juego, sin cambiar la firma de `interpretar`.
-- ---------------------------------------------------------------------------

data Efecto
  = ESumarMag     EntRef Magnitud Fijo
  | EFijarMag     EntRef Magnitud Fijo
  | ESumarMagVar  EntRef Magnitud Text
  | ERestarMagVar EntRef Magnitud Text
  | EHecho        Text
  | EElegirCantidad Text Int Int
  | EElegirOpcion   Text [Text]
  deriving (Show, Eq)

-- | Una opción de evento ya compilada. El intérprete nunca parsea JSON.
newtype Programa = Programa [Efecto]
  deriving (Show, Eq)

-- | Se llama al cargar los datos, nunca durante la partida.
compilarPrograma :: [Value] -> Either Text Programa
compilarPrograma = fmap Programa . traverse parsearEfecto

data Resultado s
  = Completado (Contexto, Estado s, [Hecho])
  | Suspendido Pregunta Reanudacion (Estado s, [Hecho])
  | Fallo Text

-- ---------------------------------------------------------------------------
-- Parser
-- ---------------------------------------------------------------------------

parsearEntRef :: Value -> Maybe EntRef
parsearEntRef = A.parseMaybe A.parseJSON

parsearEfecto :: Value -> Either Text Efecto
parsearEfecto v = do
  tag <- maybe (Left "efecto sin campo tipo") Right
           (A.parseMaybe (withObject "e" (.: "tipo")) v)
  case tag :: Text of
    "hecho" ->
      maybe (Left "hecho inválido") (Right . EHecho)
        (A.parseMaybe (withObject "h" (.: "tag")) v)
    "sumar_mag" -> do
      (e, m, val) <- triple
      Right (ESumarMag e m val)
    "fijar_mag" -> do
      (e, m, val) <- triple
      Right (EFijarMag e m val)
    "sumar_mag_var" -> do
      (e, m, var) <- tripleVar
      Right (ESumarMagVar e m var)
    "restar_mag_var" -> do
      (e, m, var) <- tripleVar
      Right (ERestarMagVar e m var)
    "elegir_cantidad" -> do
      (var, lo, hi) <- cantidad
      Right (EElegirCantidad var lo hi)
    "elegir_opcion" -> do
      (var, opts) <- opcion
      Right (EElegirOpcion var opts)
    other -> Left ("efecto no implementado: " <> other)
  where
    triple :: Either Text (EntRef, Magnitud, Fijo)
    triple = case A.parseMaybe (withObject "t" $ \o ->
               (,,) <$> o .: "entidad" <*> o .: "magnitud" <*> o .: "valor") v of
      Just x  -> Right x
      Nothing -> Left "sumar_mag/fijar_mag inválido"
    tripleVar :: Either Text (EntRef, Magnitud, Text)
    tripleVar = case A.parseMaybe (withObject "t" $ \o ->
                  (,,) <$> o .: "entidad" <*> o .: "magnitud" <*> o .: "var") v of
      Just x  -> Right x
      Nothing -> Left "*_mag_var inválido"
    cantidad = case A.parseMaybe (withObject "c" $ \o ->
                 (,,) <$> o .: "variable" <*> o .: "min" <*> o .: "max") v of
      Just x  -> Right x
      Nothing -> Left "elegir_cantidad inválido"
    opcion = case A.parseMaybe (withObject "c" $ \o ->
               (,) <$> o .: "variable" <*> o .: "opciones") v of
      Just x  -> Right x
      Nothing -> Left "elegir_opcion inválido"

-- ---------------------------------------------------------------------------
-- Intérprete
-- ---------------------------------------------------------------------------

interpretar :: Text -> Text -> Programa -> Int -> Contexto -> Estado s -> Resultado s
interpretar evento opcion prog@(Programa efectos) i ctx est
  | i >= length efectos = Completado (ctx, est, [])
  | otherwise = paso (efectos !! i)

  where
    paso ef = case ef of
      EHecho tag ->
        seguir [Hecho tag (estadoTick est) [] Map.empty] ctx est

      ESumarMag e m v  -> seguir [] ctx (escribirBase (sumarBase e m v) est)
      EFijarMag e m v  -> seguir [] ctx (escribirBase (fijarBase e m v) est)

      ESumarMagVar e m var -> case Map.lookup var ctx of
        Just (CEntero n)   -> seguir [] ctx (escribirBase (sumarBase e m (desdeEntero n)) est)
        Just (CCantidad f) -> seguir [] ctx (escribirBase (sumarBase e m f) est)
        _ -> Fallo ("variable no encontrada: " <> var)

      ERestarMagVar e m var -> case Map.lookup var ctx of
        Just (CEntero n)   -> seguir [] ctx (escribirBase (sumarBase e m (negF (desdeEntero n))) est)
        Just (CCantidad f) -> seguir [] ctx (escribirBase (sumarBase e m (negF f)) est)
        _ -> Fallo ("variable no encontrada: " <> var)

      EElegirCantidad var lo hi ->
        Suspendido (PreguntaCantidad var lo hi)
                   (Reanudacion evento opcion (i + 1) ctx)
                   (est, [])

      EElegirOpcion var opts ->
        Suspendido (PreguntaOpcion var opts)
                   (Reanudacion evento opcion (i + 1) ctx)
                   (est, [])

    seguir hs ctx' est' = case interpretar evento opcion prog (i + 1) ctx' est' of
      Completado (c, e, h)    -> Completado (c, e, hs ++ h)
      Suspendido p rn (e, h)  -> Suspendido p rn (e, hs ++ h)
      Fallo msg               -> Fallo msg

-- | Aplica un efecto de escritura al almacén de magnitudes del estado.
escribirBase :: (Almacen -> Almacen) -> Estado s -> Estado s
escribirBase f est =
  let com  = persistenteComun (estadoPersistente est)
      com' = com { comunMagnitudes = f (comunMagnitudes com) }
  in est { estadoPersistente = (estadoPersistente est)
             { persistenteComun = com' } }

-- ---------------------------------------------------------------------------
-- Reanudar y almacenar la decisión pendiente
-- ---------------------------------------------------------------------------

reanudar :: ValorCtx -> DecisionPendiente -> Programa -> Estado s -> Resultado s
reanudar valor dp prog est =
  let Reanudacion ev op idx ctx = dpReanudacion dp
      var  = preVariable (dpPregunta dp)
      ctx' = Map.insert var valor ctx
  in interpretar ev op prog idx ctx' est

-- | Resultado → estado, sin tocar el estado externo salvo para apuntar la
-- decisión pendiente. El estado de un `Completado` ya incluye los efectos;
-- devolverlo tal cual es lo correcto.
aplicarResultado :: Int -> Resultado s -> Estado s -> Estado s
aplicarResultado _ (Completado (_, e, _)) _ = e
aplicarResultado _ (Fallo _) est            = est
aplicarResultado i (Suspendido p rn (e, _)) _ =
  let com = persistenteComun (estadoPersistente e)
      dp  = DecisionPendiente i p rn
      dir = comunDirector com
      com' = com { comunDecisiones = Map.insert i dp (comunDecisiones com)
                 , comunDirector = dir { edProximaDecision = max (edProximaDecision dir) (i + 1) } }
  in e { estadoPersistente = (estadoPersistente e)
           { persistenteComun = com' } }

-- | Elimina una decisión pendiente por id. Lo hace el shell al reanudar.
quitarDecision :: Int -> Estado s -> Estado s
quitarDecision i est =
  let com = persistenteComun (estadoPersistente est)
      com' = com { comunDecisiones = Map.delete i (comunDecisiones com) }
  in est { estadoPersistente = (estadoPersistente est)
             { persistenteComun = com' } }

-- | Id libre para una nueva decisión. En el prototipo hay una sola
-- pendiente a la vez; esta función no necesita ser robusta.
-- | Id para una decisión nueva. Nunca se reutiliza un id, aunque la decisión
-- anterior ya se haya resuelto: una respuesta tardía a una decisión vieja no
-- debe poder contestar una nueva que heredó su número.
siguienteId :: Estado s -> Int
siguienteId est =
  let com = persistenteComun (estadoPersistente est)
      maxPendiente = maybe 0 fst (Map.lookupMax (comunDecisiones com))
  in max (edProximaDecision (comunDirector com)) (maxPendiente + 1)
