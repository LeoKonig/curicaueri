{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Los procesos de las tecnologías (V5, *Recursos, bienes con usos y
-- procesos* y *Los procesos de una tecnología*; documento funcional, sección
-- 12, *Recursos, bienes y procesos*; T28).
--
-- No hay un archivo de recetas: cada conocimiento (@conocimientos@ de
-- @datos/edificios.json@, el mismo objeto que el oficio de las obras) declara
-- los procesos que hace posibles. Un proceso de celda trabaja un terreno
-- (la milpa en el llano); uno de casa da un poco por persona sin ocupar
-- tierra (el solar, el tejido en casa). Un proceso existe para una facción si
-- su dominio del conocimiento llega al dominio mínimo del proceso, y rinde en
-- proporción a ese dominio.
--
-- Qué proceso trabaja cada celda se decide en dos pasos ('elegirCeldas'):
-- primero la comida, con las celdas que más energía dan por trabajador hasta
-- cubrir lo que come la gente más el tributo; después el valor, con lo que más
-- vale por trabajador. Así nadie deja la milpa para minar obsidiana mientras
-- pasa hambre.
module Reglas.Procesos
  ( LugarProceso (..)
  , Proceso (..)
  , leerProceso
  , validarProceso
  , validarProcesosDelTerritorio
  , bienesDeProcesos
  , magCodificado
  , magTacito
  , rangoConocimiento
  , dominioBase
  , dominioEn
  , opcionesDeCelda
  , elegirCeldas
  ) where

import Data.Aeson (Value)
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import Data.IntSet (IntSet)
import Data.List (foldl', sortOn)
import Data.Ord (Down (..))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Carga (CategoriaError (..), ErrorCarga (..), Validacion, falla)
import Motor.Magnitudes
import Reglas.Base
import Reglas.Estado

data LugarProceso = EnCelda | EnCasa
  deriving (Eq, Show)

-- | Un proceso de bienes de una tecnología. Los productos son por
-- trabajador y año (de celda) o por persona y año (de casa).
data Proceso = Proceso
  { prId            :: Text
  , prTecnologia    :: Text
  , prLugar         :: LugarProceso
  , prTerrenos      :: [Text]          -- ^ de celda: dónde se usa
  , prTrabajadores  :: Fijo            -- ^ de celda: los que trabajan la celda entera
  , prProductos     :: Map Text Fijo
  , prDominioMinimo :: Fijo            -- ^ de 0 a 100
  } deriving (Eq, Show)

-- | Un proceso de @procesos@ de un conocimiento:
--
-- > {"id": "milpa_temporal", "lugar": "celda", "terrenos": ["llano"], "trabajadores": "3500",
-- >  "productos": {"maiz": "1", "frijol": "0.15"}, "dominio_minimo": "50"}
leerProceso :: Text -> Value -> A.Parser Proceso
leerProceso tec = A.withObject "proceso" $ \o -> do
  i <- o A..: "id"
  lugar <- o A..: "lugar" >>= \l -> case (l :: Text) of
    "celda" -> pure EnCelda
    "casa"  -> pure EnCasa
    _       -> fail ("lugar desconocido (celda o casa): " <> T.unpack l)
  Proceso i tec lugar <$> o A..:? "terrenos" A..!= [] <*> o A..:? "trabajadores" A..!= Fijo 0
                      <*> o A..: "productos" <*> o A..:? "dominio_minimo" A..!= fi 50

-- | Lo que se puede comprobar sin el territorio: rangos y forma, con todos los
-- errores.
validarProceso :: Text -> Proceso -> Validacion ()
validarProceso archivo pr =
  let ruta x = "conocimientos." <> prTecnologia pr <> ".procesos." <> prId pr <> "." <> x
      err r m = falla (ErrorCarga ErrorRango archivo (ruta r) m)
      productos | Map.null (prProductos pr) = err "productos" "el proceso no produce nada"
                | any (< Fijo 0) (Map.elems (prProductos pr)) = err "productos" "un producto no puede ser negativo"
                | otherwise = pure ()
      dominio | prDominioMinimo pr >= Fijo 0 && prDominioMinimo pr <= fi 100 = pure ()
              | otherwise = err "dominio_minimo" "fuera de 0..100"
      lugar = case prLugar pr of
        EnCelda | null (prTerrenos pr) -> err "terrenos" "un proceso de celda necesita sus terrenos"
                | prTrabajadores pr <= Fijo 0 -> err "trabajadores" "un proceso de celda necesita trabajadores"
                | otherwise -> pure ()
        EnCasa  | not (null (prTerrenos pr)) || prTrabajadores pr /= Fijo 0 ->
                    err "lugar" "un proceso de casa no tiene terrenos ni trabajadores por celda"
                | otherwise -> pure ()
  in productos *> dominio *> lugar

-- | Cada terreno que nombra un proceso tiene que existir en la tabla de
-- terrenos. Sin tabla no se comprueba nada.
validarProcesosDelTerritorio :: Text -> [Text] -> [Proceso] -> Validacion ()
validarProcesosDelTerritorio archivo terrenos procs
  | null terrenos = pure ()
  | otherwise = () <$ traverse falta
      [ (pr, t) | pr <- procs, t <- prTerrenos pr, t `notElem` terrenos ]
  where
    falta (pr, t) = falla (ErrorCarga ErrorReferencia archivo
                            ("conocimientos." <> prTecnologia pr <> ".procesos." <> prId pr <> ".terrenos")
                            ("terreno que la tabla de terrenos no tiene: " <> t))

-- | Los bienes que dan los procesos, en orden alfabético.
bienesDeProcesos :: [Proceso] -> [Text]
bienesDeProcesos ps = Map.keys (Map.unions (map prProductos ps))

magCodificado, magTacito :: Text -> Magnitud
magCodificado k = Magnitud ("conocimiento." <> k <> ".codificado")
magTacito k     = Magnitud ("conocimiento." <> k <> ".tacito")

rangoConocimiento :: RangoMag
rangoConocimiento = RangoMag (Fijo 0) (fi 100)

-- | El dominio con las bases (sin modificadores), para el derivado, que se
-- calcula desde lo persistente: el mínimo del codificado y el tácito.
dominioBase :: Almacen -> FaccionId -> Text -> Fijo
dominioBase alm f k = min (b (magCodificado k)) (b (magTacito k))
  where b m = maybe (Fijo 0) almacenBase (Map.lookup (entFac f, m) alm)

-- | El dominio con los valores efectivos (fórmula @dominio_tecnologia@).
dominioEn :: IntSet -> Tick -> Almacen -> FaccionId -> Text -> Fijo
dominioEn vig t alm f k = min (v (magCodificado k)) (v (magTacito k))
  where v m = maybe (Fijo 0) (valorEn vig t rangoConocimiento) (Map.lookup (entFac f, m) alm)

-- | Las maneras de trabajar un componente de una celda para una facción: la
-- del terreno (si rinde algo) y cada proceso de celda de ese terreno que la
-- facción domina, con su rendimiento por periodo escalado por el dominio.
-- @periodos@ son los periodos del año y @s@ la fracción del componente (T36):
-- el proceso pide s veces sus trabajadores y da s veces lo suyo.
opcionesDeCelda :: Fijo -> (Text -> Fijo) -> [Proceso] -> Int -> Text -> Fijo -> Maybe CeldaTrabajo -> [CeldaTrabajo]
opcionesDeCelda periodos dom procs cel terreno s porTerreno =
  maybe [] pure porTerreno ++
  [ CeldaTrabajo cel l
      (Map.map (\r -> l .*. r ./. periodos .*. (d ./. fi 100)) (prProductos pr))
      (Just (prId pr)) terreno
  | pr <- procs, prLugar pr == EnCelda, terreno `elem` prTerrenos pr
  , let d = dom (prTecnologia pr), d >= prDominioMinimo pr, d > Fijo 0
  , let l = if s == uno then prTrabajadores pr else s .*. prTrabajadores pr, l > Fijo 0 ]

-- | El orden en que un altépetl trabaja sus celdas, con la manera de trabajar
-- cada una. Primero la comida: las celdas por energía por trabajador (con su
-- mejor manera para comer), mientras falte energía para el objetivo y queden
-- trabajadores. Después el valor: las demás por valor por trabajador. Cada
-- lista de @opciones@ es un componente de una celda (T36): lo que se ordena
-- son los componentes, y los empates van por id de celda y luego por terreno
-- del componente; entre maneras de un componente, la que más da en
-- la medida del paso y, a igualdad, en la otra (la milpa da lo mismo que el
-- terreno en maíz, pero también frijol).
--
-- @energia@ y @valor@ dan lo que vale una unidad de cada bien (t ME y unidades
-- de valor); @objetivo@ es la energía por periodo que la gente necesita
-- cosechar (lo que come más lo que tributa) y @w@ los trabajadores.
elegirCeldas :: Map Text Fijo -> Map Text Fijo -> Fijo -> Int -> [[CeldaTrabajo]] -> [CeldaTrabajo]
elegirCeldas energia valor objetivo w opciones =
  let por m ct = foldl' (.+.) (Fijo 0) [ y .*. Map.findWithDefault (Fijo 0) b m | (b, y) <- Map.toList (ctRendimiento ct) ]
      -- Lo que da cada manera, calculado una sola vez: energía total, y
      -- energía y valor por trabajador (V5 a escala: con la mezcla hay hasta
      -- cuatro componentes por celda, y esto se recorre cada periodo).
      anotar ct = let e = por energia ct
                  in (ct, e, e ./. ctTrabajadores ct, por valor ct ./. ctTrabajadores ct)
      anotadas = map (map anotar) opciones
      -- Entre maneras de una celda: la que más da por trabajador en la
      -- medida principal y, a igualdad, en la otra; si siguen iguales, la
      -- primera (la del terreno).
      mejor clave os = case os of
        [] -> Nothing
        (o : otras) -> Just (foldl' (\a x -> if clave x > clave a then x else a) o otras)
      porEnergia (_, _, e, v) = (e, v)
      porValor (_, _, e, v) = (v, e)
      orden clave = sortOn (\o@(ct, _, _, _) -> (Down (fst (clave o)), ctCelda ct, ctTerreno ct))
      comida = orden porEnergia [ o | os <- anotadas, Just o@(_, e, _, _) <- [mejor porEnergia os], e > Fijo 0 ]
      tomar _ _ [] = []
      tomar e l ((c, ec, _, _) : cs)
        | e >= objetivo || l >= fi w = []
        | otherwise = c : tomar (e .+. ec) (l .+. ctTrabajadores c) cs
      primero = tomar (Fijo 0) (Fijo 0) comida
      usadas = Set.fromList [ (ctCelda o, ctTerreno o) | o <- primero ]
      resto = [ ct | (ct, _, _, _) <- orden porValor [ o | os <- anotadas, Just o@(ct, _, _, _) <- [mejor porValor os]
                                                       , not (Set.member (ctCelda ct, ctTerreno ct) usadas) ] ]
  in primero ++ resto
