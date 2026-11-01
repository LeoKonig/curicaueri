{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Edificios y obras (V5, *Las palancas*: Construcción; *Arquitectura de
-- extensión*, el ejemplo de la yácata; hito 3).
--
-- Un edificio es un dato (@datos/edificios.json@): su costo en valor y en
-- veintenas de obra, los modificadores permanentes que aporta al terminarse y
-- lo que hace al terminar. La obra en curso es estado persistente del
-- altépetl ('altObra'). Como en el prototipo del hito 0:
--
-- * el costo en valor se cobra al empezar, y sin tesoro suficiente la obra se
--   rechaza sin cambiar el estado;
-- * cada altépetl tiene a lo sumo una obra en curso y cada edificio una vez;
-- * la obra avanza una veintena de obra por cada veintena en que la partida
--   de obras llega a 'cObrasPresupuestoMinimo', y mientras haya obras en curso
--   esa partida se paga (ver 'Reglas.Sistemas.hacienda').
--
-- Al terminar, los modificadores entran al almacén con la fuente
-- @edificio:<id>:<altépetl>@, de modo que el desglose nombra la obra, y se
-- emite @edificio_terminado@.
module Reglas.Edificios
  ( Edificios
  , DefEdificio (..)
  , DefModEdificio (..)
  , EntidadEdificio (..)
  , EfectoTerminar (..)
  , edificiosVacios
  , cargarEdificios
  , idsEdificios
  , fuenteEdificio
  , iniciarObra
  , construccion
  ) where

import Data.Aeson (Value)
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import Data.List (foldl', nub)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Carga (CategoriaError (..), ErrorCarga (..), Validacion (..), falla)
import Motor.Estado
import Motor.Hechos
import Motor.Juego (Rechazo (..))
import Motor.Magnitudes
import Motor.Sistema
import Reglas.Base
import Reglas.Constantes
import Reglas.Estado
import Reglas.Grupos (agregarVarios)

-- | A quién llega un modificador o un efecto: al altépetl donde se levanta la
-- obra o a la facción que la paga.
data EntidadEdificio = AlAltepetl | AlaFaccion
  deriving (Eq, Show)

data DefModEdificio = DefModEdificio
  { dmeEntidad  :: EntidadEdificio
  , dmeMagnitud :: Magnitud
  , dmeAporte   :: Aporte
  } deriving (Eq, Show)

-- | Lo que hace un edificio al terminarse, además de sus modificadores. Por
-- ahora solo sumar a la base de una magnitud (el prestigio de la obra), con el
-- nombre del efecto @sumar_mag@ de "Motor.Efectos"; la entidad es relativa a
-- la obra, como en los modificadores.
data EfectoTerminar = SumarBase EntidadEdificio Magnitud Fijo
  deriving (Eq, Show)

data DefEdificio = DefEdificio
  { deId          :: Text
  , deCostoValor  :: Fijo          -- ^ unidades de valor, del tesoro
  , deVeintenas   :: Int           -- ^ veintenas de obra
  , deMods        :: [DefModEdificio]
  , deAlTerminar  :: [EfectoTerminar]
  } deriving (Eq, Show)

-- | Los edificios por id. El orden del archivo se conserva para el catálogo.
data Edificios = Edificios
  { edOrden :: [Text]
  , edDefs  :: Map Text DefEdificio
  } deriving (Eq, Show)

edificiosVacios :: Edificios
edificiosVacios = Edificios [] Map.empty

idsEdificios :: Edificios -> [Text]
idsEdificios = edOrden

-- | La fuente de los modificadores de un edificio terminado.
fuenteEdificio :: Text -> AltId -> Fuente
fuenteEdificio e (AltId a) = Fuente "edificio" (e <> ":" <> T.pack (show a))

-- | Carga @edificios.json@ acumulando todos los errores: ids repetidos, costo
-- negativo, veintenas no positivas, insumos (aún no implementados), entidades
-- desconocidas, magnitudes que no están en el catálogo del juego, un
-- modificador sin aporte o con los dos, y efectos al terminar no admitidos.
cargarEdificios :: Text -> Map Magnitud DefMagnitud -> Value -> Validacion Edificios
cargarEdificios archivo catalogo v = case A.parseEither leer v of
  Left e -> falla (ErrorCarga ErrorEstructura archivo "" (T.pack e))
  Right crudos ->
    let ids = [ i | (i, _, _, _, _, _) <- crudos ]
        repetidos = traverse (\i -> if length (filter (== i) ids) > 1
                                      then err ErrorEsquema ("edificios." <> i) "edificio repetido"
                                      else pure ()) (nub ids)
    in (\_ ds -> Edificios ids (Map.fromList [ (deId d, d) | d <- ds ]))
         <$> repetidos <*> traverse validar crudos
  where
    err :: CategoriaError -> Text -> Text -> Validacion b
    err cat ruta msg = falla (ErrorCarga cat archivo ruta msg)
    leer = A.withObject "edificios" $ \o -> o A..: "edificios" >>= mapM edificio
    edificio = A.withObject "edificio" $ \o -> do
      i     <- o A..: "id"
      costo <- o A..: "costo"
      (val, vs, ins) <- A.withObject "costo" (\c ->
                          (,,) <$> c A..: "valor" <*> c A..: "veintenas"
                               <*> (c A..:? "insumos" A..!= ([] :: [Value]))) costo
      mods  <- o A..:? "modificadores" A..!= []
      fins  <- o A..:? "al_terminar" A..!= []
      pure (i, val, vs, ins, mods, fins)
    validar (i, val, vs, ins, mods, fins) =
      let ruta c = "edificios." <> i <> "." <> c
          valorOk = if val >= Fijo 0 then pure ()
                    else err ErrorRango (ruta "costo.valor") "el costo no puede ser negativo"
          veintOk = if vs > (0 :: Int) then pure ()
                    else err ErrorRango (ruta "costo.veintenas") "una obra dura al menos una veintena"
          insOk = if null ins then pure ()
                  else err ErrorEsquema (ruta "costo.insumos")
                         "los insumos aún no están implementados (documento funcional, sección 14h): deja la lista vacía"
      in DefEdificio i val vs
           <$> traverse (modificador (ruta "modificadores")) (zip [0 :: Int ..] mods)
           <*> traverse (efecto (ruta "al_terminar")) (zip [0 :: Int ..] fins)
           <* valorOk <* veintOk <* insOk
    entidad ruta t = case (t :: Text) of
      "altepetl" -> pure AlAltepetl
      "faccion"  -> pure AlaFaccion
      _          -> err ErrorReferencia (ruta <> ".entidad") ("entidad desconocida: " <> t <> " (altepetl o faccion)")
    magnitud ruta m@(Magnitud n)
      | Map.member m catalogo = pure m
      | otherwise = err ErrorReferencia (ruta <> ".magnitud") ("magnitud que el juego no declara: " <> n)
    modificador base (k, mv) =
      let ruta = base <> "." <> T.pack (show k)
      in case A.parseEither campos mv of
           Left e -> err ErrorEstructura ruta (T.pack e)
           Right (ent, mag, suma, por) ->
             let aporte = case (suma, por) of
                   (Just s, Nothing) -> pure (Aporte s (Fijo 0))
                   (Nothing, Just p) -> pure (Aporte (Fijo 0) (p ./. desdeEntero 100))
                   _ -> err ErrorEsquema ruta "un modificador lleva «sumar» o «porcentaje», uno de los dos"
             in DefModEdificio <$> entidad ruta ent <*> magnitud ruta mag <*> aporte
    campos = A.withObject "modificador" $ \o ->
      (,,,) <$> o A..: "entidad" <*> o A..: "magnitud" <*> o A..:? "sumar" <*> o A..:? "porcentaje"
    efecto base (k, ev) =
      let ruta = base <> "." <> T.pack (show k)
      in case A.parseEither (A.withObject "efecto" (\o ->
                (,,,) <$> o A..: "tipo" <*> o A..: "entidad" <*> o A..: "magnitud" <*> o A..: "valor")) ev of
           Left e -> err ErrorEstructura ruta (T.pack e)
           Right (tipo, ent, mag, val)
             | tipo == ("sumar_mag" :: Text) -> SumarBase <$> entidad ruta ent <*> magnitud ruta mag <*> pure val
             | otherwise -> err ErrorEsquema (ruta <> ".tipo") ("efecto no admitido al terminar una obra: " <> tipo)

-- ---------------------------------------------------------------------------
-- Obras
-- ---------------------------------------------------------------------------

-- | Empieza una obra: valida, cobra el costo en valor del tesoro y deja la
-- obra en curso. Un rechazo no cambia el estado.
iniciarObra :: Edificios -> Text -> AltId -> Estado Purepecha -> Either Rechazo (Estado Purepecha, [Hecho])
iniciarObra eds eid alt est = do
  d <- maybe (Left (Rechazo ("edificio desconocido: " <> eid))) Right (Map.lookup eid (edDefs eds))
  a <- maybe (Left (Rechazo "el altépetl no existe")) Right (Map.lookup alt (ppAltepetl jue))
  case altObra a of
    Just o  -> Left (Rechazo (altNombre a <> " ya tiene una obra en curso: " <> obEdificio o))
    Nothing -> Right ()
  if eid `elem` altEdificios a then Left (Rechazo (altNombre a <> " ya tiene " <> eid)) else Right ()
  let tesoro = baseFaccion magTesoro est
  if tesoro < deCostoValor d
    then Left (Rechazo ("no alcanza el tesoro: " <> eid <> " cuesta " <> mostrarFijo (deCostoValor d)
                        <> " y hay " <> mostrarFijo tesoro))
    else Right ()
  let obra = Obra eid 0 (deVeintenas d)
      jue' = jue { ppAltepetl = Map.insert alt a { altObra = Just obra } (ppAltepetl jue) }
      alm' = sumarBase entFaccion magTesoro (negarF (deCostoValor d)) (comunMagnitudes com)
      est' = est { estadoPersistente = p { persistenteJuego = jue', persistenteComun = com { comunMagnitudes = alm' } } }
  pure (est', [])
  where
    p   = estadoPersistente est
    jue = persistenteJuego p
    com = persistenteComun p

-- | El sistema de construcción (paso 10, cada veintena). Avanza las obras en
-- orden de altépetl si la partida de obras llega al mínimo, y termina las que
-- llegan a su total. Es el único que escribe la base de lo que sumen los
-- efectos al terminar (el prestigio) y el único que añade modificadores de
-- edificio.
construccion :: Constantes -> Edificios -> Sistema Purepecha
construccion c eds = Sistema
  { sisNombre   = NombreSistema "construccion"
  , sisCadencia = Periodo
  , sisLee      = Set.empty
  , sisEscribe  = Set.fromList ([ dmeMagnitud m | d <- Map.elems (edDefs eds), m <- deMods d ]
                                ++ [ m | d <- Map.elems (edDefs eds), SumarBase _ m _ <- deAlTerminar d ])
  , sisEjecutar = \_ est ->
      let jue = persistenteJuego (estadoPersistente est)
          trabaja = pbObras (ppPresupuesto jue) >= cObrasPresupuestoMinimo c
          enObra = [ (altId a, o) | a <- Map.elems (ppAltepetl jue), Just o <- [altObra a] ]
      in if not trabaja || null enObra then (est, [])
         else foldl' (avanzar eds) (est, []) enObra
  }

avanzar :: Edificios -> (Estado Purepecha, [Hecho]) -> (AltId, Obra) -> (Estado Purepecha, [Hecho])
avanzar eds (est, hs) (alt, o)
  | obAvance o + 1 < obTotal o = (conObra (Just o { obAvance = obAvance o + 1 }) [] est, hs)
  | otherwise = case Map.lookup (obEdificio o) (edDefs eds) of
      -- Un edificio que desapareció de los datos (un guardado con otro
      -- archivo): la obra se termina sin efectos, para no quedar colgada.
      Nothing -> (conObra Nothing [] est, hs)
      Just d  ->
        let t    = estadoTick est
            ref  = entRefAlt alt
            entD AlAltepetl = ref
            entD AlaFaccion = entFaccion
            mods = [ Modificador 0 (dmeMagnitud m) (entD (dmeEntidad m)) (dmeAporte m)
                                 (fuenteEdificio (deId d) alt) Nothing Nothing Nothing AlcancePropia
                   | m <- deMods d ]
            est1 = conObra Nothing [deId d] est
            p    = estadoPersistente est1
            com  = persistenteComun p
            alm1 = asegurarBaseProduccion ref (comunMagnitudes com)
            alm2 = agregarVarios mods alm1
            alm3 = foldl' (\al (SumarBase e m v) -> sumarBase (entD e) m v al) alm2 (deAlTerminar d)
            est2 = est1 { estadoPersistente = p { persistenteComun = com { comunMagnitudes = alm3 } } }
        in (est2, hs ++ [Hecho "edificio_terminado" t [ref] (Map.fromList [("edificio", deId d)])])
  where
    conObra mo nuevos e =
      let p   = estadoPersistente e
          jue = persistenteJuego p
          upd a = a { altObra = mo, altEdificios = altEdificios a ++ nuevos }
      in e { estadoPersistente = p { persistenteJuego = jue { ppAltepetl = Map.adjust upd alt (ppAltepetl jue) } } }

-- | La producción de un altépetl tiene base 1. Si su entrada no está en el
-- almacén (un escenario que no la siembra), se crea con esa base antes de
-- recibir el primer modificador, para que un +10 % no se aplique sobre 0.
asegurarBaseProduccion :: EntRef -> Almacen -> Almacen
asegurarBaseProduccion ref = Map.alter (Just . maybe (AlmacenMag baseProduccionAlt []) id) (ref, magProduccionAlt)

negarF :: Fijo -> Fijo
negarF (Fijo x) = Fijo (negate x)

mostrarFijo :: Fijo -> Text
mostrarFijo f = case A.toJSON f of
  A.String t -> t
  otro       -> T.pack (show otro)
