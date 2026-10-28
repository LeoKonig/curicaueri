{-# LANGUAGE StrictData #-}
-- | Población entera sin perder fracciones. Dos funciones genéricas que el
-- juego usa con sus propias cantidades: crecer con resto y migrar con resto
-- repartiendo por el método del mayor resto (Hamilton). El motor no sabe qué
-- es un pop; solo garantiza que nadie aparece ni desaparece por redondear.
module Motor.Poblacion
  ( parteEntera
  , fraccion
  , crecerConResto
  , repartirMayorResto
  , migrar
  ) where

import Data.List (sortBy)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Ord (Down (..), comparing)

import Motor.Base

-- | ⌊x⌋ como entero (hacia −∞, también para negativos).
parteEntera :: Fijo -> Int
parteEntera (Fijo n) = fromIntegral (n `div` escala)

-- | x − ⌊x⌋, siempre en [0, 1).
fraccion :: Fijo -> Fijo
fraccion (Fijo n) = Fijo (n `mod` escala)

-- | Crecimiento con resto (documento funcional, sección 12):
--   x = N·r + ρ,  N' = max piso (N + ⌊x⌋),  ρ' = x − ⌊x⌋.
crecerConResto :: Int -> Fijo -> Int -> Fijo -> (Int, Fijo)
crecerConResto piso r n rho =
  let x = desdeEntero n .*. r .+. rho
  in (max piso (n + parteEntera x), fraccion x)

-- | Reparte un total entero en proporción a unos pesos, sin perder ni crear
-- unidades: cada clave recibe la parte entera de su cuota y las unidades
-- sobrantes van a las de mayor parte fraccionaria; los empates, por clave.
-- La aritmética es entera y exacta (sin redondeo de punto fijo).
repartirMayorResto :: Ord k => Int -> [(k, Fijo)] -> [(k, Int)]
repartirMayorResto total pesos
  | total <= 0 || den <= 0 = [ (k, 0) | (k, _) <- pesos ]
  | otherwise =
      let cuotas   = [ (k, (toInteger total * w) `divMod` den) | (k, w) <- validos ]
          base     = sum [ q | (_, (q, _)) <- cuotas ]
          sobrante = fromInteger (toInteger total - base)
          orden    = sortBy (comparing (\(k, (_, r)) -> (Down r, k))) cuotas
          extra    = Set.fromList [ k | (k, _) <- take sobrante orden ]
          parte    = Map.fromList [ (k, fromInteger q + (if Set.member k extra then 1 else 0))
                                  | (k, (q, _)) <- cuotas ]
      in [ (k, Map.findWithDefault 0 k parte) | (k, _) <- pesos ]
  where
    validos = [ (k, toInteger w) | (k, Fijo w) <- pesos, w > 0 ]
    den     = sum (map snd validos)

-- | Migración simultánea con resto. Para cada origen i, con flujos
-- fraccionarios f_ij ≥ 0 calculados por el juego desde el estado anterior:
--
-- 1. salida O_i = ⌊Σ_j f_ij + ρ_i⌋, acotada para no bajar del piso;
-- 2. O_i se reparte entre los destinos por mayor resto, con pesos f_ij;
-- 3. ρ_i guarda la fracción (se pierde solo si el piso recortó la salida).
--
-- Cada origen decide sin mirar a los demás; un destino suma lo que le llega.
-- Lo que sale de cada origen es exactamente lo que entra en sus destinos.
migrar :: Ord k
       => Int                      -- ^ piso de población por asentamiento
       -> Map k Int                -- ^ población
       -> Map k Fijo               -- ^ restos por origen
       -> Map k [(k, Fijo)]        -- ^ flujos fraccionarios por origen
       -> (Map k Int, Map k Fijo)
migrar piso pob restos flujos =
  let porOrigen =
        [ (i, salida, restoNuevo, repartirMayorResto salida destinos)
        | (i, n) <- Map.toList pob
        , let destinos   = [ (j, f) | (j, f) <- Map.findWithDefault [] i flujos
                                    , j /= i, Map.member j pob ]
              rho        = Map.findWithDefault (Fijo 0) i restos
              x          = foldr ((.+.) . snd) rho destinos
              deseada    = max 0 (parteEntera x)
              salida     = min deseada (max 0 (n - piso))
              restoNuevo = if salida < deseada then Fijo 0 else fraccion x
        ]
      salidas  = Map.fromList [ (i, o) | (i, o, _, _) <- porOrigen ]
      entradas = Map.fromListWith (+) [ (j, q) | (_, _, _, rep) <- porOrigen, (j, q) <- rep ]
      pob'     = Map.mapWithKey
                   (\k n -> n - Map.findWithDefault 0 k salidas + Map.findWithDefault 0 k entradas) pob
      restos'  = Map.fromList [ (i, r) | (i, _, r, _) <- porOrigen ]
  in (pob', restos')
