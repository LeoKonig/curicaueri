{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Aparición y desaparición de facciones (V5, *Aparición y desaparición de
-- facciones*; documento funcional, sección 14b) y el agente nulo de las que
-- no dirige la persona.
--
-- Cada veintena, al empezar, una facción potencial cuyo @facDesde@ llegó se
-- activa y una activa cuyo @facHasta@ llegó se elimina. Al eliminarse
-- transfiere lo que tenía según su 'Transferencia':
--
-- * el tesoro pasa al absorbente (con el tope del rango del tesoro) o se
--   pierde, y la facción queda en cero;
-- * los altépetl, con sus pops, cambian de facción; el cabecera de la
--   eliminada queda como señorío y sujeto a la cabecera del absorbente;
-- * los personajes pasan a servir al absorbente. Quien se pierde queda
--   sirviendo a la eliminada, inerte: ninguna facción activa puede nombrarlo.
--
-- «Se pierde» no destruye datos: el tesoro es lo único que se pone en cero.
-- Un altépetl perdido sigue con la facción eliminada y nadie lo recorre; así
-- la población y los ids se conservan y la pérdida la dice el hecho.
-- Prestigio y legitimidad no se transfieren: son de la facción.
--
-- Si el absorbente no está activa al eliminarse la facción, el destino se
-- pierde y el hecho lo anota (@destino_inactivo@).
module Reglas.Facciones
  ( facciones
  , activarFaccion
  , eliminarFaccion
  , agenteNulo
  , conAgentesNulos
  ) where

import Data.List (foldl')
import qualified Data.Map.Strict as Map
import Data.Maybe (listToMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Estado
import Motor.Hechos
import Motor.Juego
import Motor.Magnitudes
import Motor.Sistema
import Reglas.Base
import Reglas.Comando (Comando)
import Reglas.Estado
import Reglas.Grupos

-- | El sistema de facciones (paso 13, cada veintena). Escribe el tesoro (al
-- transferirlo) y los modificadores de los nombramientos de los altépetl que
-- cambian de facción (en los grupos de la facción nueva).
facciones :: Grupos -> Sistema Purepecha
facciones gs = Sistema
  { sisNombre   = NombreSistema "facciones"
  , sisCadencia = Periodo
  , sisLee      = Set.empty
  , sisEscribe  = Set.singleton magTesoro
  , sisEjecutar = \_ est ->
      let t  = estadoTick est
          Tick n = t
          p  = persistenteJuego (estadoPersistente est)
          nace = [ f | f <- Map.elems (ppFacciones p), facEstado f == Potencial
                     , maybe False (<= fromIntegral n) (facDesde f) ]
          muere = [ f | f <- Map.elems (ppFacciones p), facEstado f == Activa
                      , maybe False (<= fromIntegral n) (facHasta f) ]
          -- Primero las que aparecen: una absorbente que nace el mismo día
          -- que otra desaparece ya puede recibirla.
          (est1, hs1) = foldl' (\(e, hs) f -> let (e', h) = activarFaccion t f e in (e', hs ++ h)) (est, []) nace
          (est2, hs2) = foldl' (\(e, hs) f -> let (e', h) = eliminarFaccion gs t (facId f) e in (e', hs ++ h)) (est1, hs1) muere
      in (est2, hs2)
  }

-- | Activa una facción potencial. Si no tiene tesoro en el almacén, empieza
-- en cero (el escenario puede declararle el suyo).
activarFaccion :: Tick -> Faccion -> Estado Purepecha -> (Estado Purepecha, [Hecho])
activarFaccion t f est =
  let per = estadoPersistente est
      p   = persistenteJuego per
      com = persistenteComun per
      clave = (entFac (facId f), magTesoro)
      alm = if Map.member clave (comunMagnitudes com) then comunMagnitudes com
            else Map.insert clave (AlmacenMag (Fijo 0) []) (comunMagnitudes com)
      p'  = p { ppFacciones = Map.insert (facId f) f { facEstado = Activa } (ppFacciones p) }
  in ( est { estadoPersistente = per { persistenteJuego = p', persistenteComun = com { comunMagnitudes = alm } } }
     , [Hecho "faccion_aparece" t [entFac (facId f)] (Map.fromList [("razon", "fecha"), ("tipo", facTipo f)])] )

-- | Elimina una facción activa y transfiere lo que tenía. Devuelve el hecho
-- @faccion_desaparece@ con lo transferido y lo perdido, y los
-- @modificador_terminado@ de los nombramientos que cambian de manos.
eliminarFaccion :: Grupos -> Tick -> FaccionId -> Estado Purepecha -> (Estado Purepecha, [Hecho])
eliminarFaccion gs t fid est0 = case Map.lookup fid (ppFacciones (juegoDe est0)) of
  Nothing -> (est0, [])
  Just f ->
    let tr = facTransferencia f
        activaDestino = \d -> case d of
          AlAbsorbente a | a /= fid, Just fa <- Map.lookup a (ppFacciones (juegoDe est0)), facEstado fa == Activa -> Just a
          _ -> Nothing
        dTesoro = activaDestino (trTesoro tr)
        dAlt    = activaDestino (trAltepetl tr)
        dPers   = activaDestino (trPersonajes tr)
        -- 1. El tesoro.
        tesoro = baseFaccion fid magTesoro est0
        estT = case dTesoro of
          Just a  -> moverTesoro fid a tesoro est0
          Nothing -> moverTesoro fid fid (Fijo 0) (poner (entFac fid, magTesoro) (Fijo 0) est0)
        -- 2. Los personajes: pasan al absorbente antes que los altépetl, para
        --    que sus nombramientos se rehagan en los grupos de la facción nueva.
        suyosP = [ perId pe | pe <- Map.elems (ppPersonajes (juegoDe estT)), perFaccion pe == fid ]
        estP = case dPers of
          Just a  -> conJuego (\p -> p { ppPersonajes = Map.map (\pe -> if perFaccion pe == fid then pe { perFaccion = a } else pe) (ppPersonajes p) }) estT
          Nothing -> estT
        -- 3. Los altépetl, en orden de id.
        suyosA = [ a | a <- Map.elems (ppAltepetl (juegoDe estP)), altFaccion a == fid ]
        cabeceraDe a = listToMaybe [ altId x | x <- Map.elems (ppAltepetl (juegoDe estP)), altCondicion x == Cabecera a ]
        (estA, hsA) = case dAlt of
          Nothing -> (estP, [])
          Just a  -> foldl' (pasarAltepetl gs t a (cabeceraDe a) (dPers == Just a)) (estP, []) suyosA
        -- 4. La facción queda eliminada; su id no se reutiliza.
        estF = conJuego (\p -> p { ppFacciones = Map.adjust (\x -> x { facEstado = Eliminada }) fid (ppFacciones p) }) estA
        pierdeTes = case dTesoro of { Nothing -> tesoro; Just _ -> Fijo 0 }
        hecho = Hecho "faccion_desaparece" t [entFac fid] $ Map.fromList $
          [ ("razon", "fecha"), ("tipo", facTipo f)
          , ("tesoro_transferido", mostrar (case dTesoro of { Just _ -> tesoro; Nothing -> Fijo 0 }))
          , ("tesoro_perdido", mostrar pierdeTes)
          , ("altepetl_transferidos", num (case dAlt of { Just _ -> length suyosA; Nothing -> 0 }))
          , ("altepetl_perdidos", num (case dAlt of { Just _ -> 0; Nothing -> length suyosA }))
          , ("personajes_transferidos", num (case dPers of { Just _ -> length suyosP; Nothing -> 0 }))
          , ("personajes_perdidos", num (case dPers of { Just _ -> 0; Nothing -> length suyosP }))
          ] ++ [ ("destino_inactivo", "tesoro") | Nothing <- [dTesoro], destinoPedido (trTesoro tr) ]
            ++ [ ("destino_inactivo", "altepetl") | Nothing <- [dAlt], destinoPedido (trAltepetl tr) ]
            ++ [ ("destino_inactivo", "personajes") | Nothing <- [dPers], destinoPedido (trPersonajes tr) ]
    in (estF, hsA ++ [hecho])
  where
    destinoPedido (AlAbsorbente _) = True
    destinoPedido SePierde         = False
    mostrar (Fijo x) = T.pack (show x)
    num = T.pack . show :: Int -> Text

juegoDe :: Estado Purepecha -> Purepecha
juegoDe = persistenteJuego . estadoPersistente

conJuego :: (Purepecha -> Purepecha) -> Estado Purepecha -> Estado Purepecha
conJuego g est = let per = estadoPersistente est in est { estadoPersistente = per { persistenteJuego = g (persistenteJuego per) } }

-- | Pone la base de una magnitud del almacén.
poner :: (EntRef, Magnitud) -> Fijo -> Estado Purepecha -> Estado Purepecha
poner (e, m) v est =
  let per = estadoPersistente est; com = persistenteComun per
  in est { estadoPersistente = per { persistenteComun = com { comunMagnitudes = fijarBase e m v (comunMagnitudes com) } } }

-- | Mueve @x@ del tesoro de @de@ al de @a@: el de @de@ queda en cero y el de
-- @a@ sube x, dentro del rango del tesoro.
moverTesoro :: FaccionId -> FaccionId -> Fijo -> Estado Purepecha -> Estado Purepecha
moverTesoro de a x est =
  let est1 = poner (entFac de, magTesoro) (Fijo 0) est
      nuevo = rangoFijo (minMag rangoTesoro) (maxMag rangoTesoro) (baseFaccion a magTesoro est1 .+. x)
  in if de == a then est1 else poner (entFac a, magTesoro) nuevo est1

-- | Pasa un altépetl a la facción @a@. Su gobernador se quita de los grupos
-- de la facción vieja y, si el personaje también pasó, se nombra de nuevo en
-- los de la nueva. El que era cabecera de la facción vieja queda como
-- señorío, sujeto a la cabecera de la nueva si la hay.
pasarAltepetl :: Grupos -> Tick -> FaccionId -> Maybe AltId -> Bool -> (Estado Purepecha, [Hecho]) -> Altepetl
              -> (Estado Purepecha, [Hecho])
pasarAltepetl gs t nueva cabecera personajesPasan (est, hs) alt =
  let gob = altGobernador alt
      (est1, hq) = quitarNombramiento gs t (altId alt) est
      condicion = case altCondicion alt of
        Cabecera _ -> Senorio
        otra       -> otra
      sujeto = case altCondicion alt of
        Cabecera _ -> maybe (altSujetoA alt) Just cabecera
        _          -> altSujetoA alt
      est2 = conJuego (\p -> p { ppAltepetl = Map.adjust (\x -> x { altFaccion = nueva, altCondicion = condicion, altSujetoA = sujeto })
                                               (altId alt) (ppAltepetl p) }) est1
      est3 = case gob >>= (`Map.lookup` ppPersonajes (juegoDe est2)) of
        Just pe | personajesPasan -> fst (nombrar gs t (altId alt) pe est2)
        _ -> est2
  in (est3, hs ++ hq)

-- | El agente de una facción que no dirige la persona: no hace nada. Los
-- sistemas la tratan como a cualquier otra; la IA sencilla llega en el hito 7.
agenteNulo :: Agente Purepecha Comando
agenteNulo = Agente { agPlanificar = \_ _ -> (), agEjecutar = \_ _ _ -> [] }

-- | El juego con un agente nulo por cada facción del estado que no es la
-- jugable ni está eliminada.
conAgentesNulos :: Purepecha -> Juego Purepecha Comando -> Juego Purepecha Comando
conAgentesNulos p j = j { juegoAgentes = Map.fromList
  [ (facId f, agenteNulo) | f <- Map.elems (ppFacciones p), not (facJugable f), facEstado f /= Eliminada ] }
