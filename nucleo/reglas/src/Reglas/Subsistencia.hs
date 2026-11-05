{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Subsistencia: la gente come antes de tributar (V5, *Comer antes de
-- tributar*; documento funcional, sección 12, *Subsistencia y cobertura*;
-- hito 3).
--
-- La producción reparte el maíz al cosecharlo: la cuota de tributo en especie
-- va a las trojes de la facción y el resto se queda en el altépetl, en
-- @cosechado@. Al cerrarse la ventana de cosecha, una vez por año, cada
-- altépetl cuenta su __cobertura__: qué parte de la ración de su gente cubre
-- lo que tiene,
--
-- > necesidad    = ración · Σ N_p
-- > disponible   = cosechado + reserva
-- > cobertura    = min(1, disponible / necesidad)
-- > reserva'     = min(necesidad, max(0, disponible − necesidad))
--
-- y vacía @cosechado@. La reserva local se estropea cada periodo con la merma
-- del maíz (la efectiva de la facción, con sus trojes). La cobertura vale
-- hasta la siguiente cosecha: el agravio ('Reglas.Sistemas.evolucionAgravio') y
-- la hacienda la leen cada veintena. Bajo 'cUmbralHambre' el cierre emite el
-- hecho @hambre@.
--
-- Este sistema es el único que escribe la base de @cobertura@ en el cierre; el
-- efecto @repartir_bien@ ('Reglas.Propios') también escribe @cobertura@ y
-- @reserva@, y por eso las dos están declaradas con varios escritores.
-- Antes del hito 6 nadie muere de hambre ni el hambre baja la producción.
-- Sin ventana de cosecha del maíz no hay subsistencia: la cobertura es 1.
module Reglas.Subsistencia
  ( subsistencia
  , necesidades
  , necesidadDe
  , cierreAnio
  , coberturaEn
  , reservaEn
  , mostrarFijo
  ) where

import qualified Data.Aeson as A
import Data.List (foldl')
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Estado
import Motor.Hechos
import Motor.Magnitudes
import Motor.Moneda (Economia (..), magMerma, mermaEn)
import Motor.Sistema
import Reglas.Base
import Reglas.Constantes
import Reglas.Estado
import Reglas.Produccion (Cosechas (..), cierraVentana)

-- | Lo que come la gente de cada altépetl en un año: la ración por persona
-- por el tamaño de todos sus pops (también la nobleza y los sacerdotes), en
-- una sola pasada por los pops.
necesidades :: Constantes -> Purepecha -> Map AltId Fijo
necesidades c p = Map.map (\n -> fi n .*. cRacionMaiz c) $
  Map.fromListWith (+) [ (popAltepetl pop, popTamano pop) | pop <- Map.elems (ppPops p) ]

-- | La necesidad de un solo altépetl (recorre los pops: para un efecto, no
-- para un sistema que pasa por todos).
necesidadDe :: Constantes -> Purepecha -> AltId -> Fijo
necesidadDe c p a = fi (sum [ popTamano pop | pop <- Map.elems (ppPops p), popAltepetl pop == a ]) .*. cRacionMaiz c

-- | El cierre del año de un altépetl, función pura de la necesidad, lo
-- cosechado y la reserva (esta ya con la merma del periodo):
-- @(cobertura, reserva', perdido)@. Se cumple
--
-- > cosechado + reserva = comido + reserva' + perdido,   comido = min(necesidad, disponible)
--
-- y @perdido@ es lo que no cabe en el tope de la reserva (se pudre o se
-- intercambia fuera del modelo). Sin gente que alimentar la cobertura es 1.
cierreAnio :: Fijo -> Fijo -> Fijo -> (Fijo, Fijo, Fijo)
cierreAnio need cosechado reserva =
  let disponible = cosechado .+. reserva
      cob | need <= Fijo 0 = uno
          | otherwise      = min uno (disponible ./. need)
      comido = min need disponible
      resto = disponible .-. comido
      reserva' = min need resto
  in (cob, reserva', resto .-. reserva')

-- | La cobertura efectiva del altépetl; 1 si nada la ha escrito (sin datos de
-- producción, o antes del primer cierre).
coberturaEn :: Estado Purepecha -> AltId -> Fijo
coberturaEn est a = maybe uno (valorEn (derivadoVigentes (estadoDerivado est)) (estadoTick est) rangoCobertura)
  (Map.lookup (entRefAlt a, magCobertura) (comunMagnitudes (persistenteComun (estadoPersistente est))))

-- | La reserva local del altépetl; 0 si nada la ha escrito.
reservaEn :: Estado Purepecha -> AltId -> Fijo
reservaEn est a = maybe (Fijo 0) almacenBase
  (Map.lookup (entRefAlt a, magReserva) (comunMagnitudes (persistenteComun (estadoPersistente est))))

mostrarFijo :: Fijo -> Text
mostrarFijo x = case A.toJSON x of
  A.String t -> t
  otro       -> T.pack (show otro)

-- | El sistema de subsistencia (paso 7, cada periodo). Lee @cosechado@
-- (lo escribe la producción, que corre antes) y la merma del maíz; escribe la
-- reserva cada periodo y, en el periodo que cierra la ventana de cosecha, la
-- cobertura del año y el hecho @hambre@. Un cálculo por altépetl y periodo,
-- y solo se escribe lo que cambia.
subsistencia :: Constantes -> Economia -> Cosechas -> Sistema Purepecha
subsistencia c ec temporadas = Sistema
  { sisNombre   = NombreSistema "subsistencia"
  , sisCadencia = Periodo
  , sisLee      = Set.fromList [magCosechado, magMerma bienAlimento]
  , sisEscribe  = Set.fromList [magCosechado, magReserva, magCobertura]
  , sisEjecutar = \_ est -> case Map.lookup bienAlimento (csVentanas temporadas) of
      Nothing -> (est, [])
      Just co ->
        let p    = persistenteJuego (estadoPersistente est)
            com  = persistenteComun (estadoPersistente est)
            alm0 = comunMagnitudes com
            vig  = derivadoVigentes (estadoDerivado est)
            t    = estadoTick est
            cierra = cierraVentana (comunCalendario com) temporadas co t
            need = if cierra then necesidades c p else Map.empty
            merma f = maybe (Fijo 0) (mermaEn vig t alm0 (entFac f)) (Map.lookup bienAlimento (ecoBienes ec))
            base m a = maybe (Fijo 0) almacenBase (Map.lookup (entRefAlt a, m) alm0)
            paso (alm, hs) alt =
              case Map.lookup (altFaccion alt) (ppFacciones p) of
                Just fa | facEstado fa == Activa ->
                  let a = altId alt
                      r0 = base magReserva a
                      r1 = r0 .*. (uno .-. merma (altFaccion alt))
                  in if not cierra
                       then (if r1 /= r0 then fijarBase (entRefAlt a) magReserva r1 alm else alm, hs)
                       else
                         let n = Map.findWithDefault (Fijo 0) a need
                             h = base magCosechado a
                             (cob, r', _) = cierreAnio n h r1
                             alm1 = fijarBase (entRefAlt a) magCosechado (Fijo 0)
                                      (fijarBase (entRefAlt a) magReserva r'
                                        (fijarBase (entRefAlt a) magCobertura cob alm))
                             hecho = Hecho "hambre" t [entRefAlt a, entFac (altFaccion alt)]
                                       (Map.fromList [ ("cobertura", mostrarFijo cob), ("necesidad", mostrarFijo n)
                                                     , ("cosechado", mostrarFijo h), ("reserva", mostrarFijo r1) ])
                         in (alm1, if cob < cUmbralHambre c then hecho : hs else hs)
                _ -> (alm, hs)
            (alm', hechos) = foldl' paso (alm0, []) (Map.elems (ppAltepetl p))
        in ( est { estadoPersistente = (estadoPersistente est) { persistenteComun = com { comunMagnitudes = alm' } } }
           , reverse hechos )
  }
