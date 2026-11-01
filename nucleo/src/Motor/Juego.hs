{-# LANGUAGE StrictData, TypeFamilies #-}
module Motor.Juego where

import Data.List (foldl', sortBy)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import Data.Text (Text)
import qualified Data.Text as T
import Motor.Azar
import Motor.Base
import Motor.Calendario
import Motor.Estado
import Motor.Hechos
import Motor.Recorrido (Grafo)
import Motor.Guion
import Motor.Director
import Motor.Cronica (pasoCronica, pasoFin, terminada)
import Motor.Moneda (pasoMoneda)
import Motor.Sistema
import Motor.Magnitudes
import Motor.Vista (EntidadJuego)
import Data.IntSet (IntSet)
import qualified Data.IntSet as IntSet

data Sellado c = Sellado
  { sellTick      :: Tick
  , sellFaccion   :: FaccionId
  , sellSecuencia :: Int
  , sellCmd       :: c
  } deriving (Show)

newtype Rechazo = Rechazo Text deriving (Eq, Show)

-- | Placeholder para Hito 1a. La proyección real llega en Hito 2.
data Proyeccion = Proyeccion

data Agente s c = Agente
  { agPlanificar :: Proyeccion -> Rng -> PlanDe s
  , agEjecutar   :: PlanDe s -> Proyeccion -> Rng -> [c]
  }

data Juego s c = Juego
  { juegoSistemas    :: [Sistema s]
  , juegoAplicarCmd  :: Estado s -> Sellado c -> Either Rechazo (Estado s, [Hecho])
  , juegoDerivar     :: Grafo -> Tick -> Persistente s -> DerivadoDe s   -- ^ el grafo trae el mapa ('grafoMapa')
  , juegoProyectar   :: Estado s -> [EntidadJuego]
  , juegoProyectarDe :: Estado s -> EntRef -> Maybe EntidadJuego
    -- ^ lo que aporta una sola entidad; coincide con su elemento de
    --   'juegoProyectar', y 'Nothing' si no es visible
  , juegoSucias      :: Estado s -> Estado s -> Maybe (Set EntRef)
    -- ^ entidades cuyos campos pudieron cambiar del primer estado al segundo
    --   (o aparecer o desaparecer): un superconjunto de las que cambiaron.
    --   Lo que el motor pone en la vista (las magnitudes) no lo cuenta el
    --   juego. 'Nothing' es «no lo sé»: se proyecta todo.
  , juegoAgentes     :: Map FaccionId (Agente s c)
  , juegoCatalogoMag :: Map Magnitud DefMagnitud
  }

paso :: Juego s c -> Entorno -> Semilla -> Tick -> [Sellado c] -> Estado s -> (Estado s, [Hecho])
paso j ent sigma t cmds s = let (s', hs, _) = pasoDetallado j ent sigma t cmds s in (s', hs)

-- | Una respuesta del jugador a una decisión del director: secuencia (para
-- avisar de un rechazo), decisión y respuesta (una opción o una cantidad).
data Respuesta = Respuesta { reSecuencia :: Int, reDecision :: Int, reValor :: Text }
  deriving (Eq, Show)

pasoDetallado :: Juego s c -> Entorno -> Semilla -> Tick -> [Sellado c] -> Estado s
              -> (Estado s, [Hecho], [(Sellado c, Rechazo)])
pasoDetallado j ent sigma t cmds s = let (s', hs, r, _) = pasoCompleto j ent sigma t cmds [] s in (s', hs, r)

-- | El tick completo. Devuelve también los comandos y las respuestas
-- rechazados, para que la cáscara avise a quien los mandó.
--
-- Orden: fases (al empezar el tick, para que los sistemas de la fase nueva
-- corran ese mismo día), vencimiento de modificadores, agentes (paso 0),
-- cola de comandos y respuestas (paso 1), sistemas (pasos 2 a 15), moneda
-- (precios e inflación, con lo que dejaron los sistemas), derivado (16),
-- director (17), fin de la partida y crónica (18). Una partida terminada
-- devuelve el mismo estado, sin hechos.
pasoCompleto :: Juego s c -> Entorno -> Semilla -> Tick -> [Sellado c] -> [Respuesta] -> Estado s
             -> (Estado s, [Hecho], [(Sellado c, Rechazo)], [(Respuesta, Rechazo)])
pasoCompleto j ent sigma t cmdsJugador respuestas s00
  -- Una partida terminada ya no avanza: ni tick, ni comandos, ni hechos.
  | terminada s00 = (s00, [], [], [])
  | otherwise = (sCronica, hechos, rechazos, rechazosR)
  where
    hechos = hsF ++ hs0 ++ hs1 ++ hsR ++ hs2 ++ hsV ++ hsD ++ hsFin
    guion = entGuion ent
    grafo = entGrafo ent
    -- Durante el paso, y al terminar, el estado está en el tick t: estadoTick
    -- es el último tick procesado. Antes nadie lo avanzaba y se quedaba en 0.
    (sF, hsF)     = pasoFases (juegoCatalogoMag j) guion t s00 { estadoTick = t }
    (s0, hs0)     = pasoExpirar t sF
    (cmdsIA, s0') = pasoAgentes j sigma t s0
    (s1a, hs1, rechazos) = aplicarColaDetallada j (cmdsJugador ++ cmdsIA) s0'
    (s1, hsR, rechazosR) = foldl responder (s1a, [], []) respuestas
    responder (e, hs, rs) r = case responderDecision guion (reDecision r) (reValor r) e of
      Right (e', hs') -> (e', hs ++ hs', rs)
      Left m          -> (e, hs, rs ++ [(r, Rechazo m)])
    (s2, hs2)     = correr sigma t (juegoSistemas j) s1
    (s3, hsV)     = pasoDerivar j grafo t (pasoMoneda (entEconomia ent) t s2)
    (sFinal, hsD) = pasoDirector (juegoCatalogoMag j) guion (rng sigma "director" t) t s3
    (sFin, hsFin)  = pasoFin (juegoCatalogoMag j) guion t sFinal
    -- La crónica se escribe al final, con todos los hechos del tick (incluido
    -- el fin de la partida, si lo hubo).
    sCronica      = pasoCronica guion hechos sFin

pasoAgentes :: Juego s c -> Semilla -> Tick -> Estado s -> ([Sellado c], Estado s)
pasoAgentes j sigma t s =
  let agentes    = Map.toAscList (juegoAgentes j)
      planes0    = comunPlanes (persistenteComun (estadoPersistente s))
      cal        = comunCalendario (persistenteComun (estadoPersistente s))
      enPeriodo = esInicioDePeriodo cal t
      planificar fid ag =
        agPlanificar ag Proyeccion (rng sigma ("plan:" <> unFid fid) t)
      planes1 = if enPeriodo then Map.mapWithKey planificar (juegoAgentes j) else planes0
      planesFinal = foldl' (\m (fid, ag) ->
                             if Map.member fid m then m
                             else Map.insert fid (planificar fid ag) m)
                    planes1 agentes
      s1 = s { estadoPersistente = (estadoPersistente s)
                { persistenteComun = (persistenteComun (estadoPersistente s))
                  { comunPlanes = planesFinal } } }
      cmds = concat
        [ [ Sellado t fid i c
          | (i, c) <- zip [0..]
              (agEjecutar ag (Map.findWithDefault (agPlanificar ag Proyeccion
                                                    (rng sigma ("plan:" <> unFid fid) t))
                                                   fid planesFinal)
                          Proyeccion (rng sigma ("ejec:" <> unFid fid) t)) ]
        | (fid, ag) <- agentes ]
  in (cmds, s1)
  where
    unFid (FaccionId i) = "f" <> T.pack (show i)

-- | El paso 16: al empezar el periodo recalcula el derivado y guarda de qué
-- se calculó (el origen). Un modificador condicional que estaba vigente y ya
-- no lo está emite `modificador_terminado` con la razón `condicion`, pero
-- sigue en el almacén: si su condición vuelve a cumplirse, vuelve a contar.
-- (Un modificador que expiró ya emitió su hecho al empezar el tick y no está
-- en el almacén, así que no se anuncia dos veces.)
pasoDerivar :: Juego s c -> Grafo -> Tick -> Estado s -> (Estado s, [Hecho])
pasoDerivar j grafo t s =
  let cal = comunCalendario (persistenteComun (estadoPersistente s))
  in if esInicioDePeriodo cal t
       then let p       = estadoPersistente s
                d       = derivar j grafo t p
                antes   = derivadoVigentes (estadoDerivado s)
                ahora   = derivadoVigentes d
                perdidos = [ m | x <- Map.elems (comunMagnitudes (persistenteComun p))
                               , m <- almacenMods x
                               , modId m `IntSet.member` antes
                               , not (modId m `IntSet.member` ahora) ]
            in ( s { estadoDerivado = d, estadoOrigen = Origen t p }
               , map (hechoModificadorTerminado t "condicion") perdidos )
       else (s, [])

hechoModificadorTerminado :: Tick -> Text -> Modificador -> Hecho
hechoModificadorTerminado t razon m =
  Hecho "modificador_terminado" t [modEntidad m] (Map.fromList
    [ ("id",       T.pack (show (modId m)))
    , ("magnitud", let Magnitud n = modMagnitud m in n)
    , ("fuente",   fuenteTipo (modFuente m))
    , ("razon",    razon) ])

aplicarCola :: Juego s c -> [Sellado c] -> Estado s
            -> (Estado s, [Hecho], [Rechazo])
aplicarCola j cmds s0 = let (s, hs, rs) = aplicarColaDetallada j cmds s0 in (s, hs, map snd rs)

-- | La cola en orden (tick, facción, secuencia). Un rechazo no detiene la cola
-- ni cambia el estado; se devuelve junto al comando que lo causó.
aplicarColaDetallada :: Juego s c -> [Sellado c] -> Estado s
                     -> (Estado s, [Hecho], [(Sellado c, Rechazo)])
aplicarColaDetallada j cmds s0 = foldl' aplicarUno (s0, [], []) (sortBy cmp cmds)
  where
    cmp a b = (sellTick a, sellFaccion a, sellSecuencia a)
       `compare` (sellTick b, sellFaccion b, sellSecuencia b)
    aplicarUno (e, hs, rs) c = case juegoAplicarCmd j e c of
      Right (e', hs') -> (e', hs ++ hs', rs)
      Left  r         -> (e, hs, rs ++ [(c, r)])

-- | El derivado completo: primero el del juego, luego qué modificadores
-- condicionales están vigentes.
derivar :: Juego s c -> Grafo -> Tick -> Persistente s -> Derivado s
derivar j g t p = Derivado (vigentesEn (juegoCatalogoMag j) t p) (juegoDerivar j g t p)

-- | Los ids de los modificadores condicionales cuya condición se cumple en t.
-- Las condiciones leen valores efectivos SIN los modificadores condicionales
-- (se evalúan con un conjunto de vigentes vacío). Es una decisión de diseño:
-- si una condición pudiera leer una magnitud que otro condicional modifica,
-- el resultado dependería del orden de evaluación o de un punto fijo. Así el
-- cálculo es una función pura de (t, persistente), que es lo que exige la ley
-- del derivado reproducible (documento funcional, sección 4).
vigentesEn :: Map Magnitud DefMagnitud -> Tick -> Persistente s -> IntSet
vigentesEn cat t p = IntSet.fromList
  [ modId m
  | x <- Map.elems alm
  , m <- almacenMods x
  , Just c <- [modCondicion m]
  , activoEn t m
  , evaluarCondicion cat IntSet.empty t alm c ]
  where alm = comunMagnitudes (persistenteComun p)

-- | Al empezar el tick, los modificadores cuyo fin llegó se quitan del
-- almacén y cada uno emite un hecho `modificador_terminado`. El valor
-- efectivo vuelve solo a su base: no hay regla de decaimiento.
pasoExpirar :: Tick -> Estado s -> (Estado s, [Hecho])
pasoExpirar t s =
  let com          = persistenteComun (estadoPersistente s)
      (alm', venc) = expirar t (comunMagnitudes com)
      hecho = hechoModificadorTerminado t "expiro"
  in if null venc then (s, [])
     else ( s { estadoPersistente = (estadoPersistente s)
                  { persistenteComun = com { comunMagnitudes = alm' } } }
          , map hecho venc )

-- | La consulta (documento funcional, sección 10): una predicción pura.
-- Simula desde el tick @t@ hasta la siguiente veintena (inclusive) dos veces,
-- con el comando y sin él, con los mismos comandos pendientes, y devuelve el
-- estado final de cada una. Así el costo visible incluye el efecto de la
-- veintena (ingresos, agravio), no solo el cambio inmediato. No toca la partida.
consultar :: Juego s c -> Entorno -> Semilla -> Tick -> [Sellado c] -> Sellado c -> Estado s
          -> Either Rechazo (Tick, Estado s, Estado s)
consultar j mapa sigma (Tick t) pendientes cmd s0 =
  case [ r | (c, r) <- rechazos1, sellSecuencia c == sellSecuencia cmd, sellFaccion c == sellFaccion cmd ] of
    (r : _) -> Left r
    []      -> Right (Tick horizonte, correr' sinCmd, correr' conCmd)
  where
    cal = comunCalendario (persistenteComun (estadoPersistente s0))
    horizonte = until (esInicioDePeriodo cal . Tick) (+ 1) t
    (_, _, rechazos1) = pasoDetallado j mapa sigma (Tick t) (pendientes ++ [cmd]) s0
    sinCmd = pendientes
    conCmd = pendientes ++ [cmd]
    correr' cs = foldl (\e x -> let (e', _, _) = pasoDetallado j mapa sigma (Tick x) (if x == t then cs else []) e in e')
                       s0 [t .. horizonte]
