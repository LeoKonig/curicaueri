{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Calendarios: el interno, que decide qué días corren los sistemas de
-- periodo, y el visible, que muestra la fecha europea al jugador.
--
-- Los dos son datos del escenario, no del motor. El prototipo purépecha usa
-- veintenas (18 periodos de 20 días y 5 nemontemi); otra época puede usar
-- meses, semanas o estaciones agrícolas sin tocar el motor.
--
-- El año interno no tiene bisiestos, así que se desfasa poco a poco del año
-- europeo, como en la realidad (V5, *Calendario interno*).
module Motor.Calendario
  ( -- * Calendario interno
    CalendarioInterno (..)
  , calendarioVeintenas
  , diasDelAnio
  , diaDelAnio
  , esInicioDePeriodo
  , esInicioDeAnio
  , InfoPeriodo (..)
  , infoPeriodo
    -- * Calendario visible
  , Fecha (..)
  , CalendarioVisible (..)
  , diaJuliano
  , desdeDiaJuliano
  , diaJulianoGregoriano
  , desdeDiaJulianoGregoriano
  , fechaDelTick
  , fechaVisible
  ) where

import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.=))
import Data.Text (Text)

import Motor.Base

-- ---------------------------------------------------------------------------
-- Calendario interno
-- ---------------------------------------------------------------------------

-- | Un año de @periodos × diasPorPeriodo@ días, más unos días fuera de
-- periodo al final, en los que no corren los sistemas de periodo.
data CalendarioInterno = CalendarioInterno
  { ciNombrePeriodo   :: Text   -- ^ "veintena", "mes", "semana"…
  , ciNombreFuera     :: Text   -- ^ "nemontemi", "epagómenos"… (vacío si no hay)
  , ciDiasPorPeriodo  :: Int
  , ciPeriodosPorAnio :: Int
  , ciDiasFuera       :: Int
  , ciDesfase         :: Int    -- ^ día del año interno en que cae el tick 0
  } deriving (Eq, Show)

-- | El calendario del prototipo: 18 veintenas y 5 nemontemi.
calendarioVeintenas :: Int -> CalendarioInterno
calendarioVeintenas = CalendarioInterno "veintena" "nemontemi" 20 18 5

diasDelAnio :: CalendarioInterno -> Int
diasDelAnio c = ciDiasPorPeriodo c * ciPeriodosPorAnio c + ciDiasFuera c

diaDelAnio :: CalendarioInterno -> Tick -> Int
diaDelAnio c (Tick t) = fromIntegral ((t + fromIntegral (ciDesfase c)) `mod` fromIntegral (diasDelAnio c))

dentroDePeriodos :: CalendarioInterno -> Int -> Bool
dentroDePeriodos c d = d < ciDiasPorPeriodo c * ciPeriodosPorAnio c

-- | Los sistemas de cadencia 'Periodo' corren el primer día de cada periodo,
-- nunca en los días fuera de periodo.
esInicioDePeriodo :: CalendarioInterno -> Tick -> Bool
esInicioDePeriodo c t =
  let d = diaDelAnio c t in dentroDePeriodos c d && d `mod` ciDiasPorPeriodo c == 0

esInicioDeAnio :: CalendarioInterno -> Tick -> Bool
esInicioDeAnio c t = diaDelAnio c t == 0

data InfoPeriodo = InfoPeriodo
  { ipFuera             :: Bool -- ^ en los días fuera de periodo
  , ipPeriodo           :: Int  -- ^ 1 a periodosPorAnio; 0 fuera de periodo
  , ipDia               :: Int  -- ^ día dentro del periodo, o de los días fuera
  , ipDiasParaSiguiente :: Int  -- ^ días hasta el inicio del siguiente periodo
  } deriving (Eq, Show)

infoPeriodo :: CalendarioInterno -> Tick -> InfoPeriodo
infoPeriodo c t =
  let d = diaDelAnio c t
      n = ciDiasPorPeriodo c
      dentro = ciDiasPorPeriodo c * ciPeriodosPorAnio c
  in if dentroDePeriodos c d
       then InfoPeriodo False (d `div` n + 1) (d `mod` n + 1) (n - d `mod` n)
       else InfoPeriodo True 0 (d - dentro + 1) (diasDelAnio c - d)

