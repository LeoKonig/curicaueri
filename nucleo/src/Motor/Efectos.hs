{-# LANGUAGE StrictData, OverloadedStrings, LambdaCase #-}
module Motor.Efectos where

import Data.Aeson (Value, withObject, (.:), (.:?))
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)

import Motor.Base
import Motor.Estado
import Motor.Hechos
import Motor.Magnitudes
import Motor.Propios

-- ---------------------------------------------------------------------------
-- Efectos del motor y efectos propios del juego. Un efecto propio queda como
-- su nombre y su objeto, ya validado al cargar ('EPropio'); el intérprete lo
-- aplica con el 'EfectoPropio' que registró el juego (Motor.Propios).
-- ---------------------------------------------------------------------------

data Efecto
  = ESumarMag     EntRef Magnitud Fijo
  | EFijarMag     EntRef Magnitud Fijo
  | ESumarMagVar  EntRef Magnitud Text
  | ERestarMagVar EntRef Magnitud Text
  | EHecho        Text
  | EElegirCantidad Text Int Int
  | EElegirOpcion   Text [Text]
  | EModificador  EntRef Magnitud Aporte Int
    -- ^ un modificador temporal sobre la magnitud: valor o porcentaje,
    --   durante tantos días; su fuente es la situación y la opción
  | EPropio       Text Value          -- ^ un efecto del juego: su nombre y sus argumentos validados
  deriving (Show, Eq)

-- | Una opción de evento ya compilada. El intérprete nunca parsea JSON.
newtype Programa = Programa [Efecto]
  deriving (Show, Eq)

-- | Se llama al cargar los datos, nunca durante la partida. El vocabulario
-- dice qué efectos propios tiene el juego y cómo se validan.
compilarPrograma :: Vocabulario -> [Value] -> Either Text Programa
compilarPrograma vo = fmap Programa . traverse (parsearEfecto vo)

data Resultado s
  = Completado (Contexto, Estado s, [Hecho])
  | Suspendido Pregunta Reanudacion (Estado s, [Hecho])
  | Fallo Text

-- ---------------------------------------------------------------------------
-- Parser
-- ---------------------------------------------------------------------------

parsearEntRef :: Value -> Maybe EntRef
parsearEntRef = A.parseMaybe A.parseJSON

parsearEfecto :: Vocabulario -> Value -> Either Text Efecto
parsearEfecto vo v = do
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
    "modificador" -> do
      (e, m, valor, pct, dias) <- maybe (Left "modificador inválido: pide entidad, magnitud, dias y valor o porcentaje") Right
        (A.parseMaybe (withObject "m" $ \o ->
           (,,,,) <$> o .: "entidad" <*> o .: "magnitud" <*> o .:? "valor" <*> o .:? "porcentaje" <*> o .: "dias") v)
      aporte <- case (valor, pct) of
        (Just x, Nothing) -> Right (Aporte x (Fijo 0))
        (Nothing, Just p) -> Right (Aporte (Fijo 0) p)
        _ -> Left "modificador: lleva «valor» o «porcentaje», uno de los dos"
      if dias <= 0 then Left "modificador: «dias» tiene que ser positivo"
                   else Right (EModificador e m aporte dias)
    other -> case Map.lookup other (voEfectos vo) of
      Just validar -> either (\m -> Left (other <> ": " <> m)) (const (Right (EPropio other v))) (validar v)
      Nothing -> Left ("efecto no implementado: " <> other)
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

interpretar :: Map Text (EfectoPropio s) -> Text -> Text -> Programa -> Int -> Contexto -> Estado s -> Resultado s
interpretar propios evento opcion prog@(Programa efectos) i ctx est
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

      EModificador e m aporte dias ->
        let Tick t = estadoTick est
            md = Modificador 0 m e aporte (Fuente "situacion" (evento <> "." <> opcion))
                   (Just (Tick t)) (Just (Tick (t + fromIntegral dias))) Nothing AlcancePropia []
        in seguir [] ctx (escribirBase (fst . agregarModificador md) est)

      EPropio nombre args -> case Map.lookup nombre propios of
        Nothing -> Fallo ("efecto propio desconocido: " <> nombre)
        Just ep -> case epAplicar ep args est of
          Left motivo     -> Fallo motivo
          Right (est', hs) -> seguir hs ctx est'

      EElegirOpcion var opts ->
        Suspendido (PreguntaOpcion var opts)
                   (Reanudacion evento opcion (i + 1) ctx)
                   (est, [])

    seguir hs ctx' est' = case interpretar propios evento opcion prog (i + 1) ctx' est' of
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

reanudar :: Map Text (EfectoPropio s) -> ValorCtx -> DecisionPendiente -> Programa -> Estado s -> Resultado s
reanudar propios valor dp prog est =
  let Reanudacion ev op idx ctx = dpReanudacion dp
      var  = preVariable (dpPregunta dp)
      ctx' = Map.insert var valor ctx
  in interpretar propios ev op prog idx ctx' est

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
