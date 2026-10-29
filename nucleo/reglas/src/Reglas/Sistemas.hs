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

-- | La hacienda por veintena, igual que `step` del prototipo: el ingreso de
-- la población menos el gasto del presupuesto, dividido entre las veintenas
-- del año, y el tesoro no baja de cero. Es el único sistema que escribe el
-- tesoro, así que el orden de sus sumas no importa.
hacienda :: Constantes -> Sistema Purepecha
hacienda c = Sistema
  { sisNombre   = NombreSistema "hacienda"
  , sisCadencia = Periodo
  , sisLee      = Set.empty
  , sisEscribe  = Set.singleton magTesoro
  , sisEjecutar = \_ est ->
      let p      = persistenteJuego (estadoPersistente est)
          t      = ppTasas p
          pres   = ppPresupuesto p
          ingreso = foldl' (\acc pop ->
                      acc .+. ingresoPoblacion c t (capitalDe p pop) (popTamano pop))
                    (Fijo 0) (Map.elems (ppPops p))
          gasto  = gastoPunto c (pbEjercito pres + pbAdministracion pres + pbDiplomacia pres)
          neto   = (ingreso .-. gasto) ./. cTicksPorAnio c
          com    = persistenteComun (estadoPersistente est)
          ajustar x = x { almacenBase =
                            rangoFijo (minMag rangoTesoro) (maxMag rangoTesoro)
                                      (almacenBase x .+. neto) }
          alm'   = Map.adjust ajustar (entFaccion, magTesoro) (comunMagnitudes com)
          com'   = com { comunMagnitudes = alm' }
          est'   = est { estadoPersistente = (estadoPersistente est)
                          { persistenteComun = com' } }
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
