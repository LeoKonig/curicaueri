{-# LANGUAGE StrictData #-}
module Motor.Mapa where

import Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IntMap
import Data.List (sortBy)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word64)
import Motor.Azar (fnv1a64)
import Motor.Base

newtype Terreno = Terreno Text deriving (Eq, Ord, Show)
newtype Recurso = Recurso Text deriving (Eq, Ord, Show)

data AtributoConexion = Rio | PasoMontana | Camino
  deriving (Eq, Ord, Show)

data Celda = Celda
  { celdaId        :: CeldaId
  , celdaTerreno   :: Terreno
  , celdaElevacion :: Fijo
  , celdaRecursos  :: Set Recurso
  , celdaComposicion :: [(Terreno, Fijo)]
    -- ^ los terrenos que forman la celda con su fracción, el dominante
    -- primero (V5, *La celda como mezcla de terrenos*; T36). Vacía, que es el
    -- valor por defecto, la celda es toda de 'celdaTerreno'. Solo cambia lo
    -- que la celda da: el costo de cruzarla, el combate y el color siguen
    -- siendo los del dominante.
  } deriving (Eq, Show)

-- | La composición efectiva: la declarada o, sin ella, la celda entera de
-- su terreno.
composicionDe :: Celda -> [(Terreno, Fijo)]
composicionDe c = case celdaComposicion c of
  [] -> [(celdaTerreno c, uno)]
  cs -> cs

-- | Cuántos componentes puede tener una celda como mucho.
maxComponentes :: Int
maxComponentes = 4

data Conexion = Conexion
  { connLongitud  :: Fijo
  , connCosto     :: Fijo
  , connAtributos :: Set AtributoConexion
  } deriving (Eq, Show)

data Mapa = Mapa
  { mapaCeldas  :: IntMap Celda
  , mapaVecinos :: IntMap [(CeldaId, Conexion)]
  , mapaEscala  :: Fijo
  } deriving (Eq, Show)

data ErrorMapa
  = ConexionAsimetrica CeldaId CeldaId
  | CeldaAislada CeldaId
  | EscalaInvalida
  | VecinosSinCelda CeldaId
  | CostoNegativo CeldaId CeldaId
  | ComposicionInvalida CeldaId Text
  deriving (Eq, Show)

validarMapa :: Mapa -> [ErrorMapa]
validarMapa m = concat
  [ [EscalaInvalida | mapaEscala m <= Fijo 0]
  , [ ConexionAsimetrica (CeldaId ai) (CeldaId bi)
    | (ai, vs) <- IntMap.toList vecinos
    , (CeldaId bi, _) <- vs
    , not (any (\(CeldaId ci, _) -> ci == ai)
               (IntMap.findWithDefault [] bi vecinos))
    ]
  , [ CeldaAislada (celdaId c)
    | c <- IntMap.elems celdas
    , let CeldaId i = celdaId c
    , null (IntMap.findWithDefault [] i vecinos)
    ]
  , [ VecinosSinCelda (CeldaId vi)
    | vi <- IntMap.keys vecinos
    , not (IntMap.member vi celdas)
    ]
    -- Los recorridos por el grafo (Dijkstra) suponen costos no negativos.
  , [ CostoNegativo (CeldaId ai) b
    | (ai, vs) <- IntMap.toList vecinos
    , (b, con) <- vs
    , connCosto con < Fijo 0
    ]
  , [ ComposicionInvalida (celdaId c) motivo
    | c <- IntMap.elems celdas, Just motivo <- [composicionInvalida c] ]
  ]
  where
    celdas  = mapaCeldas m
    vecinos = mapaVecinos m

-- | Ley «composición válida» (documento funcional, sección 19): de 1 a
-- 'maxComponentes' componentes de terrenos distintos, fracciones positivas
-- que suman 1 y el terreno de la celda como el de mayor fracción. Que cada
-- terreno exista en la tabla lo comprueba 'Motor.Terrenos.validarTerrenosDelMapa'.
composicionInvalida :: Celda -> Maybe Text
composicionInvalida c = case celdaComposicion c of
  [] -> Nothing
  cs
    | length cs > maxComponentes -> Just "más de cuatro componentes"
    | Set.size (Set.fromList (map fst cs)) /= length cs -> Just "un terreno repetido"
    | any ((<= Fijo 0) . snd) cs -> Just "una fracción no positiva"
    | sum [ x | (_, Fijo x) <- cs ] /= escala -> Just "las fracciones no suman 1"
    | Just s0 <- lookup (celdaTerreno c) cs, all ((<= s0) . snd) cs -> Nothing
    | otherwise -> Just "el terreno de la celda no es el de mayor fracción"

