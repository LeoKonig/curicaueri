{-# LANGUAGE StrictData, TypeFamilies #-}
module Motor.Agentes where

import Data.Text (Text)
import qualified Data.Text as T
import Motor.Azar
import Motor.Juego (Agente(..))
import Motor.Estado (PlanDe)

-- | No hace nada. Sirve para comprobar que el motor llama a los agentes
-- en el paso 0 y que una partida avanza sin ellos.
agenteNulo :: PlanDe s -> Agente s c
agenteNulo plan = Agente
  { agPlanificar = \_ _ -> plan
  , agEjecutar   = \_ _ _ -> []
  }

-- | Emite entre 0 y @maxCmds@ comandos producidos por @gen@, uno por cada
-- generador derivado del principal. Nunca se usa en partidas reales; existe
-- para probar determinismo y que el motor valida lo que recibe.
agenteAleatorio :: PlanDe s -> Int -> (Rng -> c) -> Agente s c
agenteAleatorio plan maxCmds gen = Agente
  { agPlanificar = \_ _ -> plan
  , agEjecutar   = \_ _ r ->
      let (n, _) = uniformeEntero (maxCmds + 1) r
          rngs   = take n (drop 1 (rngStream r))
      in map gen rngs
  }

-- Silencia un warning de import por si Text no se usa en algunas builds.
_unusedText :: Text
_unusedText = T.pack ""
