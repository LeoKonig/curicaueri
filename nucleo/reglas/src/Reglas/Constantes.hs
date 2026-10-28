{-# LANGUAGE StrictData, OverloadedStrings #-}
module Reglas.Constantes where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)

import Motor.Base
import Reglas.Base

data Constantes = Constantes
  { cIngresoPorPop         :: Fijo   -- por pop y veintena, a tasa neutra
  , cAgravioSubirImpuesto  :: Fijo
  , cAgravioBajarImpuesto  :: Fijo
  , cAgravioSubirTributo   :: Fijo
  , cAgravioBajarTributo   :: Fijo
  , cMantenimientoEjercito :: Fijo   -- por punto de presupuesto
  , cMantenimientoAdmin    :: Fijo
  , cNeutralTasa           :: Int
  } deriving (Eq, Show)

constantesDefault :: Constantes
constantesDefault = Constantes
  { cIngresoPorPop         = fiD 1    -- 0.1
  , cAgravioSubirImpuesto  = fi 2     -- 2.0
  , cAgravioBajarImpuesto  = fi 2
  , cAgravioSubirTributo   = fi 1
  , cAgravioBajarTributo   = fi 1
  , cMantenimientoEjercito = fiD 1    -- 0.1
  , cMantenimientoAdmin    = fiD 1
  , cNeutralTasa           = 3
  }

-- | Fórmulas con nombre. Los datos podrán elegir cuál usar y con qué
-- parámetros; en 1b se llaman directamente desde los sistemas.
type FormulaAgravio = Int -> Fijo

formulasAgravio :: Constantes -> Map Text FormulaAgravio
formulasAgravio c = Map.fromList
  [ ("agravio_por_impuesto", fnImpuesto c)
  , ("agravio_por_tributo",  fnTributo c)
  ]
  where
    fnImpuesto cc d
      | d > 0     = cAgravioSubirImpuesto cc .*. fi d .+. fi (d * d)
      | d < 0     = cAgravioBajarImpuesto cc .*. fi d
      | otherwise = Fijo 0
    fnTributo cc d
      | d > 0     = cAgravioSubirTributo cc .*. fi d .+. fi (d * d)
      | d < 0     = cAgravioBajarTributo cc .*. fi d
      | otherwise = Fijo 0
