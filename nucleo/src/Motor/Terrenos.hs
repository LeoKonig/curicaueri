{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | La tabla de terrenos como dato (@datos/terrenos.json@): capacidad base,
-- recursos y erosión base de cada terreno, y lo que rinde una celda trabajada
-- entera (documento funcional, sección 12: el rendimiento y(c) y los
-- trabajadores ℓ(c) que hacen falta para trabajarla). El mapa solo dice qué terreno es
-- cada celda; lo que ese terreno rinde sale de aquí, de modo que cambiar de
-- terreno (la roturación del hito 3) cambia las tres cosas sin escribir
-- valores sueltos. Ver V5, *La tierra y la gente*.
module Motor.Terrenos
  ( DefTerreno (..)
  , MaterialTerreno (..)
  , cargarTerrenos
  , validarTerrenosDelMapa
  , conCostoDeTerreno
  ) where

import Data.Aeson (Value)
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import Data.List (nub)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.IntMap.Strict as IntMap
import qualified Data.Set as Set

import Motor.Base
import Motor.Carga (CategoriaError (..), ErrorCarga (..), Validacion (..), falla)
import Motor.Mapa (Mapa (..), Celda (..), Conexion (..), Recurso (..), Terreno (..))

data DefTerreno = DefTerreno
  { dtTerreno   :: Terreno
  , dtCapacidad :: Fijo         -- ^ personas que sostiene una celda de este terreno
  , dtRecursos  :: [Recurso]
  , dtErosion   :: Fijo         -- ^ degradación base por veintena (la usa la erosión, hito 6a)
  , dtTrabajadores :: Fijo      -- ^ ℓ: trabajadores que trabajan la celda entera; 0 si no se trabaja
  , dtRendimiento  :: Map Text Fijo  -- ^ y: bienes por periodo de una celda trabajada entera; vacío por omisión
  , dtMateriales   :: Map Text MaterialTerreno  -- ^ materiales de obra que se extraen de la celda; vacío por omisión
  , dtCostoMovimiento :: Fijo   -- ^ μ: cuánto cuesta cruzar este terreno respecto del llano; 1 por omisión
  } deriving (Eq, Show)

-- | Un material de construcción que rinde un terreno (V5, *Las obras*): lo que
-- da por periodo una celda extraída entera y cuántos trabajadores lo extraen.
-- No es un bien: no tiene existencias; lo acopia cada obra.
data MaterialTerreno = MaterialTerreno
  { mtRendimiento  :: Fijo
  , mtTrabajadores :: Fijo
  } deriving (Eq, Show)

-- | Carga @terrenos.json@ acumulando todos los errores: terrenos repetidos,
-- capacidad o erosión negativas, recursos repetidos dentro de un terreno,
-- trabajadores o rendimientos negativos, un terreno que rinde algo sin
-- declarar cuántos trabajadores lo trabajan, y materiales con rendimiento
-- negativo o sin trabajadores.
--
-- El rendimiento se da por celda y periodo (@rendimiento@) o por trabajador y
-- año (@rendimiento_por_trabajador@, con @periodos_por_anio@ en la raíz): en
-- toneladas para los bienes a granel y en piezas para las mantas. Con el
-- segundo, el rendimiento de la celda es ℓ · r / periodos por año.
cargarTerrenos :: Text -> Value -> Validacion (Map Terreno DefTerreno)
cargarTerrenos archivo v = case A.parseEither leer v of
  Left err -> falla (ErrorCarga ErrorEstructura archivo "" (T.pack err))
  Right (periodos, ts) ->
    let ids = [ i | ((i, _, _, _, _, _), _, _, _) <- ts ]
        repetidos = traverse (\i -> if length (filter (== i) ids) > 1
                                      then falla (ErrorCarga ErrorEsquema archivo ("terrenos." <> i) "terreno repetido")
                                      else pure ()) (nub ids)
    in repetidos *> (Map.fromList . map (\t -> (dtTerreno t, t)) <$> traverse (validar periodos) ts)
  where
    leer = A.withObject "terrenos" $ \o -> do
      periodos <- o A..:? "periodos_por_anio"
      ts <- o A..: "terrenos" >>= mapM terreno
      pure (periodos :: Maybe Int, ts)
    terreno = A.withObject "terreno" $ \o -> do
      base <- (,,,,,) <$> o A..: "id" <*> o A..: "capacidad" <*> o A..:? "recursos" A..!= [] <*> o A..: "erosion"
                      <*> o A..:? "trabajadores" A..!= Fijo 0 <*> o A..:? "rendimiento" A..!= Map.empty
      mats <- o A..:? "materiales" A..!= Map.empty >>= traverse (A.withObject "material" (\m ->
                MaterialTerreno <$> m A..: "rendimiento" <*> m A..: "trabajadores"))
      mu <- o A..:? "costo_movimiento" A..!= uno
      rpt <- o A..:? "rendimiento_por_trabajador" A..!= Map.empty
      pure (base, mats, mu, rpt)
    validar periodos ((i, cap, recs, ero, trab, rend0), mats, mu, rpt) =
      let ruta = "terrenos." <> i
          -- Medidas reales (V5, *Medidas reales*): el rendimiento puede darse como lo que
          -- produce un trabajador en un año, en las unidades del bien (t, piezas), y el
          -- terreno lo convierte al de una celda por periodo: ℓ · r / periodos por año.
          rend = if Map.null rpt then rend0
                 else Map.map (\r -> (trab .*. r) ./. desdeEntero (maybe 1 id periodos)) rpt
          porTrabajadorOk
            | Map.null rpt = pure ()
            | not (Map.null rend0) = falla (ErrorCarga ErrorEsquema archivo (ruta <> ".rendimiento_por_trabajador")
                                              "un terreno lleva «rendimiento» o «rendimiento_por_trabajador», no los dos")
            | maybe True (<= 0) periodos = falla (ErrorCarga ErrorEsquema archivo "periodos_por_anio"
                                                    "el rendimiento por trabajador necesita «periodos_por_anio» mayor que 0")
            | otherwise = () <$ traverse (\(b, r) -> if r >= Fijo 0 then pure ()
                                                    else falla (ErrorCarga ErrorRango archivo (ruta <> ".rendimiento_por_trabajador." <> b)
                                                                  "el rendimiento no puede ser negativo")) (Map.toList rpt)
          capOk = if cap >= Fijo 0 then pure ()
                  else falla (ErrorCarga ErrorRango archivo (ruta <> ".capacidad") "la capacidad no puede ser negativa")
          eroOk = if ero >= Fijo 0 then pure ()
                  else falla (ErrorCarga ErrorRango archivo (ruta <> ".erosion") "la erosión no puede ser negativa")
          recsOk = if length (nub recs) == length recs then pure ()
                   else falla (ErrorCarga ErrorEsquema archivo (ruta <> ".recursos") "recurso repetido")
          trabOk = if trab >= Fijo 0 then pure ()
                   else falla (ErrorCarga ErrorRango archivo (ruta <> ".trabajadores") "los trabajadores no pueden ser negativos")
          rendOk = traverse (\(b, y) -> if y >= Fijo 0 then pure ()
                                        else falla (ErrorCarga ErrorRango archivo (ruta <> ".rendimiento." <> b)
                                                      "el rendimiento no puede ser negativo"))
                            (Map.toList rend0)
          rindeOk = if Map.null rend || trab > Fijo 0 then pure ()
                    else falla (ErrorCarga ErrorEsquema archivo (ruta <> ".trabajadores")
                                  "un terreno que rinde algo necesita trabajadores mayores que 0")
          matsOk = traverse (\(g, mt) ->
                     (if mtRendimiento mt >= Fijo 0 then pure ()
                      else falla (ErrorCarga ErrorRango archivo (ruta <> ".materiales." <> g <> ".rendimiento")
                                    "el rendimiento no puede ser negativo"))
                     *> (if mtTrabajadores mt > Fijo 0 then pure ()
                         else falla (ErrorCarga ErrorRango archivo (ruta <> ".materiales." <> g <> ".trabajadores")
                                       "la extracción necesita trabajadores mayores que 0")))
                   (Map.toList mats)
          muOk = if mu > Fijo 0 then pure ()
                 else falla (ErrorCarga ErrorRango archivo (ruta <> ".costo_movimiento") "el costo de movimiento debe ser mayor que 0")
      in DefTerreno (Terreno i) cap (map Recurso recs) ero trab rend mats mu
           <$ capOk <* eroOk <* recsOk <* trabOk <* rendOk <* rindeOk <* matsOk <* muOk <* porTrabajadorOk

-- | El costo de cada conexión según el terreno de sus dos celdas (V5, *Costo
-- del grafo*; documento funcional, sección 8):
--
-- > costo(a, b) = longitud(a, b) · (μ(a) + μ(b)) / 2
--
-- en km de llano. Es simétrico por construcción, así que la ley de simetría
-- del mapa sigue valiendo, y con μ = 1 en todas partes el costo es la
-- longitud. Una celda cuyo terreno falta en la tabla cuenta como llano; la
-- carga ya rechaza ese mapa con 'validarTerrenosDelMapa'.
conCostoDeTerreno :: Map Terreno DefTerreno -> Mapa -> Mapa
conCostoDeTerreno tabla m = m { mapaVecinos = IntMap.mapWithKey conexiones (mapaVecinos m) }
  where
    mu (CeldaId c) = maybe uno dtCostoMovimiento
                       (IntMap.lookup c (mapaCeldas m) >>= \ce -> Map.lookup (celdaTerreno ce) tabla)
    conexiones a = map (\(b, k) -> (b, k { connCosto = connLongitud k .*. ((mu (CeldaId a) .+. mu b) ./. desdeEntero 2) }))

-- | Todo terreno que el mapa usa tiene que estar en la tabla: se rechaza al
-- cargar, no en el tick 47. Un error por terreno, no por celda. Cuentan
-- también los terrenos de la composición de cada celda (T36).
validarTerrenosDelMapa :: Text -> Map Terreno DefTerreno -> Mapa -> Validacion ()
validarTerrenosDelMapa archivo tabla m =
  () <$ traverse (\t@(Terreno n) ->
         if Map.member t tabla then pure ()
         else falla (ErrorCarga ErrorReferencia archivo ("terrenos." <> n)
                       ("el mapa usa el terreno «" <> n <> "» y la tabla no lo declara")))
       usados
  where
    usados = Set.toAscList (Set.fromList [ t | c <- IntMap.elems (mapaCeldas m), t <- celdaTerreno c : map fst (celdaComposicion c) ])
