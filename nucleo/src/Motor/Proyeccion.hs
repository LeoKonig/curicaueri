{-# LANGUAGE StrictData, TypeFamilies #-}
module Motor.Proyeccion where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Motor.Base
import Motor.Estado
import Motor.Juego
import Motor.Magnitudes
import Motor.Vista
import Data.Text (Text)

proyeccion :: Juego s c -> Estado s -> Vista
proyeccion j est = Vista t (Map.fromList [(evRef ev, ev) | ev <- evs])
  where
    t        = estadoTick est
    alm      = comunMagnitudes (persistenteComun (estadoPersistente est))
    catalogo = juegoCatalogoMag j
    ejJuego  = juegoProyectar j est
    evs      = map (completar t alm catalogo) ejJuego

-- | Solo se proyectan los modificadores activos en el tick de la vista.
completar :: Tick -> Almacen -> Map Magnitud DefMagnitud -> EntidadJuego -> EntidadVista
completar t alm catalogo ej =
  EntidadVista (ejRef ej) (ejCampos ej) mags
  where
    ref  = ejRef ej
    mags = Map.fromList
      [ (m, magnitudVista dm (almacenBase x) (filter (activoEn t) (almacenMods x)))
      | ((r, m), x) <- Map.toList alm
      , r == ref
      , Just dm <- [Map.lookup m catalogo]
      ]

magnitudVista :: DefMagnitud -> Fijo -> [Modificador] -> MagnitudVista
magnitudVista dm base mods =
  MagnitudVista
    { mvBase     = base
    , mvAportes  = map aAporteVista mods
    , mvEfectivo = valorEfectivo (dmRango dm) base mods
    }

aAporteVista :: Modificador -> AporteVista
aAporteVista m =
  AporteVista
    { avFuente     = ClaveLoc (fuenteTipo (modFuente m))
    , avArgumentos = [VTexto (fuenteRef (modFuente m))]
    , avAporte     = modAporte m
    , avVence      = modFin m
    }

-- ---------------------------------------------------------------------------
-- Cambios: referencia, optimizada y punto de entrada
-- ---------------------------------------------------------------------------

-- | Implementación de referencia: compara cada entidad de vNew contra vOld.
-- Correcta por construcción; recorre todas las entidades.
cambiosRef :: Vista -> Vista -> Cambios
cambiosRef vOld vNew =
  Cambios
    { cTick         = vTick vNew
    , cActualizadas = [ ev
                      | (r, ev) <- Map.toList (vEntidades vNew)
                      , Map.lookup r (vEntidades vOld) /= Just ev ]
    , cEliminadas   = [ r
                      | r <- Map.keys (vEntidades vOld)
                      , not (Map.member r (vEntidades vNew)) ]
    }

-- | Implementación optimizada: solo visita las entidades marcadas como
-- sucias y emite las que además cambiaron. El registro de sucias debe ser
-- un superconjunto de las entidades cuya proyección cambió.
cambiosOpt :: Set EntRef -> Vista -> Vista -> Cambios
cambiosOpt sucias vOld vNew =
  Cambios
    { cTick         = vTick vNew
    , cActualizadas = [ ev
                      | r <- Set.toList sucias
                      , Just ev <- [Map.lookup r (vEntidades vNew)]
                      , Map.lookup r (vEntidades vOld) /= Just ev ]
    , cEliminadas   = [ r
                      | r <- Map.keys (vEntidades vOld)
                      , not (Map.member r (vEntidades vNew)) ]
    }

-- | Todas las entidades visibles en una vista. Es lo que el motor pasa por
-- defecto cuando no tiene un registro real del tick.
todasLasEntidades :: Vista -> Set EntRef
todasLasEntidades = Map.keysSet . vEntidades

-- | Punto de entrada del motor. En Hito 1a el registro es "todas", así que
-- el resultado coincide exactamente con la referencia. En Hito 2 el motor
-- pasará el registro de sucias que mantenga durante el tick.
cambios :: Vista -> Vista -> Cambios
cambios vOld vNew = cambiosOpt (todasLasEntidades vNew) vOld vNew

-- | Aplica cambios a una vista: reemplaza entidades, no fusiona campos.
aplicar :: Vista -> Cambios -> Vista
aplicar v c =
  let sinElim  = foldr Map.delete (vEntidades v) (cEliminadas c)
      conNuevas = foldr (\ev m -> Map.insert (evRef ev) ev m)
                        sinElim (cActualizadas c)
  in Vista (cTick c) conNuevas

-- | Una diferencia visible entre dos vistas: un campo o el valor efectivo de
-- una magnitud de una entidad. Es lo que muestra la predicción de un comando.
data Diferencia = Diferencia
  { dRef     :: EntRef
  , dNombre  :: Text          -- ^ nombre del campo o de la magnitud
  , dEsMagnitud :: Bool
  , dAntes   :: Maybe ValorVista
  , dDespues :: Maybe ValorVista
  } deriving (Eq, Show)

-- | Diferencias de b respecto de a, en orden de entidad y nombre.
diferencias :: Vista -> Vista -> [Diferencia]
diferencias a b =
  [ d
  | r <- Set.toList (Map.keysSet (vEntidades a) `Set.union` Map.keysSet (vEntidades b))
  , let ea = Map.lookup r (vEntidades a)
        eb = Map.lookup r (vEntidades b)
        campos e = maybe Map.empty evCampos e
        mags e = maybe Map.empty (Map.map (VFijo . mvEfectivo) . Map.mapKeys (\(Magnitud n) -> n) . evMagnitudes) e
  , d <- [ Diferencia r n False x y | (n, x, y) <- pares (campos ea) (campos eb) ]
      ++ [ Diferencia r n True x y | (n, x, y) <- pares (mags ea) (mags eb) ]
  ]
  where
    pares ma mb = [ (n, Map.lookup n ma, Map.lookup n mb)
                  | n <- Set.toList (Map.keysSet ma `Set.union` Map.keysSet mb)
                  , Map.lookup n ma /= Map.lookup n mb ]
