{-# LANGUAGE StrictData #-}
module Motor.Azar where

import Data.Bits (xor, shiftR, shiftL)
import Data.Char (ord)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word64)
import Motor.Base

newtype Rng = Rng Word64

splitMix64 :: Word64 -> (Word64, Word64)
splitMix64 s =
  let s' = s + 0x9E3779B97F4A7C15
      z1 = (s' `xor` (s' `shiftR` 30)) * 0xBF58476D1CE4E5B9
      z2 = (z1 `xor` (z1 `shiftR` 27)) * 0x94D049BB133111EB
      z3 = z2 `xor` (z2 `shiftR` 31)
  in (s', z3)

fnv1a64 :: Text -> Word64
fnv1a64 = T.foldl' step 0xcbf29ce484222325
  where step h c = (h `xor` fromIntegral (ord c)) * 0x100000001b3

mezcla :: Semilla -> Word64 -> Word64 -> Word64
mezcla (Semilla s) h t =
  let (_, a) = splitMix64 (fromIntegral s)
      (_, b) = splitMix64 (a `xor` h)
      (_, c) = splitMix64 (b `xor` t)
  in c

rng :: Semilla -> Text -> Tick -> Rng
rng sigma nombre (Tick t) =
  Rng (mezcla sigma (fnv1a64 nombre) (fromIntegral t))

uniforme :: Rng -> (Fijo, Rng)
uniforme (Rng s) =
  let (s', v) = splitMix64 s
      top32   = v `shiftR` 32
      f       = top32 * 10000 `div` (1 `shiftL` 32)
  in (Fijo (fromIntegral (f :: Word64)), Rng s')

uniformeEntero :: Int -> Rng -> (Int, Rng)
uniformeEntero n r =
  let (u, r') = uniforme r
      v = fromIntegral (unFijo u) :: Int
  in (v `mod` max 1 n, r')

-- | Lista infinita y perezosa de generadores encadenados.
rngStream :: Rng -> [Rng]
rngStream r = r : rngStream (snd (uniforme r))
