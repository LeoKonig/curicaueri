{-# LANGUAGE StrictData #-}
module Motor.Hechos where

import Data.Map.Strict (Map)
import Data.Text (Text)
import Motor.Base

data Hecho = Hecho
  { hechoTipo      :: Text
  , hechoTick      :: Tick
  , hechoEntidades :: [EntRef]
  , hechoParams    :: Map Text Text
  } deriving (Eq, Show)