-- | La mezcla del mapa provisional (V5, *De dónde sale la mezcla*): cada celda
-- toma, de cada terreno distinto al suyo que tienen sus vecinos, la fracción
--
-- > s_T = ε · (vecinos con T) / 6
--
-- y se queda con el resto. Con más de tres terrenos vecinos distintos se
-- quedan los tres de mayor fracción, con empate por nombre, y lo de los demás
-- vuelve al terreno propio. Como ε ≤ 1/2, el propio tiene al menos la mitad y
-- sigue siendo el dominante. Con ε = 0 el mapa no cambia. Lee los terrenos
-- del mapa de entrada, no los ya mezclados, así que el orden de las celdas no
-- importa. Es O(celdas · vecinos) y se hace una vez, al cargar.
conMezcla :: Fijo -> Mapa -> Mapa
conMezcla eps m
  | eps <= Fijo 0 = m
  | otherwise = m { mapaCeldas = IntMap.mapWithKey mezclar (mapaCeldas m) }
  where
    terrenoDe i = celdaTerreno <$> IntMap.lookup i (mapaCeldas m)
    mezclar i c =
      let propio = celdaTerreno c
          cuentas = Map.fromListWith (+)
            [ (t, 1 :: Int) | (CeldaId v, _) <- IntMap.findWithDefault [] i (mapaVecinos m)
            , Just t <- [terrenoDe v], t /= propio ]
          Fijo e = eps
          fraccion n = Fijo (fromIntegral ((fromIntegral e * fromIntegral n :: Integer) `div` 6))
          ajenos = take (maxComponentes - 1)
                     (sortBy (\(ta, a) (tb, b) -> compare (b, ta) (a, tb))
                        [ (t, fraccion n) | (t, n) <- Map.toList cuentas, fraccion n > Fijo 0 ])
          Fijo resto = foldr (\(_, x) a -> a .+. x) (Fijo 0) ajenos
      in if null ajenos then c
         else c { celdaComposicion = (propio, Fijo (escala - resto)) : ajenos }

-- | Datos para generar un mapa hexagonal.
data DatosHex = DatosHex
  { hexAncho   :: Int
  , hexAlto    :: Int
  , hexRadioKm :: Fijo
  , hexSemilla :: Word64
  }

proveedorHexagonal :: DatosHex -> Either ErrorMapa Mapa
proveedorHexagonal d
  | hexAncho d <= 0 || hexAlto d <= 0 = Left EscalaInvalida
  | hexRadioKm d <= Fijo 0            = Left EscalaInvalida
  | otherwise                         = Right (generar d)

generar :: DatosHex -> Mapa
generar d = Mapa celdas vecinos (hexRadioKm d)
  where
    ancho = hexAncho d
    alto  = hexAlto d
    idx c r = r * ancho + c
    celdas = IntMap.fromList
      [ (idx c r, mkCelda ancho c r)
      | r <- [0 .. alto - 1], c <- [0 .. ancho - 1] ]
    vecinos = IntMap.fromList
      [ (idx c r, ady (hexRadioKm d) ancho alto c r)
      | r <- [0 .. alto - 1], c <- [0 .. ancho - 1] ]

mkCelda :: Int -> Int -> Int -> Celda
mkCelda ancho c r =
  let h = fnv1a64 (T.pack ("h" ++ show c ++ "," ++ show r))
      terrenos = [Terreno "llano", Terreno "bosque"
                 , Terreno "sierra", Terreno "lago"]
      t = terrenos !! fromIntegral (h `mod` 4)
  in Celda (CeldaId (r * ancho + c)) t (Fijo (fromIntegral (h `mod` 10000))) Set.empty []

-- | Convención pointy-top, paridad de fila. Genera conexiones simétricas.
-- Entre dos celdas vecinas hay un paso: la longitud es la escala del mapa
-- (km por celda, V5 *El mapa como grafo*). El costo de la conexión coincide
-- con su longitud: para fines prácticos es la distancia en km, el peso del
-- grafo. Las rutas marítimas tendrán un costo mayor cuando existan.
ady :: Fijo -> Int -> Int -> Int -> Int -> [(CeldaId, Conexion)]
ady longitud ancho alto c r =
  [ (CeldaId (r' * ancho + c'), Conexion longitud longitud Set.empty)
  | (dc, dr) <- offsets, let { c' = c + dc; r' = r + dr }
  , c' >= 0, c' < ancho, r' >= 0, r' < alto ]
  where
    offsets =
      if odd r
        then [(1, -1), (1, 0), (1, 1), (0, 1), (-1, 0), (0, -1)]
        else [(0, -1), (1, 0), (0, 1), (-1, 1), (-1, 0), (-1, -1)]
