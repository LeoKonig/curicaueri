{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Lo que el juego añade al lenguaje del guion: condiciones y efectos
-- propios, que el motor llama por nombre sin saber qué hacen (documento
-- funcional, secciones 1 y 11).
--
-- Una condición o un efecto propio se escribe en el guion como cualquier
-- otro (@{"tipo": "faccion_activa", "faccion": 2}@). Al cargar, el motor ve
-- que el tipo no es suyo, lo busca en el 'Vocabulario' del juego y le pide
-- que valide el objeto: un nombre desconocido o un argumento mal escrito es
-- un error de carga, no una sorpresa en el tick 47. En el guion queda
-- defuncionalizado, como la continuación de una decisión: el nombre y el
-- objeto ya validado. Al evaluarlo, el juego vuelve a leer el objeto con el
-- mismo lector, que ya no puede fallar.
--
-- Así el guion no depende del tipo del estado del juego y se sigue cargando
-- antes que el juego, como el mapa.
module Motor.Propios
  ( -- * Condiciones y efectos propios
    CondicionPropia (..)
  , EfectoPropio (..)
  , condicionPropia
  , efectoPropio
    -- * El lenguaje que ve el director
  , Lenguaje (..)
  , lenguajeBasico
  , lecturaDe
  , evaluarEn
    -- * Lo que necesita la carga
  , Vocabulario (..)
  , vocabularioVacio
  , vocabularioDe
  ) where

import Data.Aeson (Value)
import qualified Data.Aeson.Types as A
import Data.IntSet (IntSet)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Estado
import Motor.Hechos
import Motor.Magnitudes

-- | Una condición del juego: cómo se validan sus argumentos al cargar y cómo
-- se evalúa sobre el estado persistente. Lee solo lo persistente para que
-- también sirva en los modificadores condicionales, cuya vigencia es una
-- función pura de (t, persistente) (ley del derivado reproducible).
data CondicionPropia s = CondicionPropia
  { cpValidar :: Value -> Either Text ()
  , cpEvaluar :: Value -> Persistente s -> Bool
  }

-- | Un efecto del juego: cómo se validan sus argumentos al cargar y cómo se
-- aplica. Un 'Left' es un rechazo sin daño: la opción entera no se aplica
-- y la respuesta vuelve con el motivo.
data EfectoPropio s = EfectoPropio
  { epValidar :: Value -> Either Text ()
  , epAplicar :: Value -> Estado s -> Either Text (Estado s, [Hecho])
  }

-- | Una condición propia a partir de un solo lector de sus argumentos: la
-- validación es que el lector no falle, y la evaluación usa lo que lee.
condicionPropia :: (Value -> A.Parser a) -> (a -> Persistente s -> Bool) -> CondicionPropia s
condicionPropia leer evaluar = CondicionPropia
  { cpValidar = \v -> either (Left . T.pack) (const (Right ())) (A.parseEither leer v)
  , cpEvaluar = \v p -> either (const False) (`evaluar` p) (A.parseEither leer v)
  }

-- | Un efecto propio a partir de un solo lector de sus argumentos.
efectoPropio :: (Value -> A.Parser a) -> (a -> Estado s -> Either Text (Estado s, [Hecho])) -> EfectoPropio s
efectoPropio leer aplicar = EfectoPropio
  { epValidar = \v -> either (Left . T.pack) (const (Right ())) (A.parseEither leer v)
  , epAplicar = \v e -> either (Left . T.pack) (`aplicar` e) (A.parseEither leer v)
  }

-- | Lo que el director necesita del juego para evaluar condiciones y
-- aplicar opciones: el catálogo de magnitudes (para acotar lo que lee) y las
-- condiciones y los efectos propios.
data Lenguaje s = Lenguaje
  { leCatalogo    :: Map Magnitud DefMagnitud
  , leCondiciones :: Map Text (CondicionPropia s)
  , leEfectos     :: Map Text (EfectoPropio s)
  }

-- | Un lenguaje sin nada propio: el de un juego que solo usa el del motor.
lenguajeBasico :: Map Magnitud DefMagnitud -> Lenguaje s
lenguajeBasico cat = Lenguaje cat Map.empty Map.empty

-- | Lo que lee una condición en el día @t@, con los modificadores
-- condicionales @vig@, sobre el estado persistente @p@.
lecturaDe :: Lenguaje s -> IntSet -> Tick -> Persistente s -> LecturaCond
lecturaDe le vig t p = LecturaCond
  { lcCatalogo  = leCatalogo le
  , lcVigentes  = vig
  , lcTick      = t
  , lcAlmacen   = comunMagnitudes c
  , lcOcurridos = comunOcurridos c
  , lcPropia    = \n v -> maybe False (\cp -> cpEvaluar cp v p) (Map.lookup n (leCondiciones le))
  }
  where c = persistenteComun p

-- | La condición, evaluada en el estado con los modificadores vigentes de su
-- derivado.
evaluarEn :: Lenguaje s -> Estado s -> Condicion -> Bool
evaluarEn le e = evaluarCondicion (lecturaDe le (derivadoVigentes (estadoDerivado e)) (estadoTick e) (estadoPersistente e))

-- | Los nombres de las condiciones y los efectos propios con sus
-- validadores: lo único que la carga del guion necesita del juego. No
-- depende del tipo del estado.
data Vocabulario = Vocabulario
  { voCondiciones :: Map Text (Value -> Either Text ())
  , voEfectos     :: Map Text (Value -> Either Text ())
  }

vocabularioVacio :: Vocabulario
vocabularioVacio = Vocabulario Map.empty Map.empty

vocabularioDe :: Lenguaje s -> Vocabulario
vocabularioDe le = Vocabulario (Map.map cpValidar (leCondiciones le)) (Map.map epValidar (leEfectos le))
