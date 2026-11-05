{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Producción de bienes por territorio (V5, *La tierra y la gente* y
-- *Población, asentamientos y territorio*; documento funcional, sección 12;
-- hito 3).
--
-- Cada altépetl trabaja las celdas que le asigna 'asignarCeldas' (las más
-- cercanas a su cabecera, dentro de 'cRadioProduccion'). Una celda rinde,
-- trabajada entera, los bienes de su terreno ('dtRendimiento') y necesita
-- 'dtTrabajadores' para ello. La producción la manda el factor escaso:
--
-- > Q_a = Σ_k y(c_k) · min(1, max(0, W_a − Σ_{j<k} ℓ(c_j)) / ℓ(c_k)) · (1 + Σ p)
--
-- con las celdas ordenadas por y/ℓ de mayor a menor (empate por id): los
-- trabajadores van primero a las mejores. W_a son los trabajadores del
-- altépetl, la fracción 'cFraccionTrabajadora' de sus pops productivos (todos
-- menos la nobleza), y (1 + Σ p) es su magnitud @produccion@, donde las obras
-- aportan sus porcentajes. Con varios bienes por celda, y es la suma de sus
-- rendimientos, sin pesos: los bienes todavía no tienen valor en el juego
-- (la moneda real es la tarea siguiente).
--
-- Qué celdas trabaja cada altépetl es estado derivado del paso 16: se
-- recalcula al empezar el periodo y lo lee la producción del periodo
-- siguiente, igual que el resto del derivado.
module Reglas.Produccion
  ( bienesDe
  , catalogoBienes
  , magCosecha
  , cosechaEn
  , azarCosecha
  , validarBienesDelTerritorio
  , lecturasMoneda
  , Cosecha (..)
  , Cosechas (..)
  , cargarCosechas
  , enVentana
  , diasVentana
  , factorCosecha
  , cierraVentana
  , derivarCeldas
  , derivarTerritorio
  , ConProcesos (..)
  , derivarTerritorioCon
  , derivarTerritorioMej
  , composicionEn
  , bienesConProcesos
  , celdaTrabajo
  , ordenarCeldas
  , trabajadoresDe
  , trabajadoresBrutos
  , retiradosDe
  , produccionCeldas
  , totalProduccion
  , produccion
  ) where

import Data.Aeson (Value)
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import Data.List (foldl', sortBy)
import Data.IntSet (IntSet)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.IntMap.Strict as IntMap
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Estado
import Motor.Magnitudes
import Motor.Mapa (Mapa (..), Terreno (..), composicionDe)
import Motor.Azar (uniforme)
import Motor.Calendario (CalendarioInterno (..), CalendarioVisible, Fecha, InfoPeriodo (..), diaDelAnioDe, diaDelAnioVisible, infoPeriodo)
import Motor.Carga (CategoriaError (..), ErrorCarga (..), Validacion, falla)
import Motor.Moneda (Bien (..), Economia (..), magExistencias, magMerma, magProduccion, mermaEn, rangoMerma)
import Motor.Recorrido (Grafo, asignarCeldas, grafoDe)
import Motor.Sistema
import Motor.Terrenos (DefTerreno (..), MaterialTerreno (..))
import Reglas.Base
import Reglas.Constantes
import Reglas.Dieta (Dieta (..), GrupoDieta (..), grupoDe, magCosechadoDe)
import Reglas.Estado
import Reglas.Procesos (LugarProceso (..), Proceso (..), bienesDeProcesos, dominioEn, elegirCeldas, opcionesDeCelda)

-- | Los bienes que el territorio puede producir: los que aparece en el
-- rendimiento de algún terreno, en orden alfabético.
bienesDe :: Map Terreno DefTerreno -> [Text]
bienesDe t = Map.keys (Map.unions (map dtRendimiento (Map.elems t)))

-- | Cada bien de la economía (@datos/bienes_<escenario>.json@) tiene que ser
-- uno que produzca el territorio: el precio se lee de sus existencias y su
-- producción, y un bien con otro nombre («manta») tendría siempre cero y un
-- precio fijo sin que nadie lo note. Acumula un error por bien. Los bienes
-- producidos son los de los terrenos y los de los procesos ('bienesConProcesos');
-- sin ninguno no hay producción y no se comprueba nada.
validarBienesDelTerritorio :: Text -> [Text] -> Economia -> Validacion ()
validarBienesDelTerritorio archivo producidos ec
  | null producidos = pure ()
  | otherwise = () <$ traverse falta [ b | b <- Map.keys (ecoBienes ec), b `notElem` producidos ]
  where
    falta b = falla (ErrorCarga ErrorReferencia archivo ("bienes." <> b)
                       ("el territorio no produce «" <> b <> "»; produce " <> T.intercalate ", " producidos))

-- | Lo que lee quien convierte entre valor y moneda ('Motor.Moneda.enCuenta',
-- 'Motor.Moneda.aValor'): las existencias y la producción de los bienes que
-- pueden ser moneda, de las que sale su precio. Va en el 'sisLee' de cada
-- sistema que escribe el tesoro.
lecturasMoneda :: Economia -> Set.Set Magnitud
lecturasMoneda ec = Set.fromList
  [ m | b <- Map.elems (ecoBienes ec), bnDesignable b, m <- [magExistencias (bnId b), magProduccion (bnId b)] ]

rangoBien :: RangoMag
rangoBien = RangoMag (fi 0) (fi 1000000000)

-- | Existencias, producción y merma de cada bien, magnitudes de la facción
-- (CLAUDE.md, *Bienes como magnitudes de la facción*). La merma tiene dos
-- escritores: la producción escribe su base (la del catálogo de bienes) y la
-- construcción los modificadores de las trojes.
--
-- Las existencias tienen dos escritores: la producción las suma cada periodo
-- y un efecto del guion las gasta ('Reglas.Propios', @consumir_bien@). La
-- cosecha del año ('magCosecha') también tiene dos: la producción escribe su
-- base (1) y el azar del año ('azarCosecha') su modificador.
catalogoBienes :: [Text] -> Map Magnitud DefMagnitud
catalogoBienes bs = Map.fromList $
  [ (magProduccion b, DefMagnitud n rangoBien ("m." <> n) Nothing False) | b <- bs, let Magnitud n = magProduccion b ]
  ++ [ (magExistencias b, DefMagnitud n rangoBien ("m." <> n) Nothing True) | b <- bs, let Magnitud n = magExistencias b ]
  ++ [ (m, DefMagnitud n rangoMerma ("m." <> n) Nothing True) | b <- bs, let m@(Magnitud n) = magMerma b ]
  ++ [ (m, DefMagnitud n rangoCosecha ("m." <> n) Nothing True) | b <- bs, let m@(Magnitud n) = magCosecha b ]

-- | La cosecha del año de un bien con ventana, por facción: el factor sobre
-- la cosecha normal. La base es 1 y el azar del año ('azarCosecha') pone un
-- modificador con su fuente, así que el desglose dice cuánto fue el azar.
magCosecha :: Text -> Magnitud
magCosecha b = Magnitud ("bien." <> b <> ".cosecha")

rangoCosecha :: RangoMag
rangoCosecha = RangoMag (fi 0) (fi 10)

-- | El factor de cosecha efectivo del bien para la facción; 1 si nada lo ha
-- escrito (un guardado anterior, o un escenario sin azar).
cosechaEn :: IntSet -> Tick -> Almacen -> EntRef -> Text -> Fijo
cosechaEn vig t alm ent b = maybe uno (valorEn vig t rangoCosecha) (Map.lookup (ent, magCosecha b) alm)

-- ---------------------------------------------------------------------------
-- Cosecha por estación
-- ---------------------------------------------------------------------------

-- | La ventana de cosecha de un bien, en días del año visible (1 a 365,
-- 'diaDelAnioDe'), los dos incluidos. Si @desde@ es mayor que @hasta@, la
-- ventana cruza el fin de año.
data Cosecha = Cosecha { coDesde :: Int, coHasta :: Int }
  deriving (Eq, Show)

enVentana :: Cosecha -> Int -> Bool
enVentana (Cosecha a b) d
  | a <= b    = a <= d && d <= b
  | otherwise = d >= a || d <= b

diasVentana :: Cosecha -> Int
diasVentana (Cosecha a b)
  | a <= b    = b - a + 1
  | otherwise = 365 - a + 1 + b

-- | Las ventanas de cosecha y cómo se lee la fecha visible de un tick (V5,
-- *Temporada de guerra y guerra ritual*: la estación sale del día del año de
-- la fecha visible, no de la veintena, porque el año interno se desfasa).
-- Un bien sin ventana se produce parejo todo el año, como antes.
data Cosechas = Cosechas
  { csVentanas :: Map Text Cosecha
  , csVisible  :: CalendarioVisible
  , csInicio   :: Fecha               -- ^ fecha visible del tick 0
  }

-- | Qué parte de la cosecha del año entra en el periodo que empieza en @t@,
-- como factor sobre la producción de una veintena pareja:
--
-- > periodos por año · días del periodo dentro de la ventana / días de la ventana
--
-- El periodo va de @t@ al inicio del siguiente (el último del año lleva
-- también los días fuera de periodo), así que los periodos cubren todos los
-- días y en un año se cosecha lo de los periodos del año: lo mismo que con
-- la producción pareja, salvo el redondeo.
factorCosecha :: CalendarioInterno -> Cosechas -> Cosecha -> Tick -> Fijo
factorCosecha cal cs co (Tick t) =
  let ip = infoPeriodo cal (Tick t)
      largo = ciDiasPorPeriodo cal + (if ipPeriodo ip == ciPeriodosPorAnio cal then ciDiasFuera cal else 0)
      dentro = length [ () | k <- [0 .. largo - 1]
                           , enVentana co (diaDelAnioVisible (csVisible cs) (csInicio cs) (Tick (t + fromIntegral k))) ]
  in desdeEntero (ciPeriodosPorAnio cal * dentro) ./. desdeEntero (diasVentana co)

-- | ¿Se cierra la ventana de cosecha en el periodo que empieza en @t@? Es
-- cierto en el único periodo de cada año que contiene el último día de la
-- ventana (@hasta@): ahí termina la cosecha y se cuenta la cobertura del año
-- (V5, *Comer antes de tributar*).
cierraVentana :: CalendarioInterno -> Cosechas -> Cosecha -> Tick -> Bool
cierraVentana cal cs co (Tick t) =
  let ip = infoPeriodo cal (Tick t)
      largo = ciDiasPorPeriodo cal + (if ipPeriodo ip == ciPeriodosPorAnio cal then ciDiasFuera cal else 0)
  in or [ diaDelAnioVisible (csVisible cs) (csInicio cs) (Tick (t + fromIntegral k)) == coHasta co | k <- [0 .. largo - 1] ]

-- | Las ventanas de cosecha de @datos/terrenos.json@ (la clave @cosechas@,
-- opcional), con fechas «MM-DD» del calendario visible:
--
-- > "cosechas": {"maiz": {"desde": "10-15", "hasta": "11-30"}}
--
-- Cada bien tiene que ser uno del territorio. Acumula todos los errores.
cargarCosechas :: Text -> [Text] -> Value -> Validacion (Map Text Cosecha)
cargarCosechas archivo producidos v = case A.parseEither leer v of
  Left e   -> falla (ErrorCarga ErrorEstructura archivo "cosechas" (T.pack e))
  Right vs -> Map.fromList <$> traverse validar (Map.toList vs)
  where
    leer = A.withObject "terrenos" $ \o -> do
      m <- o A..:? "cosechas" A..!= (Map.empty :: Map Text Value)
      traverse (A.withObject "cosecha" (\c -> (,) <$> c A..: "desde" <*> c A..: "hasta")) m
    validar (b, (d, h)) =
      let ruta c = "cosechas." <> b <> "." <> c
          bienOk = if b `elem` producidos then pure ()
                   else falla (ErrorCarga ErrorReferencia archivo ("cosechas." <> b)
                                 ("el territorio no produce «" <> b <> "»"))
      in (\_ x y -> (b, Cosecha x y)) <$> bienOk <*> fecha (ruta "desde") d <*> fecha (ruta "hasta") h
    fecha ruta t = case map (reads . T.unpack) (T.splitOn "-" t) of
      [[(m, "")], [(d, "")]] | Just n <- diaDelAnioDe m d -> pure n
      _ -> falla (ErrorCarga ErrorRango archivo ruta ("fecha «" <> t <> "»: se espera MM-DD"))

-- | Un componente de una celda que se puede trabajar, con lo que pide y lo
-- que da: la celda @c@, el terreno @t@ del componente y su fracción @s@
-- (V5, *La celda como mezcla de terrenos*; T36). El componente es como una
-- celda chica de su terreno: pide s veces los trabajadores y da s veces lo
-- suyo, así que lo que da por trabajador no depende de s. Una celda de un
-- solo terreno es su único componente, con s = 1, y da lo de siempre.
celdaTrabajo :: Int -> Text -> Fijo -> DefTerreno -> Maybe CeldaTrabajo
celdaTrabajo c t s d
  | Map.null (dtRendimiento d) || l <= Fijo 0 = Nothing
  | otherwise = Just (CeldaTrabajo c l (Map.map (parteDe s) (dtRendimiento d)) Nothing t)
  where l = parteDe s (dtTrabajadores d)

-- | La parte @s@ de una cantidad; con s = 1, la cantidad misma, sin redondear.
parteDe :: Fijo -> Fijo -> Fijo
parteDe s x = if s == uno then x else s .*. x

-- | La composición de una celda: la que cambió una obra (la roturación, T38) o, si no,
-- la del mapa. 'Nothing' si no hay mapa o la celda no existe.
composicionEn :: Maybe Mapa -> Map Int [(Text, Fijo)] -> Int -> Maybe [(Text, Fijo)]
composicionEn mm cambios cel = case Map.lookup cel cambios of
  Just cs -> Just cs
  Nothing -> do
    m <- mm
    ce <- IntMap.lookup cel (mapaCeldas m)
    pure [ (t, s) | (Terreno t, s) <- composicionDe ce ]

-- | Los componentes que trabaja cada celda asignada: cada uno con su terreno,
-- su fracción y su definición. Un terreno sin definición no da nada. Las celdas
-- cuyo terreno cambió una obra usan la composición nueva.
componentesDe :: Map Terreno DefTerreno -> Mapa -> Map Int [(Text, Fijo)] -> Int -> [(Text, Fijo, DefTerreno)]
componentesDe tabla mapa cambios cel =
  [ (t, s, d) | Just comp <- [composicionEn (Just mapa) cambios cel], (t, s) <- comp, Just d <- [Map.lookup (Terreno t) tabla] ]

-- | Una celda trabajada, con el rendimiento multiplicado por la mejora de su celda.
-- Con mejora 1 no se toca nada (sin redondeo).
mejorada :: (Int -> Fijo) -> CeldaTrabajo -> CeldaTrabajo
mejorada mejora ct = let f = mejora (ctCelda ct)
                     in if f == uno then ct else ct { ctRendimiento = Map.map (.*. f) (ctRendimiento ct) }

-- | Las celdas de mejor a peor por y/ℓ, con empate por id de celda y luego por
-- terreno del componente. La comparación se hace en enteros, multiplicando en
-- cruz, para no redondear el cociente.
ordenarCeldas :: [CeldaTrabajo] -> [CeldaTrabajo]
ordenarCeldas = map snd . sortBy cmp . map (\c -> ((y c, l c), c))
  where
    -- y y ℓ se calculan una vez por componente, no en cada comparación.
    y c = sum [ fromIntegral r :: Integer | Fijo r <- Map.elems (ctRendimiento c) ]
    l c = let Fijo x = ctTrabajadores c in fromIntegral x :: Integer
    cmp ((ya, la), a) ((yb, lb), b) = compare (yb * la, ctCelda a, ctTerreno a) (ya * lb, ctCelda b, ctTerreno b)

-- | Qué celdas trabaja cada altépetl, ya ordenadas (ver 'derivarTerritorio').
derivarCeldas :: Constantes -> Map Terreno DefTerreno -> Mapa -> Purepecha -> Map AltId [CeldaTrabajo]
derivarCeldas c tabla mapa p = fst (derivarTerritorio c tabla mapa (grafoDe mapa) p)

-- | El derivado del paso 16 sobre el territorio, con una sola asignación de
-- celdas: qué celdas trabaja cada altépetl para producir bienes y de qué
-- celdas puede extraer cada material de obra, las dos ordenadas de la que
-- más rinde por trabajador a la que menos. Sin tabla de terrenos que rinda o
-- dé material, nada (y no se recorre el mapa).
derivarTerritorio :: Constantes -> Map Terreno DefTerreno -> Mapa -> Grafo -> Purepecha
                  -> (Map AltId [CeldaTrabajo], Map AltId (Map Text [CeldaTrabajo]))
derivarTerritorio = derivarTerritorioCon Nothing

-- | Los bienes que da el territorio: los de los terrenos y los de los
-- procesos de las tecnologías (T28), en orden alfabético.
bienesConProcesos :: Map Terreno DefTerreno -> [Proceso] -> [Text]
bienesConProcesos tabla procs = Map.keys (Map.fromList [ (b, ()) | b <- bienesDe tabla ++ bienesDeProcesos procs ])

-- | Lo que necesita la derivación para trabajar las celdas con los procesos
-- de las tecnologías (T28): los procesos, lo que vale cada bien en energía (t
-- ME, de la dieta) y en valor (del catálogo; sin catálogo, 1 por unidad), la
-- necesidad por persona y año, y el dominio de cada facción con las bases.
data ConProcesos = ConProcesos
  { cpProcesos  :: [Proceso]
  , cpEnergia   :: Map Text Fijo
  , cpValor     :: Map Text Fijo
  , cpNecesidad :: Fijo
  , cpDominio   :: FaccionId -> Text -> Fijo
  }

-- | 'derivarTerritorio' con los procesos de las tecnologías. Sin procesos de
-- celda, el orden de las celdas es el de antes (por toneladas por
-- trabajador): la ley «proceso neutro». Con ellos, cada altépetl elige la
-- manera de trabajar cada celda con 'elegirCeldas': primero la comida, hasta
-- lo que come su gente más el tributo en especie, y después el valor.
derivarTerritorioCon :: Maybe ConProcesos -> Constantes -> Map Terreno DefTerreno -> Mapa -> Grafo -> Purepecha
                     -> (Map AltId [CeldaTrabajo], Map AltId (Map Text [CeldaTrabajo]))
derivarTerritorioCon = derivarTerritorioMej (const uno)

-- | 'derivarTerritorioCon' con la mejora de rendimiento de cada celda (las terrazas,
-- T38): lo que da cada componente de la celda se multiplica por ella. Con mejora 1
-- en todas, es 'derivarTerritorioCon'.
derivarTerritorioMej :: (Int -> Fijo) -> Maybe ConProcesos -> Constantes -> Map Terreno DefTerreno -> Mapa -> Grafo -> Purepecha
                     -> (Map AltId [CeldaTrabajo], Map AltId (Map Text [CeldaTrabajo]))
derivarTerritorioMej mejora mcp c tabla mapa gr p
  | null (bienesDe tabla) && null deCelda && all (Map.null . dtMateriales) (Map.elems tabla) = (Map.empty, Map.empty)
  | not (null deCelda), Just cp <- mcp =
      let (_, mats) = sinProcesos
          ws = trabajadoresDe c p
          personas = Map.fromListWith (+) [ (popAltepetl pop, popTamano pop) | pop <- Map.elems (ppPops p) ]
          porAlt = Map.fromListWith (++)
                     [ (a, [(cel, t, s, d)]) | (a, cel, t, s, d) <- asignadas ]
          deAltepetl a celdas =
            let alt = Map.lookup a (ppAltepetl p)
                f = maybe (FaccionId 0) altFaccion alt
                tau = maybe (Fijo 0) (\fa -> cTributoEspecie c .*. fi (tasaTributo (facTasas fa))) (alt >>= \x -> Map.lookup (altFaccion x) (ppFacciones p))
                need = fi (Map.findWithDefault 0 a personas) .*. cpNecesidad cp
                objetivo = (need ./. (uno .-. tau)) ./. cTicksPorAnio c
                opciones = [ map (mejorada mejora) (opcionesDeCelda (cTicksPorAnio c) (cpDominio cp f) deCelda cel t s (celdaTrabajo cel t s d))
                           | (cel, t, s, d) <- celdas ]
            in elegirCeldas (cpEnergia cp) (cpValor cp) objetivo (Map.findWithDefault 0 a ws) [ os | os <- opciones, not (null os) ]
      in (Map.mapWithKey deAltepetl porAlt, mats)
  | otherwise = sinProcesos
  where
    deCelda = [ pr | Just cp <- [mcp], pr <- cpProcesos cp, prLugar pr == EnCelda ]
    fuentes = [ (AsentId i, CeldaId (altCelda a)) | a <- Map.elems (ppAltepetl p), let AltId i = altId a ]
    asig = asignarCeldas (cRadioProduccion c) gr fuentes
    asignadas = [ (AltId a, cel, t, s, d) | (cel, AsentId a) <- IntMap.toList asig, (t, s, d) <- componentesDe tabla mapa (ppTerrenos p) cel ]
    sinProcesos = derivarSinProcesos mejora asignadas

-- | Las celdas y los materiales de cada altépetl sin procesos de celda. Los
-- materiales de obra salen del componente que los tiene, con su fracción.
derivarSinProcesos :: (Int -> Fijo) -> [(AltId, Int, Text, Fijo, DefTerreno)] -> (Map AltId [CeldaTrabajo], Map AltId (Map Text [CeldaTrabajo]))
derivarSinProcesos mejora asignadas =
      let porAlt = Map.fromListWith (++)
                     [ (a, [mejorada mejora ct]) | (a, cel, t, s, d) <- asignadas, Just ct <- [celdaTrabajo cel t s d] ]
          mats = Map.fromListWith (Map.unionWith (++))
                   [ (a, Map.singleton g [CeldaTrabajo cel l (Map.singleton g (parteDe s (mtRendimiento mt))) Nothing t])
                   | (a, cel, t, s, d) <- asignadas, (g, mt) <- Map.toList (dtMateriales d)
                   , let l = parteDe s (mtTrabajadores mt), l > Fijo 0 ]
      in (Map.map ordenarCeldas porAlt, Map.map (Map.map ordenarCeldas) mats)

-- | Trabajadores de cada altépetl (sección 12):
--
-- > W_a = max(0, Σ ⌊N_p · φ⌋ − R_a)
--
-- sobre sus pops productivos (todos los estratos menos la nobleza y los
-- sacerdotes), sumados en una sola pasada por los pops. R_a son los
-- retirados ('retiradosDe'): hoy, las cuadrillas de sus obras.
trabajadoresDe :: Constantes -> Purepecha -> Map AltId Int
trabajadoresDe c p = let r = retiradosDe p
                     in Map.mapWithKey (\a w -> max 0 (w - Map.findWithDefault 0 a r)) (trabajadoresBrutos c p)

-- | Σ ⌊N_p · φ⌋, sin restar a los retirados.
trabajadoresBrutos :: Constantes -> Purepecha -> Map AltId Int
trabajadoresBrutos c p = Map.fromListWith (+)
  [ (popAltepetl pop, trabajadores pop) | pop <- Map.elems (ppPops p), not (estratoNoTrabaja (popEstrato pop)) ]
  where
    trabajadores pop = let Fijo x = fi (popTamano pop) .*. cFraccionTrabajadora c
                       in fromIntegral (x `div` escala)

-- | Los trabajadores retirados de la producción de cada altépetl
-- (@retirar_trabajadores@, V5). Hoy los motivos son la cuadrilla de una obra
-- (motivo @obra@) y la gente que un altépetl pone para enviarle tributo en
-- especie (motivo @tributo_obra@): salen con la obra y vuelven al terminarla,
-- así que basta con leerlos de las obras en curso. La leva del hito 4 sumará
-- su propio motivo.
retiradosDe :: Purepecha -> Map AltId Int
retiradosDe p = Map.fromListWith (+) $ concat
  [ (altId a, obCuadrilla o) : [ (toFuente tr, toCuadrilla tr) | tr <- Map.elems (obTributos o) ]
  | a <- Map.elems (ppAltepetl p), Just o <- [altObra a], obCuadrilla o > 0 ]

-- | La fórmula con nombre @produccion_por_factor_escaso@: lo que dan las
-- celdas (ya ordenadas) con W trabajadores, por bien, antes de las obras.
-- La celda que queda a medias se calcula con una sola división entera.
produccionCeldas :: Int -> [CeldaTrabajo] -> Map Text Fijo
produccionCeldas w celdas = snd (foldl' celda (fromIntegral w * escala, Map.empty) celdas)
  where
    celda (libres, acc) ct
      | libres <= 0 = (libres, acc)
      | otherwise =
          let Fijo l = ctTrabajadores ct
              aporte (Fijo yv)
                | libres >= l = Fijo yv
                | otherwise   = Fijo (fromIntegral ((fromIntegral yv * fromIntegral libres :: Integer) `div` fromIntegral l))
          in (libres - l, Map.unionWith (.+.) acc (Map.map aporte (ctRendimiento ct)))

-- | Q_a sin distinguir bienes: la cantidad que cumple la ley de monotonía.
totalProduccion :: Map Text Fijo -> Fijo
totalProduccion = foldl' (.+.) (Fijo 0) . Map.elems

-- | El sistema de producción (paso 6, cada periodo). Escribe la base de
-- @bien.<id>.produccion@ de la facción con lo producido en el periodo y la
-- suma a @bien.<id>.existencias@; es el único escritor de las dos. Cada
-- facción activa recibe lo que producen sus altépetl. Lee la
-- producción de cada altépetl (las obras) y las celdas del derivado.
--
-- El tributo en especie entre altépetl no mueve nada todavía: las
-- existencias son de la facción y el tributo en especie solo va entre
-- altépetl de la misma, así que lo que un sujeto entrega a su cabecera no
-- sale de la bolsa común. Se moverá cuando haya existencias por altépetl o
-- tributo entre facciones.
--
-- Lo guardado se estropea: antes de sumar lo producido, las existencias de un
-- bien con merma (@datos/bienes_<escenario>.json@) pierden esa fracción,
--
-- > existencias' = existencias · (1 − merma) + producción
--
-- así que, con producción constante, se acercan a producción / merma en vez
-- de crecer sin fin, y el precio de la moneda se estabiliza. La merma es la
-- efectiva de @bien.<id>.merma@ ('mermaEn'): la base la escribe este sistema
-- con la del catálogo, y las trojes la bajan con sus modificadores.
-- Sin economía, o con merma 0, todo sigue como antes.
--
-- Un bien con ventana de cosecha ('Cosechas') no se produce parejo: cada
-- periodo entra 'factorCosecha' veces lo de una veintena pareja, y fuera de
-- la ventana nada. Lo cosechado en el año es lo mismo.
produccion :: Constantes -> Economia -> Dieta -> [Proceso] -> Cosechas -> [Text] -> Sistema Purepecha
produccion c ec dieta procesos temporadas bienes = Sistema
  { sisNombre   = NombreSistema "produccion"
  , sisCadencia = Periodo
  , sisLee      = Set.singleton magProduccionAlt
  , sisEscribe  = Set.fromList (map (magCosechadoDe . gdId) (dtGrupos dieta) ++ concat [ [magExistencias b, magProduccion b, magMerma b, magCosecha b] | b <- bienes ])
  , sisEjecutar = \_ est ->
      if null bienes then (est, []) else
      let p     = persistenteJuego (estadoPersistente est)
          celdas = dpCeldas (derivadoJuego (estadoDerivado est))
          ws    = trabajadoresDe c p
          vig   = derivadoVigentes (estadoDerivado est)
          com   = persistenteComun (estadoPersistente est)
          factor alt = maybe baseProduccionAlt (valorEn vig (estadoTick est) rangoProduccionAlt)
                         (Map.lookup (entRefAlt alt, magProduccionAlt) (comunMagnitudes com))
          deAlt alt cs = Map.map (.*. factor alt) (produccionCeldas (Map.findWithDefault 0 alt ws) cs)
          -- Lo producido por cada altépetl de una facción activa, calculado
          -- una sola vez, y por cada facción: la suma de sus altépetl.
          -- Lo de casa (el solar, el tejido en casa): por persona del
          -- altépetl, con el dominio de su facción, sin ocupar celdas (T28).
          enCasa = [ pr | pr <- procesos, prLugar pr == EnCasa ]
          personas = if null enCasa then Map.empty
                     else Map.fromListWith (+) [ (popAltepetl pop, popTamano pop) | pop <- Map.elems (ppPops p) ]
          deCasa f alt = Map.unionsWith (.+.)
            [ Map.map (\r -> fi n .*. r ./. cTicksPorAnio c .*. (d ./. fi 100)) (prProductos pr)
            | pr <- enCasa, let n = Map.findWithDefault 0 alt personas, n > 0
            , let d = dominioEn vig (estadoTick est) (comunMagnitudes com) f (prTecnologia pr), d >= prDominioMinimo pr, d > Fijo 0 ]
          altsConAlgo = if null enCasa then Map.keys celdas else Map.keys (ppAltepetl p)
          porAltepetl = [ (f, alt, Map.unionWith (.+.) (deAlt alt (Map.findWithDefault [] alt celdas)) (deCasa f alt))
                        | alt <- altsConAlgo
                        , let f = facDeAlt p alt, Just fa <- [Map.lookup f (ppFacciones p)], facEstado fa == Activa ]
          porFac = Map.fromListWith (Map.unionWith (.+.)) [ (f, m) | (f, _, m) <- porAltepetl ]
          -- Lo producido por cada altépetl de cada facción, para repartir los
          -- alimentos (T25 y T27).
          alimentoDe = Map.fromListWith (++) [ (f, [(alt, m)]) | (f, alt, m) <- porAltepetl ]
          repartirAlimento = Map.member bienAlimento (csVentanas temporadas) && bienAlimento `elem` bienes
          -- La parte de la cosecha que va a las trojes de la facción: el
          -- tributo en especie, 5 % por punto de la tasa (V5, *Comer antes de
          -- tributar*).
          cuotaTrojes f = maybe (Fijo 0) (\fa -> cTributoEspecie c .*. fi (tasaTributo (facTasas fa))) (Map.lookup f (ppFacciones p))
          total f = Map.unionsWith (.+.) (Map.fromList [ (b, Fijo 0) | b <- bienes ]
                                          : [Map.findWithDefault Map.empty f porFac])
          t     = estadoTick est
          cal   = comunCalendario com
          -- El factor de cosecha de cada bien con ventana: el mismo para todas
          -- las facciones, así que se calcula una vez por periodo.
          cosecha = Map.map (\co -> factorCosecha cal temporadas co t) (csVentanas temporadas)
          enPeriodo b q = maybe q (q .*.) (Map.lookup b cosecha)
          guardado f b alm = maybe (Fijo 0) almacenBase (Map.lookup (entFac f, magExistencias b) alm)
          escribir f alm00 (b, q0) =
            let ventana = Map.member b (csVentanas temporadas)
                -- La base del factor de cosecha del año, de un bien con ventana.
                alm0a = if ventana then fijarBase (entFac f) (magCosecha b) uno alm00 else alm00
                factorAnio = if ventana then cosechaEn vig t alm0a (entFac f) b else uno
                q1 = enPeriodo b q0 .*. factorAnio
                -- Cada alimento de la dieta se reparte por altépetl: la cuota
                -- de las trojes va a las existencias de la facción y el resto
                -- se queda en lo cosechado del año del altépetl, en su grupo y
                -- en t ME. Lo producido (para el precio) es el total, y las
                -- trojes son lo que no se queda, así que la masa del bien se
                -- conserva exacta.
                grupo = if repartirAlimento then grupoDe dieta b else Nothing
                repartido = [ (alt, qa, qa .*. (uno .-. cuotaTrojes f))
                            | Just _ <- [grupo]
                            , (alt, prod) <- Map.findWithDefault [] f alimentoDe
                            , let qa = enPeriodo b (Map.findWithDefault (Fijo 0) b prod) .*. factorAnio ]
                (q, qTrojes, alm0)
                  | null repartido = (q1, q1, alm0a)
                  | otherwise =
                      ( foldl' (\s (_, qa, _) -> s .+. qa) (Fijo 0) repartido
                      , foldl' (\s (_, qa, h) -> s .+. (qa .-. h)) (Fijo 0) repartido
                      , case grupo of
                          Just (g, e) -> foldl' (\a (alt, _, h) -> sumarBase (entRefAlt alt) (magCosechadoDe (gdId g)) (h .*. e) a) alm0a repartido
                          Nothing     -> alm0a )
                -- La base de la merma, del catálogo; la efectiva, con las trojes.
                (alm, m) = case Map.lookup b (ecoBienes ec) of
                  Nothing -> (alm0, Fijo 0)
                  Just bien -> let a1 = fijarBase (entFac f) (magMerma b) (bnMerma bien) alm0
                               in (a1, mermaEn vig t a1 (entFac f) bien)
            in if m <= Fijo 0
                 then sumarBase (entFac f) (magExistencias b) qTrojes (fijarBase (entFac f) (magProduccion b) q alm)
                 else fijarBase (entFac f) (magExistencias b) (guardado f b alm .*. (uno .-. m) .+. qTrojes)
                        (fijarBase (entFac f) (magProduccion b) q alm)
          alm' = foldl' (\a fa -> foldl' (escribir (facId fa)) a
                                          (Map.toList (Map.filterWithKey (\b _ -> b `elem` bienes) (total (facId fa)))))
                        (comunMagnitudes com) (activas p)
      in (est { estadoPersistente = (estadoPersistente est) { persistenteComun = com { comunMagnitudes = alm' } } }, [])
  }

-- | El azar de la cosecha (V5, *Decisiones recurrentes*, Mala cosecha): al
-- empezar cada año, cada facción activa sortea su factor, parejo entre
-- 'cCosechaMinima' y 'cCosechaMaxima', con @rng σ "cosecha" año@. El factor es
-- uno por facción y año, el mismo para todos los bienes con ventana de
-- cosecha, y se pone como un modificador de @bien.<id>.cosecha@ con fuente
-- «azar/cosecha» que dura el año: la producción lo lee al cosechar y el
-- desglose dice cuánto fue el azar. Las facciones van por id, así que con la
-- misma semilla salen los mismos años. Sin bienes con ventana no hace nada.
azarCosecha :: Constantes -> Cosechas -> Sistema Purepecha
azarCosecha c temporadas = Sistema
  { sisNombre   = NombreSistema "cosecha"
  , sisCadencia = Anual
  , sisLee      = Set.empty
  , sisEscribe  = Set.fromList (map magCosecha conVentana)
  , sisEjecutar = \g0 est ->
      if null conVentana then (est, []) else
      let p   = persistenteJuego (estadoPersistente est)
          com = persistenteComun (estadoPersistente est)
          cal = comunCalendario com
          Tick t = estadoTick est
          dias = ciDiasPorPeriodo cal * ciPeriodosPorAnio cal + ciDiasFuera cal
          sortear (g, alm) fa =
            let (u, g') = uniforme g
                factor = cCosechaMinima c .+. (cCosechaMaxima c .-. cCosechaMinima c) .*. u
                nuevo b = Modificador
                  { modId = 0, modMagnitud = magCosecha b, modEntidad = entFac (facId fa)
                  , modAporte = Aporte (Fijo 0) (factor .-. uno)
                  , modFuente = Fuente "azar" "cosecha"
                  , modInicio = Just (Tick t), modFin = Just (Tick (t + fromIntegral dias))
                  , modCondicion = Nothing, modAlcance = AlcancePropia
                  , modDetalle = [("sorteo", u)] }
            in (g', foldl' (\a b -> fst (agregarModificador (nuevo b) a)) alm conVentana)
          (_, alm') = foldl' sortear (g0, comunMagnitudes com) (activas p)
      in (est { estadoPersistente = (estadoPersistente est) { persistenteComun = com { comunMagnitudes = alm' } } }, [])
  }
  where conVentana = Map.keys (csVentanas temporadas)