instance ToJSON CalendarioInterno where
  toJSON c = object
    [ "nombre_periodo" .= ciNombrePeriodo c, "nombre_fuera" .= ciNombreFuera c
    , "dias_por_periodo" .= ciDiasPorPeriodo c, "periodos_por_anio" .= ciPeriodosPorAnio c
    , "dias_fuera" .= ciDiasFuera c, "desfase" .= ciDesfase c ]

instance FromJSON CalendarioInterno where
  parseJSON = withObject "calendario" $ \o -> CalendarioInterno
    <$> o .: "nombre_periodo" <*> o .: "nombre_fuera"
    <*> o .: "dias_por_periodo" <*> o .: "periodos_por_anio"
    <*> o .: "dias_fuera" <*> o .: "desfase"

-- ---------------------------------------------------------------------------
-- Calendario visible
-- ---------------------------------------------------------------------------

data Fecha = Fecha { fAnio :: Int, fMes :: Int, fDia :: Int }
  deriving (Eq, Ord, Show)

-- | Qué calendario europeo se muestra.
data CalendarioVisible
  = SoloJuliano
  | SoloGregoriano
  | CambioAGregoriano Fecha
    -- ^ juliano hasta esa fecha (inclusive, en juliano) y gregoriano después.
    -- En Europa católica, el 4 de octubre de 1582 fue seguido del 15.
  deriving (Eq, Show)

-- | Número de día juliano de una fecha del calendario juliano.
diaJuliano :: Fecha -> Int
diaJuliano (Fecha y m d) =
  let a  = (14 - m) `div` 12
      y' = y + 4800 - a
      m' = m + 12 * a - 3
  in d + (153 * m' + 2) `div` 5 + 365 * y' + y' `div` 4 - 32083

desdeDiaJuliano :: Int -> Fecha
desdeDiaJuliano jd =
  let c = jd + 32082
      d = (4 * c + 3) `div` 1461
      e = c - (1461 * d) `div` 4
      m = (5 * e + 2) `div` 153
  in Fecha (d - 4800 + m `div` 10) (m + 3 - 12 * (m `div` 10)) (e - (153 * m + 2) `div` 5 + 1)

-- | Número de día juliano de una fecha del calendario gregoriano.
diaJulianoGregoriano :: Fecha -> Int
diaJulianoGregoriano (Fecha y m d) =
  let a  = (14 - m) `div` 12
      y' = y + 4800 - a
      m' = m + 12 * a - 3
  in d + (153 * m' + 2) `div` 5 + 365 * y' + y' `div` 4 - y' `div` 100 + y' `div` 400 - 32045

desdeDiaJulianoGregoriano :: Int -> Fecha
desdeDiaJulianoGregoriano jd =
  let a = jd + 32044
      b = (4 * a + 3) `div` 146097
      c = a - (146097 * b) `div` 4
      d = (4 * c + 3) `div` 1461
      e = c - (1461 * d) `div` 4
      m = (5 * e + 2) `div` 153
  in Fecha (100 * b + d - 4800 + m `div` 10) (m + 3 - 12 * (m `div` 10)) (e - (153 * m + 2) `div` 5 + 1)

-- | Fecha juliana de un tick, dada la fecha juliana del tick 0.
fechaDelTick :: Fecha -> Tick -> Fecha
fechaDelTick inicio (Tick t) = desdeDiaJuliano (diaJuliano inicio + fromIntegral t)

-- | La fecha visible de un tick y el nombre de su calendario. La fecha de
-- inicio se da en el calendario que rige ese día.
fechaVisible :: CalendarioVisible -> Fecha -> Tick -> (Fecha, Text)
fechaVisible cal inicio (Tick t) = case cal of
  SoloJuliano    -> (desdeDiaJuliano jd, "juliano")
  SoloGregoriano -> (desdeDiaJulianoGregoriano (diaJulianoGregoriano inicio + dt), "gregoriano")
  CambioAGregoriano ultimo
    | jd <= diaJuliano ultimo -> (desdeDiaJuliano jd, "juliano")
    | otherwise               -> (desdeDiaJulianoGregoriano jd, "gregoriano")
  where
    dt = fromIntegral t
    jd0 = case cal of
      CambioAGregoriano ultimo | inicio > ultimo -> diaJulianoGregoriano inicio
      SoloGregoriano -> diaJulianoGregoriano inicio
      _ -> diaJuliano inicio
    jd = jd0 + dt
