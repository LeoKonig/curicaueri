{-# LANGUAGE StrictData #-}
module Motor.Mapa where

import Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IntMap
import Data.Maybe (fromMaybe)
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

-- | A qué asentamiento trabaja cada celda (documento funcional, sección 8):
--
-- > asig(c) = argmin_a (d_km(c, celda(a)), id(a))   con d_km ≤ R_prod
--
-- Un Dijkstra multifuente sobre el costo de las conexiones, que equivale a
-- los km entre un punto y otro (5 en tierra, más por mar). Cada celda recibe el asentamiento más cercano; el empate
-- lo rompe el id menor. Las celdas a más de @radio@ km de todo asentamiento
-- no aparecen en el resultado. Es derivado: se recalcula, no se guarda.
--
-- La etiqueta de un camino es el par (distancia, id de la fuente), que se
-- ordena lexicográficamente. Sumar una longitud no negativa conserva ese
-- orden, así que el Dijkstra sigue siendo correcto con empates y con
-- conexiones de costo 0. Un asentamiento cuya celda no está en el mapa se
-- ignora; si dos comparten celda, gana el de id menor.
asignarCeldas :: Fijo -> Mapa -> [(AsentId, CeldaId)] -> IntMap AsentId
asignarCeldas radio mapa fuentes = IntMap.map AsentId (visitar inicial IntMap.empty)
  where
    celdas = mapaCeldas mapa
    inicial = Set.fromList
      [ (Fijo 0, a, c) | (AsentId a, CeldaId c) <- fuentes
                       , IntMap.member c celdas, Fijo 0 <= radio ]
    -- La cola es un conjunto ordenado por (distancia, asentamiento, celda):
    -- el mínimo es siempre la etiqueta más pequeña aún sin fijar.
    visitar cola fijadas = case Set.minView cola of
      Nothing -> fijadas
      Just ((d, a, c), resto)
        | IntMap.member c fijadas -> visitar resto fijadas
        | otherwise ->
            let fijadas' = IntMap.insert c a fijadas
                nuevas = [ (d', a, v)
                         | (CeldaId v, con) <- fromMaybe [] (IntMap.lookup c (mapaVecinos mapa))
                         , not (IntMap.member v fijadas')
                         , let d' = d .+. connCosto con
                         , d' <= radio ]
            in visitar (foldr Set.insert resto nuevas) fijadas'
