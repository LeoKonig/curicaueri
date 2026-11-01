{-# OPTIONS_GHC -O2 #-}
{-# LANGUAGE BangPatterns, StrictData #-}
-- | Recorridos multifuente sobre el grafo del mapa (documento funcional,
-- secciones 8 y 9): la asignación de celdas a asentamientos y la base de la
-- influencia.
--
-- Hay dos implementaciones del mismo recorrido, y una ley dice que dan lo
-- mismo:
--
-- * 'propagarGrafo', para calcular desde cero. Trabaja sobre el 'Grafo'
--   compacto con arreglos sin boxing dentro de 'ST'; por fuera es una función
--   pura. Es la que corre cuando cambia mucho.
--
-- * 'propagar', sobre mapas persistentes. Parte de un resultado anterior y
--   toca solo las celdas que mejoran; es la que repara cuando cambia poco
--   (la actualización incremental de 'Motor.Influencia').
module Motor.Recorrido
  ( -- * Etiquetas
    Etiqueta (..)
  , Mejores (..)
  , primera
  , listaMejores
  , Cupo (..)
  , insertarMejor
    -- * El grafo compacto
  , Grafo
  , grafoDe
  , grafoMapa
  , numCeldas
    -- * Recorridos
  , propagarGrafo
  , propagar
  , semillasDeVecinas
  , asignarCeldas
  ) where

import Control.Monad (forM, forM_, when)
import Control.Monad.ST (ST, runST)
import Data.Array.Base (unsafeAt, unsafeRead, unsafeWrite)
import Data.Array.ST (STArray, STUArray, newArray, runSTUArray, writeArray)
import Data.Bits (countLeadingZeros, finiteBitSize, xor)
import Data.Array.Unboxed (UArray, listArray)
import Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IntMap
import Data.List (foldl')
import Data.Maybe (catMaybes, isJust)
import Motor.Base
import Motor.Mapa

-- * Etiquetas

-- | La etiqueta de un camino: su distancia acumulada (el costo de llegar,
-- más el potencial con que arrancó la fuente), el grupo al que pertenece (una
-- facción, un asentamiento) y la fuente. Se ordena lexicográficamente en ese
-- orden, así que los empates se rompen por id de grupo y luego de fuente.
data Etiqueta = Etiqueta
  { etDistancia :: Fijo
  , etGrupo     :: Int
  , etFuente    :: Int
  } deriving (Eq, Ord, Show)

-- | Las mejores etiquetas de una celda, de grupos distintos y en orden.
data Mejores = Una Etiqueta | Dos Etiqueta Etiqueta
  deriving (Eq, Show)

primera :: Mejores -> Etiqueta
primera (Una a)   = a
primera (Dos a _) = a

listaMejores :: Mejores -> [Etiqueta]
listaMejores (Una a)   = [a]
listaMejores (Dos a b) = [a, b]

-- | Cuántos grupos distintos guarda cada celda: el dueño, o el dueño y el
-- segundo (para las zonas disputadas).
data Cupo = UnGrupo | DosGrupos
  deriving (Eq, Show)

-- | Mete una etiqueta entre las mejores de una celda. 'Nothing' si no mejora
-- nada: ni es mejor que la de su mismo grupo ni entra entre las mejores.
-- Es la regla de 'propagar'; 'propagarGrafo' la repite sobre sus casillas
-- sin caja, y la ley «el recorrido persistente da lo mismo que el de
-- arreglos» vigila que decidan igual.
insertarMejor :: Cupo -> Etiqueta -> Maybe Mejores -> Maybe Mejores
insertarMejor _ e Nothing = Just (Una e)
insertarMejor cupo e (Just (Una a))
  | cupo == UnGrupo || etGrupo e == etGrupo a = if e < a then Just (Una e) else Nothing
  | e < a     = Just (Dos e a)
  | otherwise = Just (Dos a e)
insertarMejor _ e (Just (Dos a b))
  | etGrupo e == etGrupo a = if e < a then Just (Dos e b) else Nothing
  | etGrupo e == etGrupo b = if e >= b then Nothing
                             else if e < a then Just (Dos e a) else Just (Dos a e)
  | e < a     = Just (Dos e a)
  | e < b     = Just (Dos a e)
  | otherwise = Nothing

-- * El grafo compacto

-- | El mapa en forma compacta para recorrerlo: cada celda tiene un índice
-- denso (en el orden de sus ids) y sus conexiones están en arreglos
-- contiguos, sin boxing. Es derivado del mapa: se construye una vez por mapa
-- y no se guarda.
data Grafo = Grafo
  { grafoMapa :: Mapa
  , grIds     :: UArray Int Int    -- ^ índice → id de celda
  , grIndice  :: IntMap Int        -- ^ id de celda → índice
  , grInicio  :: UArray Int Int    -- ^ las conexiones de i están en [inicio i, inicio (i+1))
  , grVecino  :: UArray Int Int    -- ^ índice de la celda vecina
  , grCosto   :: UArray Int Int    -- ^ costo, en unidades de 'Fijo'; uno negativo cuenta como 0
  }

grafoDe :: Mapa -> Grafo
grafoDe mapa = Grafo mapa ids indice inicio vecino costo
  where
    n = IntMap.size (mapaCeldas mapa)
    ids = listArray (0, n - 1) (IntMap.keys (mapaCeldas mapa))
    indice = IntMap.fromDistinctAscList (zip (IntMap.keys (mapaCeldas mapa)) [0 ..])
    -- Las conexiones de cada celda, en el orden de su lista, sin las que van
    -- a una celda que no existe.
    conexiones c = [ (j, con) | (CeldaId v, con) <- IntMap.findWithDefault [] c (mapaVecinos mapa)
                              , Just j <- [IntMap.lookup v indice] ]
    inicio = runSTUArray $ do
      arr <- newArray (0, n) 0
      forM_ (zip [0 ..] (IntMap.keys (mapaCeldas mapa))) $ \(i, c) ->
        unsafeWrite arr (i + 1) (length (conexiones c))
      forM_ [1 .. n] $ \i -> do
        a <- unsafeRead arr (i - 1)
        b <- unsafeRead arr i
        unsafeWrite arr i (a + b)
      pure arr
    total = inicio `unsafeAt` n
    llenar campo = runSTUArray $ do
      arr <- newArray (0, total - 1) 0
      forM_ (zip [0 ..] (IntMap.keys (mapaCeldas mapa))) $ \(i, c) ->
        forM_ (zip [inicio `unsafeAt` i ..] (conexiones c)) $ \(k, jc) ->
          unsafeWrite arr k (campo jc)
      pure arr
    vecino = llenar fst
    costo = llenar (\(_, con) -> max 0 (let Fijo w = connCosto con in fromIntegral w))

numCeldas :: Grafo -> Int
numCeldas = IntMap.size . grIndice

-- | Suma saturada en el máximo, como '.+.'. Los costos no son negativos.
sumaSat :: Int -> Int -> Int
sumaSat d w = if d > maxBound - w then maxBound else d + w

-- * El recorrido desde cero, en ST

-- | Dijkstra multifuente con etiquetas lexicográficas: para cada celda, las
-- mejores etiquetas de grupos distintos (según el cupo) entre todos los
-- caminos desde las semillas, sin pasar de @tope@. Las celdas sin etiqueta
-- no aparecen. Una semilla en una celda que no está en el mapa se ignora.
--
-- La cola es una cola por cubetas ('Cola') ordenada solo por distancia.
-- Dentro de una misma distancia el orden no importa: una celda se queda con una etiqueta
-- solo si mejora lo que tiene ('insertarMejor', que compara la etiqueta
-- completa), así que el resultado no depende del orden de proceso.
--
-- Es correcto porque una etiqueta de la cola nunca es menor que la que la
-- produjo (los costos no son negativos). Si el camino óptimo de un grupo
-- hasta c pasa por u y ese grupo no está entre las mejores de u, en u hay
-- tantos grupos mejores como cupo, y esos mismos llegan a c antes que él.
propagarGrafo :: Cupo -> Maybe Fijo -> Grafo -> [(CeldaId, Etiqueta)] -> IntMap Mejores
propagarGrafo cupo tope gr semillas = runST $ do
  let n = numCeldas gr
      topeI = maybe maxBound (\(Fijo t) -> fromIntegral t) tope :: Int
      unGrupo = cupo == UnGrupo
  -- Cada celda i tiene dos casillas, 2i y 2i+1, con distancia, grupo y
  -- fuente; ocup dice cuántas están llenas.
  ocup <- newArray (0, n - 1) 0 :: ST s (STUArray s Int Int)
  -- Las tres partes de una casilla k van juntas en 3k, 3k+1 y 3k+2, para
  -- que leer una celda toque una sola línea de caché.
  cs <- newArray (0, 6 * n - 1) 0 :: ST s (STUArray s Int Int)
  let poner k d g f = unsafeWrite cs (3 * k) d >> unsafeWrite cs (3 * k + 1) g >> unsafeWrite cs (3 * k + 2) f
      copiar desde hacia = do
        d <- unsafeRead cs (3 * desde)
        g <- unsafeRead cs (3 * desde + 1)
        f <- unsafeRead cs (3 * desde + 2)
        poner hacia d g f
      -- 'insertarMejor' sobre las casillas, sin construir etiquetas en caja:
      -- si la etiqueta (d, g, f) mejora la celda i. Con @escribe@, además la
      -- mete. La ley «el recorrido persistente da lo mismo que el de
      -- arreglos» vigila que decidan igual.
      intentar !escribe !i !d !g !f = do
        o <- unsafeRead ocup i
        let k1 = 2 * i
            k2 = k1 + 1
        if o == 0
          then do
            when escribe (poner k1 d g f >> unsafeWrite ocup i 1)
            pure True
          else do
            d1 <- unsafeRead cs (3 * k1)
            g1 <- unsafeRead cs (3 * k1 + 1)
            f1 <- unsafeRead cs (3 * k1 + 2)
            let !menor1 = menorQue d g f d1 g1 f1
            if o == 1
              then
                if unGrupo || g == g1
                  then do
                    when (escribe && menor1) (poner k1 d g f)
                    pure menor1
                  else do
                    when escribe $ do
                      if menor1 then copiar k1 k2 >> poner k1 d g f else poner k2 d g f
                      unsafeWrite ocup i 2
                    pure True
              else do
                d2 <- unsafeRead cs (3 * k2)
                g2 <- unsafeRead cs (3 * k2 + 1)
                f2 <- unsafeRead cs (3 * k2 + 2)
                let !menor2 = menorQue d g f d2 g2 f2
                if g == g1 then do
                  when (escribe && menor1) (poner k1 d g f)
                  pure menor1
                else if g == g2 then
                  if not menor2 then pure False else do
                    when escribe (if menor1 then copiar k1 k2 >> poner k1 d g f else poner k2 d g f)
                    pure True
                else if menor1 then do
                  when escribe (copiar k1 k2 >> poner k1 d g f)
                  pure True
                else if menor2 then do
                  when escribe (poner k2 d g f)
                  pure True
                else pure False
      etiq k = do
        d <- unsafeRead cs (3 * k)
        g <- unsafeRead cs (3 * k + 1)
        f <- unsafeRead cs (3 * k + 2)
        pure (Etiqueta (Fijo (fromIntegral d)) g f)
      leer i = do
        o <- unsafeRead ocup i
        case o of
          0 -> pure Nothing
          1 -> Just . Una <$> etiq (2 * i)
          _ -> (\x y -> Just (Dos x y)) <$> etiq (2 * i) <*> etiq (2 * i + 1)
  cola <- nuevaCola
  forM_ semillas $ \(CeldaId c, Etiqueta (Fijo d) g f) ->
    case IntMap.lookup c (grIndice gr) of
      Just i | fromIntegral d <= topeI -> empujar cola (fromIntegral d) i g f
      _ -> pure ()
  let relajar !d !g !f !k !fin
        | k >= fin = pure ()
        | otherwise = do
            let !j  = grVecino gr `unsafeAt` k
                !d' = sumaSat d (grCosto gr `unsafeAt` k)
            when (d' <= topeI) $ do
              mejora <- intentar False j d' g f
              when mejora (empujar cola d' j g f)
            relajar d g f (k + 1) fin
      bucle = sacar cola (pure ()) $ \ !d !i !g !f -> do
        mejora <- intentar True i d g f
        when mejora $
          relajar d g f (grInicio gr `unsafeAt` i) (grInicio gr `unsafeAt` (i + 1))
        bucle
  bucle
  celdas <- forM [0 .. n - 1] $ \i -> fmap (\m -> (grIds gr `unsafeAt` i, m)) <$> leer i
  pure (IntMap.fromDistinctAscList (catMaybes celdas))

-- | El orden de 'Etiqueta' sobre sus tres campos.
menorQue :: Int -> Int -> Int -> Int -> Int -> Int -> Bool
menorQue d g f d' g' f' = d < d' || (d == d' && (g < g' || (g == g' && f < f')))
{-# INLINE menorQue #-}

-- | Cola por cubetas para claves enteras que nunca bajan (un montículo de
-- radix). Dijkstra solo mete claves mayores o iguales que la última que sacó,
-- así que basta comparar cada clave con esa última: la cubeta b guarda las
-- claves cuyo bit más alto distinto de la última es el b−1 (la 0, las iguales).
-- Meter es O(1); sacar vacía la cubeta más baja con algo, que reparte su
-- contenido en cubetas más bajas, y cada entrada baja a lo sumo 64 veces.
-- Las entradas (distancia, celda, grupo, fuente) se guardan de cuatro en
-- cuatro en un arreglo por cubeta que crece.
data Cola s = Cola
  { colaMeta  :: STUArray s Int Int                  -- ^ [0] la última clave sacada, [1] cuántas entradas hay
  , colaTam   :: STUArray s Int Int                  -- ^ entradas por cubeta
  , colaCap   :: STUArray s Int Int                  -- ^ capacidad por cubeta
  , colaDatos :: STArray s Int (STUArray s Int Int)  -- ^ las entradas de cada cubeta
  }

nuevaCola :: ST s (Cola s)
nuevaCola = do
  meta <- newArray (0, 1) 0
  unsafeWrite meta 0 minBound
  tam <- newArray (0, 64) 0
  cap <- newArray (0, 64) 16
  vacio <- newArray (0, 4 * 16 - 1) 0
  datos <- newArray (0, 64) vacio
  forM_ [1 .. 64] $ \b -> newArray (0, 4 * 16 - 1) 0 >>= writeArray datos b
  pure (Cola meta tam cap datos)

-- | La cubeta de una clave respecto de la última sacada.
cubetaDe :: Int -> Int -> Int
cubetaDe ultima k =
  let x = fromIntegral (k `xor` ultima) :: Word
  in if x == 0 then 0 else finiteBitSize x - countLeadingZeros x
{-# INLINE cubetaDe #-}

meterEn :: Cola s -> Int -> Int -> Int -> Int -> Int -> ST s ()
meterEn c !b !d !i !g !f = do
  t <- unsafeRead (colaTam c) b
  cap <- unsafeRead (colaCap c) b
  arr <- if t < cap then unsafeReadArr (colaDatos c) b else do
    viejo <- unsafeReadArr (colaDatos c) b
    nuevo <- newArray (0, 8 * cap - 1) 0
    let copiar !k = when (k < 4 * t) (unsafeRead viejo k >>= unsafeWrite nuevo k >> copiar (k + 1))
    copiar 0
    writeArray (colaDatos c) b nuevo
    unsafeWrite (colaCap c) b (2 * cap)
    pure nuevo
  poner4 arr t d i g f
  unsafeWrite (colaTam c) b (t + 1)

empujar :: Cola s -> Int -> Int -> Int -> Int -> ST s ()
empujar c !d !i !g !f = do
  ultima <- unsafeRead (colaMeta c) 0
  n <- unsafeRead (colaMeta c) 1
  unsafeWrite (colaMeta c) 1 (n + 1)
  meterEn c (cubetaDe ultima d) d i g f

-- | Saca una entrada de clave mínima y se la pasa a @siguiente@; si la cola
-- está vacía, corre @vacia@. Sin tuplas ni 'Maybe' en el camino caliente.
sacar :: Cola s -> ST s a -> (Int -> Int -> Int -> Int -> ST s a) -> ST s a
sacar c vacia siguiente = do
  n <- unsafeRead (colaMeta c) 1
  if n == 0 then vacia else do
    t0 <- unsafeRead (colaTam c) 0
    when (t0 == 0) $ do
      let primeraLlena !b = do
            t <- unsafeRead (colaTam c) b
            if t > 0 then pure b else primeraLlena (b + 1)
      b <- primeraLlena 1
      arr <- unsafeReadArr (colaDatos c) b
      t <- unsafeRead (colaTam c) b
      let minimo !k !m
            | k >= t = pure m
            | otherwise = do
                d <- unsafeRead arr (4 * k)
                minimo (k + 1) (min m d)
      d0 <- unsafeRead arr 0
      m <- minimo 1 d0
      unsafeWrite (colaMeta c) 0 m
      unsafeWrite (colaTam c) b 0
      -- Cada entrada cae en una cubeta más baja que b: comparte con m los
      -- bits por encima del b−1, y m es la menor.
      let repartir !k = when (k < t) $ do
            d <- unsafeRead arr (4 * k)
            i <- unsafeRead arr (4 * k + 1)
            g <- unsafeRead arr (4 * k + 2)
            f <- unsafeRead arr (4 * k + 3)
            meterEn c (cubetaDe m d) d i g f
            repartir (k + 1)
      repartir 0
    t <- unsafeRead (colaTam c) 0
    arr0 <- unsafeReadArr (colaDatos c) 0
    let !k = t - 1
    d <- unsafeRead arr0 (4 * k)
    i <- unsafeRead arr0 (4 * k + 1)
    g <- unsafeRead arr0 (4 * k + 2)
    f <- unsafeRead arr0 (4 * k + 3)
    unsafeWrite (colaTam c) 0 k
    unsafeWrite (colaMeta c) 1 (n - 1)
    siguiente d i g f

unsafeReadArr :: STArray s Int e -> Int -> ST s e
unsafeReadArr = unsafeRead
{-# INLINE unsafeReadArr #-}

poner4 :: STUArray s Int Int -> Int -> Int -> Int -> Int -> Int -> ST s ()
poner4 arr k d i g f = do
  unsafeWrite arr (4 * k) d
  unsafeWrite arr (4 * k + 1) i
  unsafeWrite arr (4 * k + 2) g
  unsafeWrite arr (4 * k + 3) f

-- * La reparación, sobre mapas persistentes

-- | El mismo recorrido que 'propagarGrafo', pero partiendo de las etiquetas
-- que ya tiene cada celda (@inicial@) y sobre mapas persistentes: solo copia
-- lo que cambia, así que su costo es proporcional a las celdas que mejoran.
-- Con @inicial@ vacío da lo mismo que 'propagarGrafo' (es una ley).
--
-- Precondición para usar @inicial@: cada etiqueta inicial es la distancia de
-- un camino real, y a cada celda que perdió una etiqueta se le vuelve a
-- ofrecer todo lo que le llega ('semillasDeVecinas' y las fuentes que están
-- en ella).
propagar :: Cupo -> Maybe Fijo -> Mapa -> [(CeldaId, Etiqueta)] -> IntMap Mejores -> IntMap Mejores
propagar cupo tope mapa semillas inicial = vaciar cola0 inicial
  where
    celdas = mapaCeldas mapa
    dentro e = maybe True (etDistancia e <=) tope
    clave e = let Fijo d = etDistancia e in fromIntegral d :: Int
    -- La cola: un 'IntMap' de la distancia a las entradas con esa distancia.
    empujarP q c e = IntMap.insertWith (\_ viejo -> (c, e) : viejo) (clave e) [(c, e)] q
    cola0 = foldl' (\q (CeldaId c, e) -> if IntMap.member c celdas && dentro e then empujarP q c e else q)
                   IntMap.empty semillas
    vaciar q m = case IntMap.minView q of
      Nothing -> m
      Just (cubeta, q') -> let (q'', m') = foldl' paso (q', m) cubeta in vaciar q'' m'
    paso (q, m) (c, e) = case insertarMejor cupo e (IntMap.lookup c m) of
      Nothing -> (q, m)
      Just nuevo ->
        let m' = IntMap.insert c nuevo m
            relajar qa (CeldaId v, con) =
              let e' = e { etDistancia = etDistancia e .+. max (Fijo 0) (connCosto con) }
              in if dentro e' && IntMap.member v celdas
                      && isJust (insertarMejor cupo e' (IntMap.lookup v m'))
                   then empujarP qa v e' else qa
        in (foldl' relajar q (IntMap.findWithDefault [] c (mapaVecinos mapa)), m')

-- | Lo que llega a cada celda de @destinos@ desde las etiquetas de sus
-- vecinas: parte de las semillas con que 'propagar' repara las celdas que
-- perdieron una etiqueta. Cada etiqueta cruza la conexión de la vecina hacia
-- la celda, con el mismo costo que usa 'propagar'.
semillasDeVecinas :: Mapa -> IntMap Mejores -> [Int] -> [(CeldaId, Etiqueta)]
semillasDeVecinas mapa m destinos =
  [ (CeldaId c, e { etDistancia = etDistancia e .+. max (Fijo 0) (connCosto con) })
  | c <- destinos
  , (CeldaId u, _) <- IntMap.findWithDefault [] c (mapaVecinos mapa)
  , Just mu <- [IntMap.lookup u m]
  , (CeldaId x, con) <- IntMap.findWithDefault [] u (mapaVecinos mapa), x == c
  , e <- listaMejores mu ]

-- * Asignación de celdas

-- | A qué asentamiento trabaja cada celda (documento funcional, sección 8):
--
-- > asig(c) = argmin_a (d(c, celda(a)), id(a))   con d ≤ R_prod
--
-- d es el costo del camino por el grafo, que equivale a los km entre un punto
-- y otro (5 en tierra, más por mar). Cada celda recibe el asentamiento más
-- cercano; el empate lo rompe el id menor. Las celdas a más de @radio@ de todo
-- asentamiento no aparecen en el resultado. Es derivado: se recalcula, no se
-- guarda. Un asentamiento cuya celda no está en el mapa se ignora; si dos
-- comparten celda, gana el de id menor.
--
-- Es el recorrido con un grupo por asentamiento y una sola etiqueta por celda.
asignarCeldas :: Fijo -> Grafo -> [(AsentId, CeldaId)] -> IntMap AsentId
asignarCeldas radio gr fuentes =
  IntMap.map (AsentId . etGrupo . primera)
    (propagarGrafo UnGrupo (Just radio) gr
       [ (c, Etiqueta (Fijo 0) a a) | (AsentId a, c) <- fuentes ])
