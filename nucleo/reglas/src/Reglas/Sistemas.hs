{-# LANGUAGE StrictData #-}
module Reglas.Sistemas where

import Data.List (foldl')
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import Motor.Base
import Motor.Estado
import Motor.Magnitudes
import Motor.Sistema
import Reglas.Base
import Reglas.Constantes
import Reglas.Estado

-- | Factor multiplicativo de las tasas respecto a la neutral.
tasaFactor :: Constantes -> Tasas -> Fijo
tasaFactor c t =
  let d = (tasaTributo t - cNeutralTasa c) + (tasaImpuesto t - cNeutralTasa c)
  in uno .+. fiD 1 .*. fi d     -- 1 + 0.1 · d

recaudacion :: Constantes -> Sistema Purepecha
recaudacion c = Sistema
  { sisNombre   = NombreSistema "recaudacion"
  , sisCadencia = Periodo
  , sisLee      = Set.empty
  , sisEscribe  = Set.empty   -- solo toca `ppFaccion`, no magnitudes
  , sisEjecutar = \_ est ->
      let p   = persistenteJuego (estadoPersistente est)
          inp = foldl' (\acc pop ->
                  acc .+. cIngresoPorPop c .*. fi (popTamano pop)
                       .*. tasaFactor c (ppTasas p))
                (Fijo 0) (Map.elems (ppPops p))
          fac  = ppFaccion p
          fac' = fac { facTesoro = facTesoro fac .+. inp }
          p'   = p { ppFaccion = fac' }
          est' = est { estadoPersistente = (estadoPersistente est)
                        { persistenteJuego = p' } }
      in (est', [])
  }

pago :: Constantes -> Sistema Purepecha
pago c = Sistema
  { sisNombre   = NombreSistema "pago"
  , sisCadencia = Periodo
  , sisLee      = Set.empty
  , sisEscribe  = Set.empty
  , sisEjecutar = \_ est ->
      let p    = persistenteJuego (estadoPersistente est)
          pres = ppPresupuesto p
          gasto = cMantenimientoEjercito c .*. fi (pbEjercito pres)
                .+. cMantenimientoAdmin c .*. fi (pbAdministracion pres)
          fac  = ppFaccion p
          fac' = fac { facTesoro = max (Fijo 0) (facTesoro fac .-. gasto) }
          p'   = p { ppFaccion = fac' }
          est' = est { estadoPersistente = (estadoPersistente est)
                        { persistenteJuego = p' } }
      in (est', [])
  }

evolucionAgravio :: Constantes -> Sistema Purepecha
evolucionAgravio c = Sistema
  { sisNombre   = NombreSistema "evolucion_agravio"
  , sisCadencia = Periodo
  , sisLee      = Set.empty
  , sisEscribe  = Set.singleton (Magnitud "agravio")
  , sisEjecutar = \_ est ->
      let p    = persistenteJuego (estadoPersistente est)
          t    = ppTasas p
          dT   = tasaTributo t  - cNeutralTasa c
          dI   = tasaImpuesto t - cNeutralTasa c
          fs   = formulasAgravio c
          dT'  = maybe (Fijo 0) ($ dT) (Map.lookup "agravio_por_tributo" fs)
          dI'  = maybe (Fijo 0) ($ dI) (Map.lookup "agravio_por_impuesto" fs)
          pops = ppPops p
          delta pid = case Map.lookup pid pops of
            Just pop -> (dT' .+. dI') .*. estratoW pop
            Nothing  -> Fijo 0
          estratoW pop = if popEstrato pop == "nobleza" then fiD 5 else uno
          alm  = comunMagnitudes (persistenteComun (estadoPersistente est))
          upd (k@(r, Magnitud "agravio"), x) = case r of
            EntRef "pop" i ->
              let b' = rangoFijo (Fijo 0) (fi 100)
                                (almacenBase x .+. delta (PopId i))
              in (k, x { almacenBase = b' })
            _ -> (k, x)
          upd e = e
          alm' = Map.fromList (map upd (Map.toList alm))
          com  = persistenteComun (estadoPersistente est)
          com' = com { comunMagnitudes = alm' }
          est' = est { estadoPersistente = (estadoPersistente est)
                        { persistenteComun = com' } }
      in (est', [])
  }
