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
  , validarBienesDelTerritorio
  , lecturasMoneda
  , Cosecha (..)
  , Cosechas (..)
  , cargarCosechas
  , enVentana
  , diasVentana
  , factorCosecha
  , derivarCeldas
  , derivarTerritorio
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
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.IntMap.Strict as IntMap
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Estado
import Motor.Magnitudes
import Motor.Mapa (Mapa (..), Celda (..), Terreno)
import Motor.Calendario (CalendarioInterno (..), CalendarioVisible, Fecha, InfoPeriodo (..), diaDelAnioDe, diaDelAnioVisible, infoPeriodo)
import Motor.Carga (CategoriaError (..), ErrorCarga (..), Validacion, falla)
import Motor.Moneda (Bien (..), Economia (..), magExistencias, magMerma, magProduccion, mermaEn, rangoMerma)
import Motor.Recorrido (Grafo, asignarCeldas, grafoDe)
import Motor.Sistema
import Motor.Terrenos (DefTerreno (..), MaterialTerreno (..))
import Reglas.Base
import Reglas.Constantes
import Reglas.Estado

-- | Los bienes que el territorio puede producir: los que aparece en el
-- rendimiento de algún terreno, en orden alfabético.
bienesDe :: Map Terreno DefTerreno -> [Text]
bienesDe t = Map.keys (Map.unions (map dtRendimiento (Map.elems t)))

-- | Cada bien de la economía (@datos/bienes_<escenario>.json@) tiene que ser
-- uno que produzca el territorio: el precio se lee de sus existencias y su
-- producción, y un bien con otro nombre («manta») tendría siempre cero y un
-- precio fijo sin que nadie lo note. Acumula un error por bien. Sin tabla de
-- terrenos no hay producción y no se comprueba nada.
validarBienesDelTerritorio :: Text -> Map Terreno DefTerreno -> Economia -> Validacion ()
validarBienesDelTerritorio archivo tabla ec
  | Map.null tabla = pure ()
  | otherwise = () <$ traverse falta [ b | b <- Map.keys (ecoBienes ec), b `notElem` producidos ]
  where
    producidos = bienesDe tabla
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
catalogoBienes :: [Text] -> Map Magnitud DefMagnitud
catalogoBienes bs = Map.fromList $
  [ (m, DefMagnitud n rangoBien ("m." <> n) Nothing False)
  | b <- bs, m@(Magnitud n) <- [magExistencias b, magProduccion b] ]
  ++ [ (m, DefMagnitud n rangoMerma ("m." <> n) Nothing True) | b <- bs, let m@(Magnitud n) = magMerma b ]

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

-- | Una celda que se puede trabajar, con lo que pide y lo que da.
celdaTrabajo :: Int -> DefTerreno -> Maybe CeldaTrabajo
celdaTrabajo c d
  | Map.null (dtRendimiento d) || dtTrabajadores d <= Fijo 0 = Nothing
  | otherwise = Just (CeldaTrabajo c (dtTrabajadores d) (dtRendimiento d))

-- | Las celdas de mejor a peor por y/ℓ, con empate por id. La comparación se
-- hace en enteros, multiplicando en cruz, para no redondear el cociente.
ordenarCeldas :: [CeldaTrabajo] -> [CeldaTrabajo]
ordenarCeldas = sortBy cmp
  where
    y c = sum [ fromIntegral r :: Integer | Fijo r <- Map.elems (ctRendimiento c) ]
    l c = let Fijo x = ctTrabajadores c in fromIntegral x :: Integer
    cmp a b = compare (y b * l a, ctCelda a) (y a * l b, ctCelda b)

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
derivarTerritorio c tabla mapa gr p
  | null (bienesDe tabla) && all (Map.null . dtMateriales) (Map.elems tabla) = (Map.empty, Map.empty)
  | otherwise =
      let fuentes = [ (AsentId i, CeldaId (altCelda a)) | a <- Map.elems (ppAltepetl p), let AltId i = altId a ]
          asig = asignarCeldas (cRadioProduccion c) gr fuentes
          defDe cel = IntMap.lookup cel (mapaCeldas mapa) >>= \ce -> Map.lookup (celdaTerreno ce) tabla
          asignadas = [ (AltId a, cel, d) | (cel, AsentId a) <- IntMap.toList asig, Just d <- [defDe cel] ]
          porAlt = Map.fromListWith (++)
                     [ (a, [ct]) | (a, cel, d) <- asignadas, Just ct <- [celdaTrabajo cel d] ]
          mats = Map.fromListWith (Map.unionWith (++))
                   [ (a, Map.singleton g [CeldaTrabajo cel (mtTrabajadores mt) (Map.singleton g (mtRendimiento mt))])
                   | (a, cel, d) <- asignadas, (g, mt) <- Map.toList (dtMateriales d) ]
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
produccion :: Constantes -> Economia -> Cosechas -> [Text] -> Sistema Purepecha
produccion c ec temporadas bienes = Sistema
  { sisNombre   = NombreSistema "produccion"
  , sisCadencia = Periodo
  , sisLee      = Set.singleton magProduccionAlt
  , sisEscribe  = Set.fromList (concat [ [magExistencias b, magProduccion b, magMerma b] | b <- bienes ])
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
          -- Lo producido por cada facción activa: la suma de sus altépetl.
          porFac = Map.fromListWith (Map.unionWith (.+.))
                     [ (f, deAlt alt cs) | (alt, cs) <- Map.toList celdas
                     , let f = facDeAlt p alt, Just fa <- [Map.lookup f (ppFacciones p)], facEstado fa == Activa ]
          total f = Map.unionsWith (.+.) (Map.fromList [ (b, Fijo 0) | b <- bienes ]
                                          : [Map.findWithDefault Map.empty f porFac])
          t     = estadoTick est
          cal   = comunCalendario com
          -- El factor de cosecha de cada bien con ventana: el mismo para todas
          -- las facciones, así que se calcula una vez por periodo.
          cosecha = Map.map (\co -> factorCosecha cal temporadas co t) (csVentanas temporadas)
          enPeriodo b q = maybe q (q .*.) (Map.lookup b cosecha)
          guardado f b alm = maybe (Fijo 0) almacenBase (Map.lookup (entFac f, magExistencias b) alm)
          escribir f alm0 (b, q0) =
            let q = enPeriodo b q0
                -- La base de la merma, del catálogo; la efectiva, con las trojes.
                (alm, m) = case Map.lookup b (ecoBienes ec) of
                  Nothing -> (alm0, Fijo 0)
                  Just bien -> let a1 = fijarBase (entFac f) (magMerma b) (bnMerma bien) alm0
                               in (a1, mermaEn vig t a1 (entFac f) bien)
            in if m <= Fijo 0
                 then sumarBase (entFac f) (magExistencias b) q (fijarBase (entFac f) (magProduccion b) q alm)
                 else fijarBase (entFac f) (magExistencias b) (guardado f b alm .*. (uno .-. m) .+. q)
                        (fijarBase (entFac f) (magProduccion b) q alm)
          alm' = foldl' (\a fa -> foldl' (escribir (facId fa)) a
                                          (Map.toList (Map.filterWithKey (\b _ -> b `elem` bienes) (total (facId fa)))))
                        (comunMagnitudes com) (activas p)
      in (est { estadoPersistente = (estadoPersistente est) { persistenteComun = com { comunMagnitudes = alm' } } }, [])
  }
