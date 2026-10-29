{-# LANGUAGE StrictData #-}
module Reglas.Sistemas where

import Data.List (foldl')
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing)
import qualified Data.Set as Set

import Motor.Base
import Motor.Estado
import Motor.Magnitudes
import Motor.Sistema
import Reglas.Base
import Reglas.Constantes
import Reglas.Estado
import Reglas.Formulas

-- | ¿Es capital el altépetl del poblador? Una capital no está sujeta a otro.
capitalDe :: Purepecha -> Pop -> Bool
capitalDe p pop =
  maybe False (isNothing . altSujetoA) (Map.lookup (popAltepetl pop) (ppAltepetl p))

-- | El ingreso de la faccion por veintena: la suma de `ingresoPoblacion` de
-- cada poblador, dividida entre las veintenas del año. El tributo de las
-- sujetas pasa a la capital, así que el total no depende del reparto.
recaudacion :: Constantes -> Sistema Purepecha
recaudacion c = Sistema
  { sisNombre   = NombreSistema "recaudacion"
  , sisCadencia = Periodo
  , sisLee      = Set.empty
  , sisEscribe  = Set.empty   -- solo toca `ppFaccion`, no magnitudes
  , sisEjecutar = \_ est ->
      let p    = persistenteJuego (estadoPersistente est)
          t    = ppTasas p
          anual = foldl' (\acc pop ->
                    acc .+. ingresoPoblacion c t (capitalDe p pop) (popTamano pop))
                  (Fijo 0) (Map.elems (ppPops p))
          fac  = ppFaccion p
          fac' = fac { facTesoro = facTesoro fac .+. (anual ./. cTicksPorAnio c) }
          p'   = p { ppFaccion = fac' }
          est' = est { estadoPersistente = (estadoPersistente est)
                        { persistenteJuego = p' } }
      in (est', [])
  }

-- | El gasto del presupuesto por veintena. Obras no cuesta nada todavía: en
-- el prototipo solo corre con edificios, y 1b no los tiene. El ejército
-- tampoco suma soldados (`mantenimiento_por_soldado`) porque 1b no los cuenta.
pago :: Constantes -> Sistema Purepecha
pago c = Sistema
  { sisNombre   = NombreSistema "pago"
  , sisCadencia = Periodo
  , sisLee      = Set.empty
  , sisEscribe  = Set.empty
  , sisEjecutar = \_ est ->
      let p    = persistenteJuego (estadoPersistente est)
          pres = ppPresupuesto p
          anual = gastoPunto c (pbEjercito pres + pbAdministracion pres + pbDiplomacia pres)
          fac  = ppFaccion p
          fac' = fac { facTesoro = max (Fijo 0) (facTesoro fac .-. (anual ./. cTicksPorAnio c)) }
          p'   = p { ppFaccion = fac' }
          est' = est { estadoPersistente = (estadoPersistente est)
                        { persistenteJuego = p' } }
      in (est', [])
  }

-- | El agravio de cada poblador sube o baja por veintena según `popParts`
-- (`deltaAgravio`), acotado a 0..100.
evolucionAgravio :: Constantes -> Sistema Purepecha
evolucionAgravio c = Sistema
  { sisNombre   = NombreSistema "evolucion_agravio"
  , sisCadencia = Periodo
  , sisLee      = Set.empty
  , sisEscribe  = Set.singleton (Magnitud "agravio")
  , sisEjecutar = \_ est ->
      let p    = persistenteJuego (estadoPersistente est)
          t    = ppTasas p
          alts = ppAltepetl p
          pops = ppPops p
          delta pid = case Map.lookup pid pops of
            Just pop -> case Map.lookup (popAltepetl pop) alts of
              Just a  -> deltaAgravio c (popParts c t (isNothing (altSujetoA a))
                                            (popEstrato pop) (popIdentidad pop)
                                            (altDistancia a))
              Nothing -> Fijo 0
            Nothing  -> Fijo 0
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
