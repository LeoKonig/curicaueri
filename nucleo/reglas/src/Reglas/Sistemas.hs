{-# LANGUAGE StrictData #-}
module Reglas.Sistemas where

import Data.List (foldl')
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust, isNothing)
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

-- | El valor efectivo de una magnitud del altépetl en el tick del estado, con
-- los modificadores condicionales vigentes. Sin entrada en el almacén vale
-- @base@.
valorDeAlt :: Estado Purepecha -> RangoMag -> Fijo -> Magnitud -> AltId -> Fijo
valorDeAlt est r base m alt =
  maybe base (valorEn (derivadoVigentes (estadoDerivado est)) (estadoTick est) r)
    (Map.lookup (entRefAlt alt, m) (comunMagnitudes (persistenteComun (estadoPersistente est))))

-- | La producción de cada altépetl como factor (1 = 100 %): lo que suman sus
-- edificios (`incomeParts`: yácata × 1,1, fortaleza × 0,95; aquí los
-- porcentajes se suman).
factoresProduccion :: Estado Purepecha -> Map.Map AltId Fijo
factoresProduccion est =
  Map.mapWithKey (\k _ -> valorDeAlt est rangoProduccionAlt baseProduccionAlt magProduccionAlt k)
    (ppAltepetl (persistenteJuego (estadoPersistente est)))

-- | La hacienda por veintena, igual que `step` del prototipo: el ingreso de
-- la población, por la producción de su altépetl, menos el gasto del
-- presupuesto, dividido entre las veintenas del año, y el tesoro no baja de
-- cero. Los sacerdotes no tributan (por verificar con la *Relación de
-- Michoacán*; así el escenario conserva las cifras del prototipo, que no los
-- tiene). La partida de obras solo se paga mientras haya una obra en curso
-- (`expenseLines`). Es el único sistema que escribe la base del tesoro (el
-- comando de construir cobra al empezar), así que el orden de sus sumas no
-- importa.
hacienda :: Constantes -> Sistema Purepecha
hacienda c = Sistema
  { sisNombre   = NombreSistema "hacienda"
  , sisCadencia = Periodo
  , sisLee      = Set.singleton magProduccionAlt
  , sisEscribe  = Set.singleton magTesoro
  , sisEjecutar = \_ est ->
      let p      = persistenteJuego (estadoPersistente est)
          t      = ppTasas p
          pres   = ppPresupuesto p
          efs    = eficiencias c p
          fps    = factoresProduccion est
          ingreso = foldl' (\acc pop ->
                      acc .+. ingresoPoblacion c t (capitalDe p pop)
                                (Map.findWithDefault (Fijo 0) (popAltepetl pop) efs)
                                (popTamano pop)
                              .*. Map.findWithDefault baseProduccionAlt (popAltepetl pop) fps)
                    (Fijo 0) (filter ((/= estratoSacerdote) . popEstrato) (Map.elems (ppPops p)))
          enObra = any (isJust . altObra) (Map.elems (ppAltepetl p))
          gasto  = gastoPunto c (pbEjercito pres + pbAdministracion pres + pbDiplomacia pres
                                 + (if enObra then pbObras pres else 0))
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
-- (`deltaAgravio`) más la tasa de agravio de su altépetl (lo que restan sus
-- edificios: yácata −5 y troje −3 por año), acotado a 0..100.
evolucionAgravio :: Constantes -> Sistema Purepecha
evolucionAgravio c = Sistema
  { sisNombre   = NombreSistema "evolucion_agravio"
  , sisCadencia = Periodo
  , sisLee      = Set.singleton magTasaAgravio
  , sisEscribe  = Set.singleton (Magnitud "agravio")
  , sisEjecutar = \_ est ->
      let p    = persistenteJuego (estadoPersistente est)
          t    = ppTasas p
          alts = ppAltepetl p
          pops = ppPops p
          tasas = Map.mapWithKey (\k _ -> valorDeAlt est rangoTasaAgravio (Fijo 0) magTasaAgravio k) alts
          delta pid = case Map.lookup pid pops of
            Just pop -> case Map.lookup (popAltepetl pop) alts of
              Just a  -> deltaAgravio c (popParts c t (isNothing (altSujetoA a))
                                            (popEstrato pop) (popIdentidad pop)
                                            (altDistancia a)
                                            (adminDe p (altGobernador a)))
                         .+. Map.findWithDefault (Fijo 0) (altId a) tasas ./. cTicksPorAnio c
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
