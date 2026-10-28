{-# LANGUAGE DeriveGeneric, DeriveAnyClass, StrictData #-}
module Motor.Base where

import Data.Aeson (withObject, (.:), (.=))
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import qualified Data.Scientific as S

import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

-- | Punto fijo con escala 10 000 (resolución 1e-4).
newtype Fijo = Fijo Int64
  deriving (Eq, Ord, Show, Generic)

escala :: Int64
escala = 10000

uno :: Fijo
uno = Fijo escala

sat :: Integer -> Int64
sat n = fromInteger (max (toInteger (minBound :: Int64))
                          (min (toInteger (maxBound :: Int64)) n))

rangoFijo :: Fijo -> Fijo -> Fijo -> Fijo
rangoFijo lo hi x = max lo (min hi x)

-- Las mismas precedencias que + y *. Sin estas declaraciones, los cuatro
-- operadores tenían todos la precedencia por omisión (infixl 9) y
-- `a .+. b .*. c` se leía como `(a .+. b) .*. c`.
infixl 6 .+., .-.
infixl 7 .*., ./.

(.+.) :: Fijo -> Fijo -> Fijo
Fijo a .+. Fijo b = Fijo (sat (toInteger a + toInteger b))

(.-.) :: Fijo -> Fijo -> Fijo
Fijo a .-. Fijo b = Fijo (sat (toInteger a - toInteger b))

(.*.) :: Fijo -> Fijo -> Fijo
Fijo a .*. Fijo b =
  Fijo (sat (toInteger a * toInteger b `div` toInteger escala))

(./.) :: Fijo -> Fijo -> Fijo
Fijo _ ./. Fijo 0 = Fijo 0          -- TODO: devolver Maybe
Fijo a ./. Fijo b =
  Fijo (sat (toInteger a * toInteger escala `div` toInteger b))

negF :: Fijo -> Fijo
negF (Fijo a) = Fijo (negate a)

-- | Parseo decimal; rechaza más de 4 decimales.
desdeDecimal :: Text -> Either String Fijo
desdeDecimal t
  | T.null t = Left "vacío"
  | otherwise =
      let neg = T.head t == '-'
          s   = if neg then T.tail t else t
      in case T.splitOn "." s of
           [e] -> do n <- readInt e
                     let v = fromIntegral n * escala
                     Right (Fijo (if neg then negate v else v))
           [e, f] -> do n <- readInt e
                        fr <- readFrac f
                        let v = fromIntegral n * escala + fr
                        Right (Fijo (if neg then negate v else v))
           _ -> Left ("Número inválido: " <> T.unpack t)
  where
    readInt s = case reads (T.unpack s) :: [(Int, String)] of
      [(n, "")] -> Right n
      _ -> Left ("Entero inválido: " <> T.unpack s)
    readFrac s
      | T.length s > 4 = Left "Más de cuatro decimales"
      | otherwise =
          let pad = T.justifyLeft 4 '0' s   -- "5" es 0,5 = 5000, no 0005
          in case reads (T.unpack pad) :: [(Int64, String)] of
               [(n, "")] -> Right n
               _ -> Left ("Fracción inválida: " <> T.unpack s)

newtype Tick     = Tick Int64     deriving (Eq, Ord, Show, Generic)
newtype Semilla  = Semilla Int    deriving (Eq, Show, Generic)
newtype CeldaId  = CeldaId Int    deriving (Eq, Ord, Show, Generic)
newtype AsentId  = AsentId Int    deriving (Eq, Ord, Show, Generic)
newtype FaccionId = FaccionId Int deriving (Eq, Ord, Show, Generic)

-- | Referencia a cualquier entidad.
data EntRef = EntRef { entClase :: Text, entId :: Int }
  deriving (Eq, Ord, Show, Generic)

-- El calendario (veintenas, meses…) vive en Motor.Calendario: es dato del escenario.

-- | Ln determinista (Taylor sobre atanh) — primera implementación.
lnFijo :: Fijo -> Either String Fijo
lnFijo (Fijo x)
  | x <= 0 = Left "lnFijo: dominio no positivo"
  | otherwise = Right (Fijo (sat res))
  where
    hp    = 10000000000 :: Integer       -- 10^10
    x'    = toInteger x
    k     = buscarK 0 x'
    m     = if k >= 0 then x' `div` (2 ^ k) else x' * (2 ^ negate k)
    w     = (m - toInteger escala) * hp `div` (m + toInteger escala)
    atanhW = serie w
    lnM   = 2 * atanhW `div` (hp `div` toInteger escala)
    res   = k * 6931 + lnM
    buscarK k' v
      | v >= 2 * toInteger escala = buscarK (k' + 1) (v `div` 2)
      | v < toInteger escala      = buscarK (k' - 1) (v * 2)
      | otherwise = k'
    serie w0 =
      let w2 = w0 * w0 `div` hp
          go i wk acc
            | i > 30    = acc
            | otherwise =
                let term = wk `div` (2 * i + 1)
                    acc' = acc + term
                in if term == 0 then acc else go (i + 1) (wk * w2 `div` hp) acc'
      in go 0 w0 0

-- | Exp determinista: tabla para la parte entera y Taylor para la fraccionaria.
-- Dominio útil: |x| < 14; fuera de él satura en 0 o en maxBound.
expFijo :: Fijo -> Fijo
expFijo (Fijo x0)
  | x0 == 0 = uno
  | x0 < 0 =
      let Fijo e = expFijo (Fijo (negate x0))
      in if e == maxBound then Fijo 0
         else Fijo (sat (toInteger escala * toInteger escala `div` toInteger e))
  | x >= 14 * esc = Fijo maxBound
  | otherwise = Fijo (sat (tabla !! n * frac `div` esc))
  where
    esc  = toInteger escala
    x    = toInteger x0
    n    = fromIntegral (x `div` esc) :: Int
    y    = x - toInteger n * esc
    frac = taylor y            -- e^y en punto fijo, con y en [0, 1)
    taylor :: Integer -> Integer
    taylor y0 =
      let go :: Int -> Integer -> Integer -> Integer
          go i term acc
            | i > 25    = acc
            | otherwise =
                let t' = term * y0 `div` (esc * toInteger (i + 1))
                in if t' == 0 then acc else go (i + 1) t' (acc + t')
      in go 0 esc esc          -- el primer término de la serie es 1
    tabla =
      [ 10000, 27183, 73891, 200855, 545981, 1484132
      , 4034288, 10966332, 29809580, 81030839, 220264284
      , 598741481, 1627547794, 4424133958 ] :: [Integer]

unFijo :: Fijo -> Int64
unFijo (Fijo n) = n

-- | Un entero de unidades completas (40 es 40,0, no 0,0040).
desdeEntero :: Int -> Fijo
desdeEntero n = Fijo (fromIntegral n * escala)

-- Instancias JSON junto a sus tipos (sin huérfanas).
-- | Fijo desde string ("3", "1.5") o número JSON, siempre por desdeDecimal.
instance A.FromJSON Fijo where
  parseJSON (A.String t) = either fail pure (desdeDecimal t)
  parseJSON (A.Number n) =
    let t = T.pack (S.formatScientific S.Fixed Nothing n)
    in either fail pure (desdeDecimal t)
  parseJSON v = A.typeMismatch "Fijo" v

-- | Fijo como texto decimal exacto: 1,5 se escribe "1.5", nunca un flotante.
instance A.ToJSON Fijo where
  toJSON (Fijo n) =
    let s  = if n < 0 then "-" else ""
        a  = abs n
        i  = a `div` 10000
        f  = a `mod` 10000
        fs = if f == 0 then ""
             else "." <> T.dropWhileEnd (== '0') (T.justifyRight 4 '0' (T.pack (show f)))
    in A.String (s <> T.pack (show i) <> fs)

instance A.FromJSON EntRef where
  parseJSON = withObject "EntRef" $ \o -> EntRef <$> o .: "clase" <*> o .: "id"
instance A.ToJSON EntRef where
  toJSON (EntRef c i) = A.object ["clase" .= c, "id" .= i]

