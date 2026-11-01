{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | La crónica del reino y el fin de la partida.
--
-- La crónica es un registro de solo añadir, parte del estado almacenado: al
-- final de cada tick, los hechos cuyo tipo aparece en la tabla del guion
-- (@cronica@) pasan a ser entradas, con su tick, sus entidades, sus parámetros
-- y la clave de localización que dice cómo contarlos. Qué cuenta como
-- importante es un dato del escenario, no del motor.
--
-- El fin de la partida también lo declara el guion (@fin@): una fecha, o una
-- condición de derrota con su razón. Al cumplirse, el estado guarda el fin y
-- emite el hecho @fin_partida@; una partida terminada ya no avanza.
--
-- Ver V5, *La crónica del reino* e *Interfaz, IA y fin de partida*.
module Motor.Cronica
  ( terminada
  , pasoCronica
  , pasoFin
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import Data.Sequence ((><))
import qualified Data.Sequence as Seq

import Motor.Base
import Motor.Director (evaluar)
import Motor.Estado
import Motor.Guion
import Motor.Hechos
import Motor.Magnitudes

conComun :: (Comun s -> Comun s) -> Estado s -> Estado s
conComun f e =
  let p = estadoPersistente e
  in e { estadoPersistente = p { persistenteComun = f (persistenteComun p) } }

-- | ¿Ya terminó la partida?
terminada :: Estado s -> Bool
terminada = isJust . comunFin . persistenteComun . estadoPersistente

-- | Añade a la crónica una entrada por cada hecho cuyo tipo está en la tabla
-- del guion, en el orden en que ocurrieron. Solo añade: nunca quita ni cambia
-- lo que ya estaba.
pasoCronica :: Guion -> [Hecho] -> Estado s -> Estado s
pasoCronica g hs e
  | null nuevas = e
  | otherwise = conComun (\c -> c { comunCronica = comunCronica c >< Seq.fromList nuevas }) e
  where
    nuevas =
      [ EntradaCronica (hechoTick h) (hechoTipo h) (hechoEntidades h) clave (hechoParams h)
      | h <- hs, Just clave <- [Map.lookup (hechoTipo h) (guCronica g)] ]

-- | Al final del tick: si el guion declara un fin y se cumple, la partida
-- termina. Una condición de derrota gana a la fecha si las dos se cumplen el
-- mismo día, y entre las derrotas gana la primera. Una partida ya terminada no
-- vuelve a terminar.
pasoFin :: Map Magnitud DefMagnitud -> Guion -> Tick -> Estado s -> (Estado s, [Hecho])
pasoFin cat g t@(Tick tt) e = case guFin g of
  Just f | not (terminada e), Just r <- razon f ->
    ( conComun (\c -> c { comunFin = Just (FinPartida t r) }) e
    , [Hecho "fin_partida" t [] (Map.fromList [("razon", r)])] )
  _ -> (e, [])
  where
    razon f = case [ r | (r, c) <- fgDerrotas f, evaluar cat e c ] of
      (r : _) -> Just r
      []      -> case fgTick f of
        Just n | tt >= n -> Just "fecha"
        _                -> Nothing
