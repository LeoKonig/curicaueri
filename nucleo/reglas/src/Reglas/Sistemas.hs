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

-- | La hacienda por veintena, igual que `step` del prototipo, para cada
-- facción activa: el ingreso de la población de sus altépetl, por la
-- producción de cada uno, menos el gasto de su presupuesto, dividido entre
-- las veintenas del año, y el tesoro no baja de cero. Los sacerdotes no tributan (por verificar con la *Relación de
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
          efs    = eficiencias c p
          fps    = factoresProduccion est
          -- Una sola pasada por los pops: el ingreso de cada facción es la
          -- suma de los de sus altépetl (los de una facción que no está activa
          -- no cuentan).
          ingresoDe pop = case Map.lookup (popAltepetl pop) (ppAltepetl p) >>= \a -> Map.lookup (altFaccion a) (ppFacciones p) of
            Just f | facEstado f == Activa ->
              Just (facId f, ingresoPoblacion c (facTasas f) (capitalDe p pop)
                                (Map.findWithDefault (Fijo 0) (popAltepetl pop) efs)
                                (popTamano pop)
                              .*. Map.findWithDefault baseProduccionAlt (popAltepetl pop) fps)
            _ -> Nothing
          ingresos = Map.fromListWith (.+.)
            [ i | pop <- Map.elems (ppPops p), popEstrato pop /= estratoSacerdote, Just i <- [ingresoDe pop] ]
          enObra = Set.fromList [ altFaccion a | a <- Map.elems (ppAltepetl p), isJust (altObra a) ]
          neto f = let pres  = facPresupuesto f
                       gasto = gastoPunto c (pbEjercito pres + pbAdministracion pres + pbDiplomacia pres
                                             + (if Set.member (facId f) enObra then pbObras pres else 0))
                   in (Map.findWithDefault (Fijo 0) (facId f) ingresos .-. gasto) ./. cTicksPorAnio c
          com    = persistenteComun (estadoPersistente est)
          ajustar n x = x { almacenBase =
                              rangoFijo (minMag rangoTesoro) (maxMag rangoTesoro)
                                        (almacenBase x .+. n) }
          alm'   = foldl' (\a f -> Map.adjust (ajustar (neto f)) (entFac (facId f), magTesoro) a)
                          (comunMagnitudes com) (activas p)
          com'   = com { comunMagnitudes = alm' }
          est'   = est { estadoPersistente = (estadoPersistente est)
                          { persistenteComun = com' } }
      in (est', [])
  }

-- | Las tasas de la facción de un altépetl; las neutras si no la tiene.
tasasDe :: Constantes -> Purepecha -> Altepetl -> Tasas
tasasDe c p a = maybe (Tasas (cNeutralTasa c) (cNeutralTasa c)) facTasas (Map.lookup (altFaccion a) (ppFacciones p))

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
          alts = ppAltepetl p
          pops = ppPops p
          tasas = Map.mapWithKey (\k _ -> valorDeAlt est rangoTasaAgravio (Fijo 0) magTasaAgravio k) alts
          delta pid = case Map.lookup pid pops of
            Just pop -> case Map.lookup (popAltepetl pop) alts of
              Just a  -> deltaAgravio c (popParts c (tasasDe c p a) (isNothing (altSujetoA a))
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
