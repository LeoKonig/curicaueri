{-# LANGUAGE StrictData, OverloadedStrings, DeriveGeneric, DeriveAnyClass #-}
module Reglas.Base where

import Data.Aeson
import Data.Aeson.Types (toJSONKeyText)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Motor.Base

newtype AltId = AltId Int deriving (Eq, Ord, Show, Generic, ToJSON, FromJSON)
newtype PopId = PopId Int deriving (Eq, Ord, Show, Generic, ToJSON, FromJSON)
newtype PerId = PerId Int deriving (Eq, Ord, Show, Generic, ToJSON, FromJSON)

instance ToJSONKey AltId where
  toJSONKey = toJSONKeyText (\(AltId n) -> T.pack (show n))
instance FromJSONKey AltId where
  fromJSONKey = FromJSONKeyTextParser $ \t ->
    case reads (T.unpack t) of
      [(n, "")] -> pure (AltId n)
      _         -> fail "AltId inválido"

instance ToJSONKey PopId where
  toJSONKey = toJSONKeyText (\(PopId n) -> T.pack (show n))
instance FromJSONKey PopId where
  fromJSONKey = FromJSONKeyTextParser $ \t ->
    case reads (T.unpack t) of
      [(n, "")] -> pure (PopId n)
      _         -> fail "PopId inválido"

instance ToJSONKey PerId where
  toJSONKey = toJSONKeyText (\(PerId n) -> T.pack (show n))
instance FromJSONKey PerId where
  fromJSONKey = FromJSONKeyTextParser $ \t ->
    case reads (T.unpack t) of
      [(n, "")] -> pure (PerId n)
      _         -> fail "PerId inválido"

entRefAlt :: AltId -> EntRef
entRefAlt (AltId i) = EntRef "altepetl" i

entRefPop :: PopId -> EntRef
entRefPop (PopId i) = EntRef "pop" i

-- | Entero → Fijo. `fi 1` = 1.0.
fi :: Int -> Fijo
fi n = Fijo (fromIntegral n * 10000)

-- | Décimas → Fijo. `fiD 1` = 0.1.
fiD :: Int -> Fijo
fiD n = Fijo (fromIntegral n * 1000)
