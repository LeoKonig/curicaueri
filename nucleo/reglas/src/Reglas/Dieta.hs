{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | La dieta: alimentos por grupo con tope de energía (V5, *La dieta:
-- alimentos, gustos y lujos*; documento funcional, sección 12, *La dieta por
-- grupos*; T27).
--
-- Cada alimento pertenece a un grupo y vale, por tonelada, su energía en
-- toneladas de maíz equivalente (t ME: sus kilocalorías entre las del maíz).
-- De cada grupo solo cuenta, como mucho, una parte de la energía que necesita
-- la gente (su tope), para que nadie viva de un solo alimento. Lo que sobra de
-- un grupo se guarda hasta su tope de reserva (0 para lo que no se guarda).
--
-- Sin @datos/dieta.json@ hay un solo grupo, sin tope, con el maíz como único
-- alimento y la ración de maíz de T25 como necesidad: todo es como en T25, y
-- sus magnitudes tienen los mismos nombres (@cosechado@, @reserva@).
module Reglas.Dieta
  ( Dieta (..)
  , GrupoDieta (..)
  , dietaPorDefecto
  , cargarDieta
  , grupoDe
  , grupoDelMaiz
  , magCosechadoDe
  , magReservaDe
  , magCubiertoDe
  , catalogoDieta
  , cierreDieta
  ) where

import Data.Aeson (Value)
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import Data.List (foldl', sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Carga (CategoriaError (..), ErrorCarga (..), Validacion, falla)
import Motor.Magnitudes
import Reglas.Constantes
import Reglas.Estado

-- | Un grupo de la dieta. El grupo por defecto tiene id vacío (sus
-- magnitudes se llaman como en T25) y la merma del maíz de la facción.
data GrupoDieta = GrupoDieta
  { gdId          :: Text
  , gdTope        :: Fijo          -- ^ parte máxima de la necesidad que puede cubrir
  , gdTopeReserva :: Fijo          -- ^ reserva máxima, como parte de la necesidad
  , gdMerma       :: Maybe Fijo    -- ^ por periodo; 'Nothing': la del maíz de la facción, con sus trojes
  , gdAlimentos   :: Map Text Fijo -- ^ t ME por tonelada de cada alimento
  } deriving (Eq, Show)

data Dieta = Dieta
  { dtGrupos     :: [GrupoDieta]   -- ^ por id
  , dtNecesidad  :: Fijo           -- ^ t ME por persona y año
  , dtDeArchivo  :: Bool           -- ^ falso: la dieta por defecto (T25)
  } deriving (Eq, Show)

-- | La dieta de T25: un grupo sin tope, el maíz, la ración de maíz.
dietaPorDefecto :: Constantes -> Dieta
dietaPorDefecto c = Dieta [GrupoDieta "" uno uno Nothing (Map.singleton bienAlimento uno)] (cRacionMaiz c) False

-- | El grupo de un alimento y lo que vale por tonelada, en t ME.
grupoDe :: Dieta -> Text -> Maybe (GrupoDieta, Fijo)
grupoDe d b = case [ (g, e) | g <- dtGrupos d, Just e <- [Map.lookup b (gdAlimentos g)] ] of
  (x : _) -> Just x
  []      -> Nothing

-- | El id del grupo del maíz (el de los guardados de T25).
grupoDelMaiz :: Dieta -> Maybe Text
grupoDelMaiz d = gdId . fst <$> grupoDe d bienAlimento

nombrar :: Text -> Text -> Magnitud
nombrar base "" = Magnitud base
nombrar base g  = Magnitud (base <> "." <> g)

-- | Lo cosechado del año del altépetl en el grupo, en t ME.
magCosechadoDe :: Text -> Magnitud
magCosechadoDe = nombrar "cosechado"

-- | La reserva local del grupo, en t ME.
magReservaDe :: Text -> Magnitud
magReservaDe = nombrar "reserva"

-- | Lo que el grupo cubrió de la necesidad en el último cierre, en t ME; lo
-- lee @repartir_bien@ para no pasar el tope del grupo.
magCubiertoDe :: Text -> Magnitud
magCubiertoDe = nombrar "cubierto"

-- | Las magnitudes del altépetl por grupo. Lo cosechado lo suma la
-- producción y lo vacía la subsistencia; la reserva y lo cubierto los
-- escriben la subsistencia y @repartir_bien@.
catalogoDieta :: Dieta -> Map Magnitud DefMagnitud
catalogoDieta d = Map.fromList
  [ (m, DefMagnitud n rangoAlimentoAlt ("m." <> base) Nothing True)
  | g <- dtGrupos d, (base, f) <- [("cosechado", magCosechadoDe), ("reserva", magReservaDe), ("cubierto", magCubiertoDe)]
  , let m@(Magnitud n) = f (gdId g) ]

-- | El cierre del año de un altépetl con la dieta por grupos, función pura de
-- la necesidad y, por grupo, @(tope, tope de reserva, disponible)@:
-- @(cobertura, por grupo (comido, reserva', perdido))@.
--
-- > cuenta_g  = min(disponible_g, tope_g · N)
-- > cobertura = min(1, Σ cuenta_g / N)
--
-- Si lo que cuenta pasa de N, la gente come N, repartido en proporción. Lo
-- que sobra de cada grupo va a su reserva hasta @tope de reserva · N@, y lo
-- demás se pierde. Por grupo, @disponible = comido + reserva' + perdido@.
cierreDieta :: Fijo -> [(Fijo, Fijo, Fijo)] -> (Fijo, [(Fijo, Fijo, Fijo)])
cierreDieta need gs
  | need <= Fijo 0 = (uno, [ (Fijo 0, Fijo 0, d) | (_, _, d) <- gs ])
  | otherwise =
      let cuentas = [ min d (t .*. need) | (t, _, d) <- gs ]
          total = foldl' (.+.) (Fijo 0) cuentas
          cob = min uno (total ./. need)
          comidos | total <= need = cuentas
                  | otherwise     = [ min x (x .*. need ./. total) | x <- cuentas ]
          porGrupo = [ let resto = d .-. com
                           r' = min (rho .*. need) resto
                       in (com, r', resto .-. r')
                     | ((_, rho, d), com) <- zip gs comidos ]
      in (cob, porGrupo)

-- | @datos/dieta.json@:
--
-- > {"version": 1, "grupos": [
-- >   {"id": "granos", "tope": "0.85", "tope_reserva": "1", "merma": "0.02",
-- >    "alimentos": {"maiz": "3650"}}, …]}
--
-- con las kilocalorías por kilogramo de cada alimento. Cada alimento tiene que
-- ser un bien conocido y estar en un solo grupo; el maíz tiene que estar,
-- porque su cosecha cierra el año. Acumula todos los errores.
cargarDieta :: Constantes -> Text -> [Text] -> Value -> Validacion Dieta
cargarDieta c archivo conocidos v = case A.parseEither leer v of
  Left e -> falla (ErrorCarga ErrorEstructura archivo "grupos" (T.pack e))
  Right gs ->
    let porId = sortOn (\(i, _, _, _, _) -> i) gs
        validos = traverse validar porId
        repetidos = [ i | (i, n) <- Map.toList (Map.fromListWith (+) [ (gid, 1 :: Int) | (gid, _, _, _, _) <- gs ]), n > 1 ]
        enVarios = [ b | (b, n) <- Map.toList (Map.fromListWith (+) [ (b, 1 :: Int) | (_, _, _, _, as) <- gs, b <- Map.keys as ]), n > 1 ]
        unicos = traverse_ (\i -> falla (ErrorCarga ErrorReferencia archivo ("grupos." <> i) "el grupo está repetido")) repetidos
        unaVez = traverse_ (\b -> falla (ErrorCarga ErrorReferencia archivo ("alimentos." <> b) "el alimento está en más de un grupo")) enVarios
        conMaiz = if any (\(_, _, _, _, as) -> Map.member bienAlimento as) gs then pure ()
                  else falla (ErrorCarga ErrorReferencia archivo "grupos" ("falta el maíz («" <> bienAlimento <> "»): su cosecha cierra el año"))
        noVacia = if null gs then falla (ErrorCarga ErrorEstructura archivo "grupos" "no hay grupos") else pure ()
    in (\g _ _ _ _ -> Dieta g (cNecesidadEnergia c) True) <$> validos <*> unicos <*> unaVez <*> conMaiz <*> noVacia
  where
    leer = A.withObject "dieta" $ \o -> do
      gs <- o A..: "grupos"
      traverse (A.withObject "grupo" $ \g ->
        (,,,,) <$> g A..: "id" <*> g A..: "tope" <*> g A..: "tope_reserva" <*> g A..: "merma"
               <*> (g A..: "alimentos" :: A.Parser (Map Text Fijo))) gs
    validar (gid, tope, rho, merma, as) =
      let ruta x = "grupos." <> gid <> "." <> x
          rango x lo hi incluyeLo nombre
            | (if incluyeLo then x >= lo else x > lo) && x <= hi = pure ()
            | otherwise = falla (ErrorCarga ErrorRango archivo (ruta nombre) (nombre <> " fuera de rango"))
          idOk | T.null gid || T.any (== '.') gid = falla (ErrorCarga ErrorEstructura archivo (ruta "id") "el id no puede estar vacío ni tener puntos")
               | otherwise = pure ()
          mermaOk = if merma >= Fijo 0 && merma < uno then pure ()
                    else falla (ErrorCarga ErrorRango archivo (ruta "merma") "la merma va de 0 a menos de 1")
          alimento (b, k)
            | k <= Fijo 0 = falla (ErrorCarga ErrorRango archivo (ruta ("alimentos." <> b)) "las kilocalorías tienen que ser positivas")
            | b `notElem` conocidos = falla (ErrorCarga ErrorReferencia archivo (ruta ("alimentos." <> b)) ("no existe el bien «" <> b <> "»"))
            | otherwise = pure (b, k ./. cKcalMaiz c)
      in (\_ _ _ _ es -> GrupoDieta gid tope rho (Just merma) (Map.fromList es))
           <$> idOk <*> rango tope (Fijo 0) uno False "tope" <*> rango rho (Fijo 0) uno True "tope_reserva" <*> mermaOk
           <*> traverse alimento (Map.toList as)
    traverse_ f = fmap (const ()) . traverse f
