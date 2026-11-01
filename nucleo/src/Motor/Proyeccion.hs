{-# LANGUAGE StrictData, TypeFamilies #-}
module Motor.Proyeccion where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Motor.Base
import Motor.Estado
import Motor.Juego
import Motor.Magnitudes
import Motor.Vista
import Data.IntSet (IntSet)
import Data.Text (Text)
import Motor.Compartido (clavesCambiadas)

proyeccion :: Juego s c -> Estado s -> Vista
proyeccion j est = Vista t (Map.fromList [(evRef ev, ev) | ev <- evs])
  where
    t        = estadoTick est
    alm      = comunMagnitudes (persistenteComun (estadoPersistente est))
    catalogo = juegoCatalogoMag j
    ejJuego  = juegoProyectar j est
    evs      = map (completar (derivadoVigentes (estadoDerivado est)) t alm catalogo) ejJuego

-- | La proyección de @e1@ hecha sobre la de @e0@: se proyectan de nuevo
-- solo las entidades sucias y el resto se queda como estaba, compartido con
-- la vista anterior. Pide que @v0@ sea @proyeccion j e0@; entonces el
-- resultado es @proyeccion j e1@ (la ley está en las pruebas).
--
-- Sucias son las que dice el juego ('juegoSucias') más las que el motor ve
-- en el almacén: las de una magnitud que cambió ('clavesCambiadas', que salta
-- lo compartido) y las de un modificador que empieza o deja de contar al
-- pasar de un tick al otro o de unos vigentes a otros. Esa última búsqueda
-- recorre los modificadores; solo se hace si cambió el tick o los vigentes.
-- Si el juego no sabe qué cambió, se proyecta todo.
proyeccionIncremental :: Juego s c -> Estado s -> Vista -> Estado s -> Vista
proyeccionIncremental j e0 v0 e1 = case juegoSucias j e0 e1 of
  Nothing      -> proyeccion j e1
  Just deJuego -> Vista t1 (Set.foldl' reproyectar (vEntidades v0) (deJuego <> deAlmacen <> porVentana))
  where
    t0 = estadoTick e0
    t1 = estadoTick e1
    alm e = comunMagnitudes (persistenteComun (estadoPersistente e))
    alm0 = alm e0
    alm1 = alm e1
    vig0 = derivadoVigentes (estadoDerivado e0)
    vig1 = derivadoVigentes (estadoDerivado e1)
    catalogo = juegoCatalogoMag j
    deAlmacen = Set.fromList (map fst (clavesCambiadas alm0 alm1))
    porVentana
      | t0 == t1 && vig0 == vig1 = Set.empty
      | otherwise = Set.fromList
          [ r | ((r, _), x) <- Map.toList alm1
              , any (\m -> cuentaEn vig0 t0 m /= cuentaEn vig1 t1 m) (almacenMods x) ]
    reproyectar ents r = case juegoProyectarDe j e1 r of
      Nothing -> Map.delete r ents
      Just ej -> Map.insert r (completar vig1 t1 alm1 catalogo ej) ents

-- | Solo se proyectan los modificadores que cuentan en el tick de la vista
-- (en su ventana y, si son condicionales, vigentes).
completar :: IntSet -> Tick -> Almacen -> Map Magnitud DefMagnitud -> EntidadJuego -> EntidadVista
completar vig t alm catalogo ej =
  EntidadVista (ejRef ej) (ejCampos ej) mags
  where
    ref  = ejRef ej
    -- Las claves del almacén se ordenan por entidad primero: las magnitudes de
    -- esta entidad forman un tramo contiguo, que se toma en O(log n). Recorrer
    -- todo el almacén por cada entidad hacía la proyección cuadrática.
    deLaEntidad = Map.takeWhileAntitone ((== ref) . fst)
                    (Map.dropWhileAntitone ((< ref) . fst) alm)
    mags = Map.fromList
      [ (m, magnitudVista dm (almacenBase x) (filter (cuentaEn vig t) (almacenMods x)))
      | ((_, m), x) <- Map.toList deLaEntidad
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
    , avArgumentos = VTexto (fuenteRef (modFuente m))
                     : [ VLista [VTexto n, VFijo v] | (n, v) <- modDetalle m ]
    , avAporte     = modAporte m
    , avVence      = modFin m
    }

-- ---------------------------------------------------------------------------
-- Cambios: referencia, optimizada y punto de entrada
-- ---------------------------------------------------------------------------

-- | Implementación de referencia: compara cada entidad de vNew contra vOld.
-- Correcta por construcción; recorre todas las entidades. La usan las leyes.
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

-- | Punto de entrada del motor: lo que cambió de una vista a otra, igual que
-- 'cambiosRef'. Usa 'clavesCambiadas', así que cuando la vista nueva se hizo
-- sobre la vieja ('proyeccionIncremental') cuesta lo que cambió; entre dos
-- proyecciones completas cuesta lo mismo que la referencia.
cambios :: Vista -> Vista -> Cambios
cambios vOld vNew =
  let ks = clavesCambiadas (vEntidades vOld) (vEntidades vNew)
      nuevas = vEntidades vNew
  in Cambios
       { cTick         = vTick vNew
       , cActualizadas = [ ev | k <- ks, Just ev <- [Map.lookup k nuevas] ]
       , cEliminadas   = [ k | k <- ks, not (Map.member k nuevas) ]
       }

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

-- | Diferencias de b respecto de a, en orden de entidad y nombre. Solo mira
-- las entidades que cambiaron ('clavesCambiadas'): las demás no dan ninguna.
diferencias :: Vista -> Vista -> [Diferencia]
diferencias a b =
  [ d
  | r <- clavesCambiadas (vEntidades a) (vEntidades b)
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
