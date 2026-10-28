{-# LANGUAGE OverloadedStrings #-}
-- | Agentes externos: otro programa que decide por una facción.
--
-- La cáscara lanza el programa, le escribe un `agente_turno` por su entrada
-- estándar al empezar cada periodo y lee un `agente_plan` de su salida, con
-- un tiempo límite. Todo lo imperativo vive aquí; el motor sigue siendo puro:
-- los comandos del agente entran a `paso` como datos, por la misma cola que
-- los del jugador.
--
-- Garantías (documento funcional, sección 14):
--
-- * Un agente que tarda más que el límite queda fuera de la partida y su
--   facción sigue con el agente nulo. No se le vuelve a preguntar: una
--   respuesta tardía llegaría desfasada y desordenaría las siguientes.
-- * Una respuesta que no es un plan válido, o que es de otro tick, se
--   descarta y se anota; el agente sigue en la partida.
-- * Cada respuesta (o su ausencia) se anota en el registro. Con el registro,
--   la partida se repite exactamente sin el programa externo.
module Agente
  ( FuenteAgente
  , RespuestaAgente (..)
  , lanzarAgente
  , reproducirAgente
  , pedirPlan
  , lineaDeRegistro
  , cerrarAgente
  ) where

import Control.Exception (IOException, try)
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import Data.IORef
import Data.Int (Int64)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import System.IO
import System.Process
import System.Timeout (timeout)

import Motor.Protocolo (PlanAgente (..))

data RespuestaAgente = RespuestaAgente
  { rPlan   :: Maybe PlanAgente
  , rMotivo :: Maybe Text          -- ^ por qué no hubo plan, si no lo hubo
  } deriving (Eq, Show)

data FuenteAgente
  = Proceso Handle Handle ProcessHandle Int (IORef Bool)   -- ^ entrada, salida, proceso, espera en ms, ¿sigue vivo?
  | Reproduccion (Map.Map Int64 RespuestaAgente)

-- | Lanza el programa del agente. El comando se parte por espacios:
-- @"python3 agentes/python/agente.py"@.
lanzarAgente :: String -> Int -> IO FuenteAgente
lanzarAgente comando esperaMs = case words comando of
  [] -> fail "comando de agente vacío"
  (prog : args) -> do
    (Just ent, Just sal, _, ph) <- createProcess (proc prog args)
      { std_in = CreatePipe, std_out = CreatePipe, std_err = Inherit }
    mapM_ (`hSetBinaryMode` True) [ent, sal]
    hSetBuffering ent LineBuffering
    vivo <- newIORef True
    pure (Proceso ent sal ph esperaMs vivo)

-- | Una fuente que responde con lo anotado en un registro, sin programa.
reproducirAgente :: FilePath -> IO FuenteAgente
reproducirAgente ruta = do
  lineas <- BC.lines <$> BC.readFile ruta
  entradas <- mapM leer (filter (not . BC.null) lineas)
  pure (Reproduccion (Map.fromList entradas))
  where
    leer l = case A.decodeStrict l >>= A.parseMaybe entrada of
      Just e  -> pure e
      Nothing -> fail ("línea de registro ilegible: " <> BC.unpack l)
    entrada = A.withObject "registro" $ \o -> do
      t <- o A..: "tick"
      plan <- o A..:? "plan"
      motivo <- o A..:? "motivo"
      pure (t, RespuestaAgente plan motivo)

-- | Pide el plan del tick @t@, mandando el turno ya codificado.
pedirPlan :: FuenteAgente -> Int64 -> A.Value -> IO RespuestaAgente
pedirPlan (Reproduccion m) t _ =
  pure (Map.findWithDefault (RespuestaAgente Nothing (Just "sin registro para este tick")) t m)
pedirPlan (Proceso ent sal _ espera vivo) t turno = do
  activo <- readIORef vivo
  if not activo then pure (RespuestaAgente Nothing (Just "agente fuera de la partida")) else do
    escrito <- try (BL.hPut ent (A.encode turno <> "\n") >> hFlush ent) :: IO (Either IOException ())
    case escrito of
      Left e -> caido ("no se pudo escribir al agente: " <> T.pack (show e))
      Right () -> do
        r <- try (timeout (espera * 1000) (BC.hGetLine sal)) :: IO (Either IOException (Maybe BC.ByteString))
        case r of
          Left e -> caido ("el agente cerró su salida: " <> T.pack (show e))
          Right Nothing -> caido ("tiempo agotado (" <> T.pack (show espera) <> " ms); el agente queda fuera de la partida")
          Right (Just linea) -> pure $ case A.eitherDecodeStrict linea of
            Left err -> RespuestaAgente Nothing (Just ("respuesta inválida: " <> T.pack err))
            Right plan
              | paTick plan /= t -> RespuestaAgente Nothing (Just ("plan del tick " <> T.pack (show (paTick plan)) <> ", se esperaba el " <> T.pack (show t)))
              | otherwise -> RespuestaAgente (Just plan) Nothing
  where
    caido motivo = writeIORef vivo False >> pure (RespuestaAgente Nothing (Just motivo))

-- | Una línea del registro de respuestas (JSON Lines).
lineaDeRegistro :: Int64 -> Int -> RespuestaAgente -> BL.ByteString
lineaDeRegistro t faccion r = A.encode (A.object
  [ "tick" A..= t, "faccion" A..= faccion, "plan" A..= rPlan r, "motivo" A..= rMotivo r ]) <> "\n"

-- | Termina el programa del agente al salir, para no dejar procesos sueltos.
cerrarAgente :: FuenteAgente -> IO ()
cerrarAgente (Reproduccion _) = pure ()
cerrarAgente (Proceso ent _ ph _ _) = do
  _ <- try (hClose ent) :: IO (Either IOException ())
  terminateProcess ph
