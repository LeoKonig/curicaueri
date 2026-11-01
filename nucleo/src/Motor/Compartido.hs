{-# LANGUAGE MagicHash #-}
-- | Diferencias entre estructuras persistentes que comparten lo que no
-- cambió (CLAUDE.md, *Pensado para el juego completo*).
--
-- Un tick toca pocas entidades y deja el resto del mapa tal cual: el árbol
-- nuevo comparte con el viejo todos los subárboles por los que no pasó una
-- inserción. 'clavesCambiadas' recorre los dos árboles a la vez y salta los
-- subárboles que son el mismo objeto en memoria, así que cuesta lo que
-- cambió (por log n), no el tamaño del mapa.
--
-- La igualdad de punteros es solo un atajo: si dice «el mismo», los valores
-- son iguales; si dice «distinto», se comparan con '=='. El resultado no
-- depende de lo que diga (ver la ley en las pruebas), así que el atajo no
-- rompe el determinismo: a lo sumo cuesta más.
module Motor.Compartido
  ( clavesCambiadas
  , mismoObjeto
  ) where

import Data.Map.Internal (Map (..))
import qualified Data.Map.Internal as MI
import GHC.Exts (isTrue#, reallyUnsafePtrEquality#)

-- | ¿Son el mismo objeto en memoria? Verdadero implica iguales; falso no
-- implica nada.
mismoObjeto :: a -> a -> Bool
mismoObjeto x y = isTrue# (reallyUnsafePtrEquality# x y)
{-# INLINE mismoObjeto #-}

-- | Las claves cuyo valor difiere entre los dos mapas, o que están en uno
-- solo, en orden ascendente. Equivale a
--
-- > [ k | k <- Set.toList (keysSet a ∪ keysSet b), lookup k a /= lookup k b ]
--
-- pero salta los subárboles compartidos. Parte el segundo árbol por la raíz
-- del primero: cuando los dos tienen la misma forma, 'MI.splitLookup'
-- devuelve los hijos tal cual y la comparación sigue saltando.
clavesCambiadas :: (Ord k, Eq v) => Map k v -> Map k v -> [k]
clavesCambiadas a0 b0 = ir a0 b0 []
  where
    ir a b acc
      | mismoObjeto a b = acc
    ir Tip b acc = MI.foldrWithKey (\k _ r -> k : r) acc b
    ir a Tip acc = MI.foldrWithKey (\k _ r -> k : r) acc a
    ir (Bin _ k x l r) b acc =
      let (lb, mx, rb) = MI.splitLookup k b
          derecha = ir r rb acc
          aqui = case mx of
                   Just y | mismoObjeto x y || x == y -> derecha
                   _                                   -> k : derecha
      in ir l lb aqui
