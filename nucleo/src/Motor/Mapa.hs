{-# LANGUAGE StrictData #-}
module Motor.Mapa where

import Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IntMap
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
  } deriving (Eq, Show)

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
  ]
  where
    celdas  = mapaCeldas m
    vecinos = mapaVecinos m

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
  in Celda (CeldaId (r * ancho + c)) t (Fijo (fromIntegral (h `mod` 10000))) Set.empty

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
