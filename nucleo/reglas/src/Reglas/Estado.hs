{-# LANGUAGE StrictData, OverloadedStrings, TypeFamilies #-}
module Reglas.Estado where

import Data.Map.Strict (Map)
import Data.Text (Text)
import Data.Aeson (ToJSON, FromJSON)
import GHC.Generics (Generic)

import Motor.Base
import Motor.Estado
import Reglas.Base

data Purepecha = Purepecha
  { ppAltepetl    :: Map AltId Altepetl
  , ppPops        :: Map PopId Pop
  , ppPersonajes  :: Map PerId Personaje
  , ppFaccion     :: Faccion
  , ppTasas       :: Tasas
  , ppPresupuesto :: Presupuesto
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

data Altepetl = Altepetl
  { altId         :: AltId
  , altNombre     :: Text
  , altGobernador :: Maybe PerId
  , altDistancia  :: Fijo
  , altSujetoA    :: Maybe AltId
  , altLealtad    :: Fijo
  , altCelda      :: Int          -- ^ celda del mapa donde está la cabecera
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

data Pop = Pop
  { popId        :: PopId
  , popAltepetl  :: AltId
  , popIdentidad :: Text
  , popEstrato   :: Text
  , popTamano    :: Int
  , popLealtad   :: Fijo
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

data Personaje = Personaje
  { perId     :: PerId
  , perNombre :: Text
  , perAdmin  :: Int
  , perMando  :: Int
  , perEdad   :: Int
  , perVivo   :: Bool
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

data Faccion = Faccion
  { facTesoro      :: Fijo
  , facPrestigio   :: Int
  , facLegitimidad :: Int
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

data Tasas = Tasas
  { tasaTributo  :: Int
  , tasaImpuesto :: Int
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

data PartePresupuesto
  = PEjercito | PAdministracion | PObras | PDiplomacia | PCulto
  deriving (Eq, Show, Generic, ToJSON, FromJSON)

data Presupuesto = Presupuesto
  { pbEjercito       :: Int
  , pbAdministracion :: Int
  , pbObras          :: Int
  , pbDiplomacia     :: Int
  , pbCulto          :: Int
  } deriving (Eq, Show, Generic, ToJSON, FromJSON)

type instance DerivadoDe Purepecha = ()
type instance PlanDe     Purepecha = ()
