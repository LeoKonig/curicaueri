{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Grupos de poder y nombramientos (V5, *Política interna* y *Los
-- nombramientos mueven poder*; documento funcional, sección 14d).
--
-- Los grupos son datos (@datos/grupos.json@): sus ids, su poder y su lealtad
-- de partida por tipo de facción, qué grupos pretende cada cargo y cuánto
-- mueve un nombramiento. Cada grupo tiene dos magnitudes de la facción,
-- @faccion.grupo.<id>.poder@ y @faccion.grupo.<id>.lealtad@. Su base la
-- escribe solo el escenario; los nombramientos aportan modificadores sin fin
-- que se quitan al destituir o reemplazar.
module Reglas.Grupos
  ( Grupos (..)
  , BaseGrupo (..)
  , gruposVacios
  , cargarGrupos
  , magPoder
  , magLealtad
  , catalogoGrupos
  , conGrupos
  , cargoGobernador
  , fuenteNombramiento
  , nombrar
  , quitarNombramiento
  , agregarVarios
  ) where

import Data.Aeson (Value)
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import Data.List (foldl', nub)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Carga (CategoriaError (..), ErrorCarga (..), Validacion (..), falla)
import Motor.Estado
import Motor.Hechos
import Motor.Juego (hechoModificadorTerminado)
import Motor.Magnitudes
import Reglas.Base
import Reglas.Estado

data BaseGrupo = BaseGrupo { bgPoder :: Fijo, bgLealtad :: Fijo }
  deriving (Eq, Show)

data Grupos = Grupos
  { grIds          :: [Text]                          -- ^ en el orden del archivo
  , grBases        :: Map Text (Map Text BaseGrupo)   -- ^ tipo de facción → grupo → base
  , grPretendientes :: Map Text [Text]                -- ^ cargo → grupos que lo pretenden
  , grPoderCargo   :: Fijo                            -- ^ π, @PODER_POR_CARGO@
  , grLealtadCargo :: Fijo                            -- ^ λ: lealtad del grupo del nombrado
  , grLealtadPerdida :: Fijo                          -- ^ λ': lealtad de cada pretendiente que pierde
  } deriving (Eq, Show)

-- | Sin archivo de grupos: nombrar un gobernador no mueve poder de nadie.
gruposVacios :: Grupos
gruposVacios = Grupos [] Map.empty Map.empty (Fijo 0) (Fijo 0) (Fijo 0)

magPoder, magLealtad :: Text -> Magnitud
magPoder g   = Magnitud ("faccion.grupo." <> g <> ".poder")
magLealtad g = Magnitud ("faccion.grupo." <> g <> ".lealtad")

rangoGrupo :: RangoMag
rangoGrupo = RangoMag (Fijo 0) (fi 100)

-- | Las dos magnitudes de cada grupo, para el catálogo del juego.
catalogoGrupos :: Grupos -> Map Magnitud DefMagnitud
catalogoGrupos gs = Map.fromList
  [ (m, DefMagnitud n rangoGrupo ("m." <> n) Nothing False)
  | g <- grIds gs, m@(Magnitud n) <- [magPoder g, magLealtad g] ]

-- | Carga @grupos.json@ acumulando todos los errores: grupos repetidos, un
-- tipo de facción al que le falta un grupo o que nombra uno desconocido,
-- bases fuera de [0, 100], pretendientes desconocidos y constantes negativas.
cargarGrupos :: Text -> Value -> Validacion Grupos
cargarGrupos archivo v = case A.parseEither leer v of
  Left err -> falla (ErrorCarga ErrorEstructura archivo "" (T.pack err))
  Right (ids, bases, cargos, pc, lc, lp) ->
    let err cat ruta msg = falla (ErrorCarga cat archivo ruta msg)
        siNo c e = if c then pure () else e
        repetidos = traverse (\g -> siNo (length (filter (== g) ids) == 1)
                                      (err ErrorEsquema ("grupos." <> g) "grupo repetido")) (nub ids)
        deTipo (tipo, porGrupo) =
          traverse (\g -> siNo (Map.member g porGrupo)
                              (err ErrorEsquema ("bases." <> tipo <> "." <> g) "falta la base de este grupo")) (nub ids)
          *> traverse (\(g, b) ->
                 let ruta = "bases." <> tipo <> "." <> g
                 in siNo (g `elem` ids) (err ErrorReferencia ruta "grupo desconocido")
                    *> siNo (enRango (bgPoder b)) (err ErrorRango (ruta <> ".poder") "fuera de 0..100")
                    *> siNo (enRango (bgLealtad b)) (err ErrorRango (ruta <> ".lealtad") "fuera de 0..100"))
               (Map.toList porGrupo)
        deCargo (cargo, ps) =
          traverse (\g -> siNo (g `elem` ids)
                              (err ErrorReferencia ("cargos." <> cargo <> ".pretendientes") ("grupo desconocido: " <> g))) ps
        constante nombre x = siNo (x >= Fijo 0) (err ErrorRango nombre "no puede ser negativa")
    in Grupos ids bases cargos pc lc lp
         <$ repetidos
         <* traverse deTipo (Map.toList bases)
         <* traverse deCargo (Map.toList cargos)
         <* constante "poder_por_cargo" pc
         <* constante "lealtad_por_cargo" lc
         <* constante "lealtad_por_cargo_perdido" lp
  where
    enRango x = x >= Fijo 0 && x <= fi 100
    leer = A.withObject "grupos" $ \o -> do
      ids    <- o A..: "grupos"
      bases  <- o A..: "bases" >>= traverse (traverse baseGrupo)
      cargos <- o A..: "cargos" >>= traverse (A.withObject "cargo" (A..: "pretendientes"))
      (,,,,,) ids bases cargos <$> o A..: "poder_por_cargo" <*> o A..: "lealtad_por_cargo"
                               <*> o A..: "lealtad_por_cargo_perdido"
    baseGrupo = A.withObject "base" $ \o -> BaseGrupo <$> o A..: "poder" <*> o A..: "lealtad"

-- ---------------------------------------------------------------------------
-- Nombramientos
-- ---------------------------------------------------------------------------

cargoGobernador :: Text
cargoGobernador = "gobernador"

-- | La fuente de los modificadores de un nombramiento. El documento funcional
-- la escribe @nombramiento:<p>:<k>@; aquí el cargo k lleva su tipo y su
-- entidad (@gobernador:<altépetl>@) para que el gobierno de un altépetl y,
-- más adelante, una capitanía con el mismo número no se confundan.
fuenteNombramiento :: PerId -> AltId -> Fuente
fuenteNombramiento (PerId p) (AltId a) =
  Fuente "nombramiento" (T.pack (show p) <> ":" <> cargoGobernador <> ":" <> T.pack (show a))

-- | Los modificadores que añade nombrar a p en el gobierno de un altépetl
-- (sección 14d): poder y lealtad del grupo del nombrado, y lealtad negativa
-- de cada otro grupo que pretendía el cargo. Si el personaje no tiene grupo,
-- ninguno. Son modificadores sin fin: el aporte es constante mientras dura
-- el cargo, así que mantenerlo no acumula poder.
modsNombramiento :: Grupos -> Personaje -> AltId -> [Modificador]
modsNombramiento gs per alt = case perGrupo per of
  Nothing -> []
  Just g ->
    [ mk (magPoder g) (grPoderCargo gs), mk (magLealtad g) (grLealtadCargo gs) ]
    ++ [ mk (magLealtad o) (negar (grLealtadPerdida gs))
       | o <- Map.findWithDefault [] cargoGobernador (grPretendientes gs), o /= g ]
  where
    negar (Fijo x) = Fijo (negate x)
    mk m x = Modificador 0 m entFaccion (Aporte x (Fijo 0))
                         (fuenteNombramiento (perId per) alt) Nothing Nothing Nothing AlcancePropia

-- | Pone a p en el gobierno del altépetl. Quien gobernaba antes pierde el
-- cargo y sus modificadores terminan. No valida: lo hace el comando.
nombrar :: Grupos -> Tick -> AltId -> Personaje -> Estado Purepecha -> (Estado Purepecha, [Hecho])
nombrar gs t alt per est0 =
  let (est1, hs) = quitarNombramiento gs t alt est0
      p    = estadoPersistente est1
      jue  = persistenteJuego p
      com  = persistenteComun p
      jue' = jue { ppAltepetl = Map.adjust (\a -> a { altGobernador = Just (perId per) }) alt (ppAltepetl jue) }
      alm' = agregarVarios (modsNombramiento gs per alt) (comunMagnitudes com)
  in (est1 { estadoPersistente = p { persistenteJuego = jue', persistenteComun = com { comunMagnitudes = alm' } } }, hs)

-- | Añade modificadores con ids nuevos consecutivos, en orden, como lo haría
-- 'agregarModificador' uno a uno, pero calculando el siguiente id una sola vez.
agregarVarios :: [Modificador] -> Almacen -> Almacen
agregarVarios ms alm0 = Map.unionWith juntar alm0 nuevos
  where
    -- Agrupados por (entidad, magnitud) y en su orden: cada lista se pega una vez.
    nuevos = Map.map (AlmacenMag (Fijo 0)) (Map.fromListWith (flip (++))
               [ ((modEntidad m, modMagnitud m), [m { modId = i }])
               | (i, m) <- zip [siguienteModId alm0 ..] ms ])
    juntar viejo nuevo = viejo { almacenMods = almacenMods viejo ++ almacenMods nuevo }

-- | Deja vacante el gobierno del altépetl. Los modificadores del nombramiento
-- se quitan del almacén y cada uno emite @modificador_terminado@ con la razón
-- @fuente@ ("su fuente desapareció"). Solo se miran las magnitudes de los
-- grupos de la facción, no todo el almacén.
quitarNombramiento :: Grupos -> Tick -> AltId -> Estado Purepecha -> (Estado Purepecha, [Hecho])
quitarNombramiento gs t alt est =
  case Map.lookup alt (ppAltepetl jue) >>= altGobernador of
    Nothing -> (est, [])
    Just per ->
      let fuente = fuenteNombramiento per alt
          claves = [ (entFaccion, m) | g <- grIds gs, m <- [magPoder g, magLealtad g] ]
          quitar (alm, acc) k = case Map.lookup k alm of
            Nothing -> (alm, acc)
            Just x  -> let (fuera, quedan) = partirPor ((== fuente) . modFuente) (almacenMods x)
                       in (Map.insert k x { almacenMods = quedan } alm, acc ++ fuera)
          (alm', terminados) = foldl' quitar (comunMagnitudes com, []) claves
          jue' = jue { ppAltepetl = Map.adjust (\a -> a { altGobernador = Nothing }) alt (ppAltepetl jue) }
      in ( est { estadoPersistente = p { persistenteJuego = jue', persistenteComun = com { comunMagnitudes = alm' } } }
         , map (hechoModificadorTerminado t "fuente") terminados )
  where
    p   = estadoPersistente est
    jue = persistenteJuego p
    com = persistenteComun p
    partirPor f xs = (filter f xs, filter (not . f) xs)

-- | El escenario con sus grupos: escribe la base de poder y lealtad de cada
-- grupo para el tipo de facción y aplica los nombramientos con que empieza
-- (los gobernadores del escenario), para que destituir a uno devuelva su
-- grupo a la base. Falla si el tipo no está en el archivo o si un personaje
-- tiene un grupo que el archivo no declara.
conGrupos :: Text -> Grupos -> Text -> Estado Purepecha -> Validacion (Estado Purepecha)
conGrupos archivo gs tipo est
  | null (grIds gs) = pure est
  | otherwise = case Map.lookup tipo (grBases gs) of
      Nothing -> falla (ErrorCarga ErrorReferencia archivo ("bases." <> tipo) "el escenario usa un tipo de facción sin bases")
      Just bases ->
        let jue = persistenteJuego (estadoPersistente est)
            desconocidos = [ (perId pe, g) | pe <- Map.elems (ppPersonajes jue), Just g <- [perGrupo pe]
                                           , g `notElem` grIds gs ]
            comprobar (PerId i, g) = falla (ErrorCarga ErrorReferencia archivo ("personajes." <> T.pack (show i))
                                              ("grupo desconocido: " <> g))
            conBases e = Map.foldlWithKey' (\acc g b ->
                            fijarBase entFaccion (magLealtad g) (bgLealtad b)
                              (fijarBase entFaccion (magPoder g) (bgPoder b) acc)) e bases
            p    = estadoPersistente est
            com  = persistenteComun p
            est1 = est { estadoPersistente = p { persistenteComun = com { comunMagnitudes = conBases (comunMagnitudes com) } } }
            iniciales = mapMaybe (\a -> (,) (altId a) <$> (altGobernador a >>= (`Map.lookup` ppPersonajes jue)))
                                 (Map.elems (ppAltepetl jue))
            -- El gobernador ya está puesto: solo se añaden sus modificadores, todos
            -- de una vez (con miles de altépetl, añadirlos uno a uno recorrería el
            -- almacén por cada uno).
            p1   = estadoPersistente est1
            c1   = persistenteComun p1
            est2 = est1 { estadoPersistente = p1 { persistenteComun = c1 { comunMagnitudes =
                     agregarVarios (concatMap (\(alt, pe) -> modsNombramiento gs pe alt) iniciales) (comunMagnitudes c1) } } }
            p2   = estadoPersistente est2
        in est2 { estadoOrigen = Origen (estadoTick est2) p2 } <$ traverse comprobar desconocidos
