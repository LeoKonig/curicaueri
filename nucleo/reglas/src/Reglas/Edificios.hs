{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Edificios y obras (V5, *Las obras*; documento funcional, sección 14i;
-- hito 3, etapa 1).
--
-- Un edificio es un dato (@datos/edificios.json@). Una obra cuesta:
--
-- * valor, que se cobra del tesoro al empezar;
-- * una cuadrilla, que se retira de la producción mientras dura la obra
--   ('retiradosDe') y cuyo sustento sale de la partida de obras;
-- * trabajo en el sitio, en trabajador·veintena;
-- * materiales que la cuadrilla extrae de las celdas del altépetl y acopia
--   en la obra (no son bienes con existencias);
-- * una duración mínima: ninguna cuadrilla termina antes.
--
-- Un edificio que no declara trabajo ni materiales es el del primer corte:
-- sin cuadrilla, avanza una veintena de obra por cada veintena en que la
-- partida de obras llega a 'cObrasPresupuestoMinimo'.
--
-- Lo que da un edificio no es un número fijo por copia: cada tipo aporta, por
-- altépetl y magnitud, un solo modificador con fuente @edificio:<id>:<alt>@
-- cuyo valor calcula una fórmula con nombre a partir de cuántos hay y, en los
-- templos, de los fieles de su tradición que asisten y de los sacerdotes que
-- los atienden. El sistema de construcción lo recalcula cada veintena.
module Reglas.Edificios
  ( Edificios
  , DefEdificio (..)
  , DefModEdificio (..)
  , EntidadEdificio (..)
  , EfectoTerminar (..)
  , Formula (..)
  , Nivel (..)
  , Culto (..)
  , Tradicion (..)
  , Conocimiento (..)
  , conocimientos
  , magCodificado
  , magTacito
  , catalogoConocimientos
  , conConocimientos
  , dominio
  , productividad
  , fuentePractica
  , edificiosVacios
  , cargarEdificios
  , idsEdificios
  , defEdificio
  , tradiciones
  , fuenteEdificio
  , afinidad
  , beneficio
  , detalleBeneficio
  , fielesAtendidos
  , trabajadoresPara
  , derivarFieles
  , derivarDistancias
  , fuenteTributo
  , diasDeTransporte
  , pedirTributo
  , iniciarObra
  , construccion
  ) where

import Data.Aeson (Value)
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import Data.List (foldl', nub)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.IntMap.Strict as IntMap
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Carga (CategoriaError (..), ErrorCarga (..), Validacion (..), falla)
import Motor.Estado
import Motor.Hechos
import Motor.Juego (Rechazo (..), hechoModificadorTerminado)
import Motor.Magnitudes
import Motor.Recorrido (Etiqueta (..), Cupo (..), Grafo, grafoMapa, primera, propagar, propagarGrafo)
import Motor.Sistema
import Reglas.Base
import Reglas.Constantes
import Reglas.Estado
import Reglas.Formulas (gastoPunto)
import Reglas.Grupos (agregarVarios)
import Reglas.Produccion (produccionCeldas, trabajadoresDe)

-- ---------------------------------------------------------------------------
-- Datos
-- ---------------------------------------------------------------------------

-- | A quién llega un modificador o un efecto: al altépetl donde se levanta la
-- obra o a la facción que la paga.
data EntidadEdificio = AlAltepetl | AlaFaccion
  deriving (Eq, Show)

-- | Cómo crece el beneficio con las copias (sección 14i). @a@ es el aporte
-- que declara el modificador.
data Formula
  = FFija           -- ^ a si hay al menos una copia (el primer corte; por omisión)
  | FLineal         -- ^ a · n
  | FLogaritmica    -- ^ a · ln(1 + n)
  | FPorAsistentes  -- ^ a · ln(1 + S / ref), con S los fieles atendidos
  deriving (Eq, Show)

data DefModEdificio = DefModEdificio
  { dmeEntidad  :: EntidadEdificio
  , dmeMagnitud :: Magnitud
  , dmeAporte   :: Aporte
  , dmeFormula  :: Formula
  } deriving (Eq, Show)

-- | Lo que hace un edificio al terminarse, además de sus modificadores: sumar
-- a la base de una magnitud (el prestigio de la obra), con el nombre del
-- efecto @sumar_mag@ de "Motor.Efectos"; la entidad es relativa a la obra.
data EfectoTerminar = SumarBase EntidadEdificio Magnitud Fijo
  deriving (Eq, Show)

-- | Templo local (atiende a su zona) o centro ceremonial (a todo el reino,
-- con peso por distancia).
data Nivel = Local | Centro
  deriving (Eq, Show)

data Culto = Culto
  { cuTradicion  :: Text
  , cuNivel      :: Nivel
  , cuCapacidad  :: Fijo   -- ^ fieles que atiende un templo
  , cuSacerdotes :: Fijo   -- ^ sacerdotes que necesita un templo
  , cuReferencia :: Fijo   -- ^ ref de la fórmula por asistentes
  } deriving (Eq, Show)

-- | Una tradición religiosa. Sus fieles son los pops de sus identidades, con
-- afinidad 1 − g, o, si es la que sigue el gradiente (la católica), todos los
-- pops con afinidad g.
data Tradicion = Tradicion
  { trId          :: Text
  , trIdentidades :: [Text]
  , trGradiente   :: Bool
  } deriving (Eq, Show)

-- | Un conocimiento del oficio (V5, *Tecnología y educación*; *Las obras*,
-- etapa 3): sus bases en el escenario y cuánto enseña la práctica. Sus dos
-- magnitudes son de la facción.
data Conocimiento = Conocimiento
  { cnId         :: Text
  , cnCodificado :: Fijo   -- ^ base de @conocimiento.<id>.codificado@
  , cnTacito     :: Fijo   -- ^ base de @conocimiento.<id>.tacito@
  , cnPractica   :: Fijo   -- ^ α: la práctica aporta α · ln(1 + n) al tácito
  } deriving (Eq, Show)

data DefEdificio = DefEdificio
  { deId          :: Text
  , deCostoValor  :: Fijo                -- ^ unidades de valor, del tesoro
  , deVeintenas   :: Int                 -- ^ D: veintenas de obra mínimas
  , deTrabajo     :: Fijo                -- ^ T: trabajador·veintena; 0 sin cuadrilla
  , deMateriales  :: Map Text Fijo       -- ^ M_g
  , deCuadrillaMax :: Int
  , deMaximo      :: Maybe Int           -- ^ copias por altépetl; sin límite por omisión
  , deCulto       :: Maybe Culto
  , deOficio      :: Maybe (Text, Fijo)  -- ^ conocimiento y dominio mínimo; sin oficio por omisión
  , deMods        :: [DefModEdificio]
  , deAlTerminar  :: [EfectoTerminar]
  } deriving (Eq, Show)

-- | ¿Lleva cuadrilla la obra? Sí si pide trabajo o materiales.
conCuadrilla :: DefEdificio -> Bool
conCuadrilla d = deTrabajo d > Fijo 0 || not (Map.null (deMateriales d))

-- | Los edificios por id. El orden del archivo se conserva para el catálogo.
data Edificios = Edificios
  { edOrden         :: [Text]
  , edDefs          :: Map Text DefEdificio
  , edTradiciones   :: [Tradicion]
  , edConocimientos :: [Conocimiento]
  } deriving (Eq, Show)

edificiosVacios :: Edificios
edificiosVacios = Edificios [] Map.empty [] []

conocimientos :: Edificios -> [Conocimiento]
conocimientos = edConocimientos

magCodificado, magTacito :: Text -> Magnitud
magCodificado k = Magnitud ("conocimiento." <> k <> ".codificado")
magTacito k     = Magnitud ("conocimiento." <> k <> ".tacito")

rangoConocimiento :: RangoMag
rangoConocimiento = RangoMag (Fijo 0) (fi 100)

-- | Las dos magnitudes de cada conocimiento, para el catálogo del juego.
catalogoConocimientos :: Edificios -> Map Magnitud DefMagnitud
catalogoConocimientos eds = Map.fromList
  [ (m, DefMagnitud n rangoConocimiento ("m." <> n) Nothing False)
  | k <- edConocimientos eds, m@(Magnitud n) <- [magCodificado (cnId k), magTacito (cnId k)] ]

-- | El escenario con las bases de cada conocimiento en cada facción declarada
-- (también la potencial, para que al activarse ya los tenga).
conConocimientos :: Edificios -> Estado Purepecha -> Estado Purepecha
conConocimientos eds est =
  let p = estadoPersistente est
      com = persistenteComun p
      alm = foldl' (\al (f, k) -> fijarBase (entFac f) (magTacito (cnId k)) (cnTacito k)
                                    (fijarBase (entFac f) (magCodificado (cnId k)) (cnCodificado k) al))
                   (comunMagnitudes com)
                   [ (f, k) | f <- Map.keys (ppFacciones (persistenteJuego p)), k <- edConocimientos eds ]
      p' = p { persistenteComun = com { comunMagnitudes = alm } }
  in est { estadoPersistente = p', estadoOrigen = Origen (estadoTick est) p' }

-- | El dominio de un conocimiento de una facción (fórmula con nombre @dominio_tecnologia@,
-- sección 14e; provisional: el mínimo del codificado y el tácito), con sus
-- valores efectivos.
dominio :: Estado Purepecha -> FaccionId -> Text -> Fijo
dominio est f k = min (valor (magCodificado k)) (valor (magTacito k))
  where
    alm = comunMagnitudes (persistenteComun (estadoPersistente est))
    valor m = maybe (Fijo 0) (valorEn (derivadoVigentes (estadoDerivado est)) (estadoTick est) rangoConocimiento)
                (Map.lookup (entFac f, m) alm)

-- | η: cuánto rinde la gente de la obra de una facción, el dominio entre 100;
-- 1 sin oficio.
productividad :: Estado Purepecha -> FaccionId -> DefEdificio -> Fijo
productividad est f d = maybe uno (\(k, _) -> dominio est f k ./. desdeEntero 100) (deOficio d)

-- | La fuente del aporte de la práctica al conocimiento tácito.
fuentePractica :: Text -> Fuente
fuentePractica k = Fuente "practica" k

idsEdificios :: Edificios -> [Text]
idsEdificios = edOrden

defEdificio :: Edificios -> Text -> Maybe DefEdificio
defEdificio eds e = Map.lookup e (edDefs eds)

tradiciones :: Edificios -> [Tradicion]
tradiciones = edTradiciones

-- | La fuente de los modificadores de un tipo de edificio en un altépetl.
fuenteEdificio :: Text -> AltId -> Fuente
fuenteEdificio e (AltId a) = Fuente "edificio" (e <> ":" <> T.pack (show a))

-- ---------------------------------------------------------------------------
-- Carga
-- ---------------------------------------------------------------------------

-- | Carga @edificios.json@ acumulando todos los errores: ids repetidos,
-- costos, trabajo o materiales negativos, veintenas no positivas, insumos
-- (aún no implementados), una obra con trabajo o materiales sin cuadrilla
-- máxima, entidades, fórmulas o tradiciones desconocidas, magnitudes que no
-- están en el catálogo del juego, un modificador sin aporte o con los dos, un
-- beneficio por asistentes sin culto, y efectos al terminar no admitidos.
cargarEdificios :: Text -> Map Magnitud DefMagnitud -> Value -> Validacion Edificios
cargarEdificios archivo catalogo v = case A.parseEither leer v of
  Left e -> falla (ErrorCarga ErrorEstructura archivo "" (T.pack e))
  Right (trads, cons, crudos) ->
    let ids = [ crId c | c <- crudos ]
        repetidos = traverse (\i -> if length (filter (== i) ids) > 1
                                      then err ErrorEsquema ("edificios." <> i) "edificio repetido"
                                      else pure ()) (nub ids)
        tradIds = map trId trads
        tradRep = traverse (\i -> if length (filter (== i) tradIds) > 1
                                    then err ErrorEsquema ("tradiciones." <> i) "tradición repetida"
                                    else pure ()) (nub tradIds)
        conIds = map cnId cons
        conRep = traverse (\i -> if length (filter (== i) conIds) > 1
                                    then err ErrorEsquema ("conocimientos." <> i) "conocimiento repetido"
                                    else pure ()) (nub conIds)
        conOk = traverse (\k ->
                  let r x = "conocimientos." <> cnId k <> "." <> x
                      rango x y = if y >= Fijo 0 && y <= fi 100 then pure () else err ErrorRango (r x) "fuera de 0..100"
                  in rango "codificado" (cnCodificado k) *> rango "tacito" (cnTacito k)
                     *> (if cnPractica k >= Fijo 0 then pure () else err ErrorRango (r "practica") "no puede ser negativa"))
                cons
    in (\_ _ _ _ ds -> Edificios ids (Map.fromList [ (deId d, d) | d <- ds ]) trads cons)
         <$> repetidos <*> tradRep <*> conRep <*> conOk <*> traverse (validar tradIds conIds) crudos
  where
    err :: CategoriaError -> Text -> Text -> Validacion b
    err cat ruta msg = falla (ErrorCarga cat archivo ruta msg)
    leer = A.withObject "edificios" $ \o -> do
      ts <- o A..:? "tradiciones" A..!= [] >>= mapM (A.withObject "tradicion" (\t ->
              Tradicion <$> t A..: "id" <*> t A..:? "identidades" A..!= [] <*> t A..:? "por_gradiente" A..!= False))
      cs <- o A..:? "conocimientos" A..!= [] >>= mapM (A.withObject "conocimiento" (\k ->
              Conocimiento <$> k A..: "id" <*> k A..: "codificado" <*> k A..: "tacito" <*> k A..:? "practica" A..!= Fijo 0))
      es <- o A..: "edificios" >>= mapM edificio
      pure (ts, cs, es)
    edificio = A.withObject "edificio" $ \o -> do
      i     <- o A..: "id"
      costo <- o A..: "costo"
      (val, vs, trab, mats, ins) <- A.withObject "costo" (\c ->
                          (,,,,) <$> c A..: "valor" <*> c A..: "veintenas"
                                 <*> c A..:? "trabajo" A..!= Fijo 0
                                 <*> c A..:? "materiales" A..!= Map.empty
                                 <*> (c A..:? "insumos" A..!= ([] :: [Value]))) costo
      cmax  <- o A..:? "cuadrilla_maxima" A..!= 0
      maxi  <- o A..:? "maximo"
      cultoV <- o A..:? "culto"
      oficio <- o A..:? "oficio" >>= traverse (A.withObject "oficio" (\f ->
                  (,) <$> f A..: "conocimiento" <*> f A..: "dominio_minimo"))
      mods  <- o A..:? "modificadores" A..!= []
      fins  <- o A..:? "al_terminar" A..!= []
      pure (Crudo i val vs trab mats ins cmax maxi cultoV oficio mods fins)
    validar tradIds conIds c =
      let i = crId c
          ruta x = "edificios." <> i <> "." <> x
          positivoOCero r x msg = if x >= Fijo 0 then pure () else err ErrorRango r msg
          valorOk = positivoOCero (ruta "costo.valor") (crValor c) "el costo no puede ser negativo"
          trabOk  = positivoOCero (ruta "costo.trabajo") (crTrabajo c) "el trabajo no puede ser negativo"
          matsOk  = traverse (\(g, q) -> if q > Fijo 0 then pure ()
                                         else err ErrorRango (ruta ("costo.materiales." <> g)) "la cantidad debe ser mayor que 0")
                             (Map.toList (crMateriales c))
          veintOk = if crVeintenas c > 0 then pure ()
                    else err ErrorRango (ruta "costo.veintenas") "una obra dura al menos una veintena"
          insOk = if null (crInsumos c) then pure ()
                  else err ErrorEsquema (ruta "costo.insumos")
                         "los insumos aún no están implementados (documento funcional, sección 14h): deja la lista vacía"
          lleva = crTrabajo c > Fijo 0 || not (Map.null (crMateriales c))
          cuadOk = if not lleva || crCuadrillaMax c > 0 then pure ()
                   else err ErrorEsquema (ruta "cuadrilla_maxima") "una obra con trabajo o materiales necesita una cuadrilla máxima mayor que 0"
          maxOk = case crMaximo c of
                    Just m | m < 1 -> err ErrorRango (ruta "maximo") "el máximo es al menos 1"
                    _ -> pure ()
          cultoV = traverse (culto tradIds (ruta "culto")) (crCulto c)
          modsV  = traverse (modificador (ruta "modificadores")) (zip [0 :: Int ..] (crMods c))
          finsV  = traverse (efecto (ruta "al_terminar")) (zip [0 :: Int ..] (crFins c))
          def cu ms fs = DefEdificio i (crValor c) (crVeintenas c) (crTrabajo c) (crMateriales c)
                                     (crCuadrillaMax c) (crMaximo c) cu (crOficio c) ms fs
          oficioOk = case crOficio c of
            Nothing -> pure ()
            Just (k, dmin) ->
              (if k `elem` conIds then pure ()
               else err ErrorReferencia (ruta "oficio.conocimiento") ("conocimiento que el archivo no declara: " <> k))
              *> (if dmin >= Fijo 0 && dmin <= fi 100 then pure ()
                  else err ErrorRango (ruta "oficio.dominio_minimo") "fuera de 0..100")
          sinCulto cu ms = if any ((== FPorAsistentes) . dmeFormula) ms && cu == Nothing
                             then err ErrorEsquema (ruta "culto") "un beneficio «por_asistentes» necesita el culto del templo"
                             else pure ()
      in (\cu ms fs -> def cu ms fs) <$> cultoV <*> modsV <*> finsV
           <* valorOk <* trabOk <* matsOk <* veintOk <* insOk <* cuadOk <* maxOk <* oficioOk
           <* (case (valValor cultoV, valValor modsV) of
                 (Just cu, Just ms) -> sinCulto cu ms
                 _ -> pure ())
    culto tradIds ruta cv = case A.parseEither (A.withObject "culto" (\o ->
        (,,,,) <$> o A..: "tradicion" <*> o A..: "nivel" <*> o A..: "capacidad"
               <*> o A..: "sacerdotes" <*> o A..: "referencia")) cv of
      Left e -> err ErrorEstructura ruta (T.pack e)
      Right (t, n, cap, sac, ref) ->
        let tradOk = if t `elem` tradIds then pure ()
                     else err ErrorReferencia (ruta <> ".tradicion") ("tradición que el archivo no declara: " <> t)
            nivel = case (n :: Text) of
              "local"  -> pure Local
              "centro" -> pure Centro
              _ -> err ErrorEsquema (ruta <> ".nivel") ("nivel desconocido: " <> n <> " (local o centro)")
            pos r x = if x > Fijo 0 then pure () else err ErrorRango (ruta <> "." <> r) "debe ser mayor que 0"
        in (\nv -> Culto t nv cap sac ref) <$> nivel <* tradOk <* pos "capacidad" cap
                                             <* pos "sacerdotes" sac <* pos "referencia" ref
    entidad ruta t = case (t :: Text) of
      "altepetl" -> pure AlAltepetl
      "faccion"  -> pure AlaFaccion
      _          -> err ErrorReferencia (ruta <> ".entidad") ("entidad desconocida: " <> t <> " (altepetl o faccion)")
    formula ruta f = case (f :: Text) of
      "fija"           -> pure FFija
      "lineal"         -> pure FLineal
      "logaritmica"    -> pure FLogaritmica
      "por_asistentes" -> pure FPorAsistentes
      _ -> err ErrorReferencia (ruta <> ".formula") ("fórmula desconocida: " <> f)
    magnitud ruta m@(Magnitud n)
      | Map.member m catalogo = pure m
      | otherwise = err ErrorReferencia (ruta <> ".magnitud") ("magnitud que el juego no declara: " <> n)
    modificador base (k, mv) =
      let ruta = base <> "." <> T.pack (show k)
      in case A.parseEither campos mv of
           Left e -> err ErrorEstructura ruta (T.pack e)
           Right (ent, mag, suma, por, f) ->
             let aporte = case (suma, por) of
                   (Just s, Nothing) -> pure (Aporte s (Fijo 0))
                   (Nothing, Just p) -> pure (Aporte (Fijo 0) (p ./. desdeEntero 100))
                   _ -> err ErrorEsquema ruta "un modificador lleva «sumar» o «porcentaje», uno de los dos"
             in DefModEdificio <$> entidad ruta ent <*> magnitud ruta mag <*> aporte <*> formula ruta f
    campos = A.withObject "modificador" $ \o ->
      (,,,,) <$> o A..: "entidad" <*> o A..: "magnitud" <*> o A..:? "sumar" <*> o A..:? "porcentaje"
             <*> o A..:? "formula" A..!= ("fija" :: Text)
    efecto base (k, ev) =
      let ruta = base <> "." <> T.pack (show k)
      in case A.parseEither (A.withObject "efecto" (\o ->
                (,,,) <$> o A..: "tipo" <*> o A..: "entidad" <*> o A..: "magnitud" <*> o A..: "valor")) ev of
           Left e -> err ErrorEstructura ruta (T.pack e)
           Right (tipo, ent, mag, val)
             | tipo == ("sumar_mag" :: Text) -> SumarBase <$> entidad ruta ent <*> magnitud ruta mag <*> pure val
             | otherwise -> err ErrorEsquema (ruta <> ".tipo") ("efecto no admitido al terminar una obra: " <> tipo)

-- | Un edificio leído, antes de validarlo.
data Crudo = Crudo
  { crId :: Text, crValor :: Fijo, crVeintenas :: Int, crTrabajo :: Fijo, crMateriales :: Map Text Fijo
  , crInsumos :: [Value], crCuadrillaMax :: Int, crMaximo :: Maybe Int, crCulto :: Maybe Value
  , crOficio :: Maybe (Text, Fijo)
  , crMods :: [Value], crFins :: [Value] }

-- ---------------------------------------------------------------------------
-- Fórmulas
-- ---------------------------------------------------------------------------

lnF :: Fijo -> Fijo
lnF x = either (const (Fijo 0)) id (lnFijo x)

escalarAporte :: Fijo -> Aporte -> Aporte
escalarAporte k (Aporte s p) = Aporte (s .*. k) (p .*. k)

-- | Los fieles que atienden n templos (sección 14i):
--
-- > S = min(F, n · cap · min(1, σ / (n · s)))
--
-- con F los fieles que asisten y σ los sacerdotes de la tradición. Sin
-- templos o sin sacerdotes, nadie. Se calcula en la forma equivalente
-- min(F, n · cap, cap · σ / s): cuando faltan sacerdotes, lo atendido no
-- depende de n, y el redondeo del punto fijo no lo hace oscilar.
fielesAtendidos :: Culto -> Int -> Fijo -> Fijo -> Fijo
fielesAtendidos cu n fieles sacerdotes
  | n <= 0 = Fijo 0
  | otherwise = minimum [ fieles, desdeEntero n .*. cuCapacidad cu
                        , cuCapacidad cu .*. (sacerdotes ./. cuSacerdotes cu) ]

-- | El aporte de n copias de un edificio con la fórmula de su modificador.
-- Para @por_asistentes@ hacen falta el culto, los fieles y los sacerdotes.
beneficio :: Formula -> Maybe Culto -> Int -> Fijo -> Fijo -> Aporte -> Aporte
beneficio f mcu n fieles sacerdotes a
  | n <= 0 = mempty
  | otherwise = case f of
      FFija          -> a
      FLineal        -> escalarAporte (desdeEntero n) a
      FLogaritmica   -> escalarAporte (lnF (desdeEntero (n + 1))) a
      FPorAsistentes -> case mcu of
        Nothing -> mempty
        Just cu -> let s = fielesAtendidos cu n fieles sacerdotes
                   in escalarAporte (lnF (uno .+. s ./. cuReferencia cu)) a

-- | De qué sale el beneficio, para el desglose: las copias y, en los
-- templos, los fieles que asisten, los atendidos y los sacerdotes. Así el
-- tooltip dice «yácata: copias 1, fieles 12 000, atendidos 5 000, sacerdotes
-- 60» y no solo el número.
detalleBeneficio :: Formula -> Maybe Culto -> Int -> Fijo -> Fijo -> [(Text, Fijo)]
detalleBeneficio f mcu n fieles sacerdotes = ("copias", desdeEntero n) : case (f, mcu) of
  (FPorAsistentes, Just cu) -> [ ("fieles", fieles), ("atendidos", fielesAtendidos cu n fieles sacerdotes)
                               , ("sacerdotes", sacerdotes) ]
  _ -> []

-- ---------------------------------------------------------------------------
-- Asistencia a los templos (derivado del paso 16)
-- ---------------------------------------------------------------------------

-- | La afinidad de un pop con una tradición: g con la que sigue el
-- gradiente, 1 − g con la de su identidad, 0 con las demás.
afinidad :: Tradicion -> Pop -> Fijo
afinidad t pop
  | trGradiente t                         = popGradiente pop
  | popIdentidad pop `elem` trIdentidades t = uno .-. popGradiente pop
  | otherwise                              = Fijo 0

-- | Los fieles de cada templo local y de cada centro ceremonial, por
-- (altépetl del templo, tradición). Los pops viven en la cabecera de su
-- altépetl.
--
-- * Local: cada altépetl va al templo local de la tradición más cercano por
--   el costo del grafo, hasta 'cAlcanceTemploLocal', con empate por id: un
--   solo recorrido multifuente por tradición, y nadie se cuenta dos veces.
-- * Centro: cada centro suma los fieles de todo el reino con peso
--   max(0, 1 − d / 'cAlcanceCentro'): un recorrido con tope por centro.
--
-- Sin templos no se recorre nada.
derivarFieles :: Constantes -> Edificios -> Grafo -> Purepecha
              -> (Map (AltId, Text) Fijo, Map (AltId, Text) Fijo)
derivarFieles c eds gr p
  | null templos = (Map.empty, Map.empty)
  | otherwise = (Map.unionsWith (.+.) (map local trads), Map.unionsWith (.+.) (map centro trads))
  where
    trads = edTradiciones eds
    alts = ppAltepetl p
    -- (altépetl, tradición, nivel) de cada altépetl con algún templo
    templos = [ (altId a, cuTradicion cu, cuNivel cu)
              | a <- Map.elems alts, e <- nub (altEdificios a)
              , Just d <- [Map.lookup e (edDefs eds)], Just cu <- [deCulto d] ]
    -- fieles por altépetl y tradición, en una pasada por los pops
    porAlt t = Map.filter (> Fijo 0) (Map.fromListWith (.+.)
                 [ (popAltepetl pop, fi (popTamano pop) .*. afinidad t pop) | pop <- Map.elems (ppPops p) ])
    celdaDe a = maybe Nothing (\x -> Just (altCelda x)) (Map.lookup a alts)
    semilla (AltId i) = fmap (\cel -> (CeldaId cel, Etiqueta (Fijo 0) i i)) (celdaDe (AltId i))
    local t =
      let fuentes = nub [ a | (a, tt, Local) <- templos, tt == trId t ]
      in if null fuentes then Map.empty else
         let et = propagarGrafo UnGrupo (Just (cAlcanceTemploLocal c)) gr [ s | Just s <- map semilla fuentes ]
         in Map.fromListWith (.+.)
              [ ((AltId (etGrupo (primera m)), trId t), f)
              | (b, f) <- Map.toList (porAlt t), Just cel <- [celdaDe b], Just m <- [IntMap.lookup cel et] ]
    centro t =
      let centros = nub [ a | (a, tt, Centro) <- templos, tt == trId t ]
          fs = porAlt t
          alc = cAlcanceCentro c
          uno' e = case semilla e of
            Nothing -> Map.empty
            Just s ->
              let et = propagar UnGrupo (Just alc) (grafoMapa gr) [s] IntMap.empty
                  peso d = max (Fijo 0) (uno .-. d ./. alc)
                  total = foldl' (.+.) (Fijo 0)
                            [ f .*. peso (etDistancia (primera m))
                            | (b, f) <- Map.toList fs, Just cel <- [celdaDe b], Just m <- [IntMap.lookup cel et] ]
              in Map.singleton (e, trId t) total
      in Map.unions (map uno' centros)

-- ---------------------------------------------------------------------------
-- Obras
-- ---------------------------------------------------------------------------

-- | Los trabajadores que hacen falta para extraer @falta@ unidades de un
-- material de unas celdas ya ordenadas: llenan primero las mejores, y la
-- última a medias se redondea hacia arriba.
trabajadoresPara :: Fijo -> [CeldaTrabajo] -> Int
trabajadoresPara falta = go falta 0
  where
    go f acc [] = if f > Fijo 0 then maxBound `div` 4 else acc
    go f acc (ct : cs)
      | f <= Fijo 0 = acc
      | otherwise =
          let y = foldl' (.+.) (Fijo 0) (Map.elems (ctRendimiento ct))
              Fijo l = ctTrabajadores ct
              lInt = fromIntegral ((l + escala - 1) `div` escala)
          in if y <= f || y <= Fijo 0
               then go (f .-. y) (acc + lInt) cs
               else let Fijo fv = f; Fijo yv = y
                        need = (fromIntegral fv * fromIntegral l + fromIntegral yv * fromIntegral escala - 1)
                               `div` (fromIntegral yv * fromIntegral escala) :: Integer
                    in acc + fromIntegral need

-- | Empieza una obra: valida, cobra el costo en valor del tesoro y deja la
-- obra en curso con su cuadrilla. Un rechazo no cambia el estado.
iniciarObra :: Constantes -> Edificios -> FaccionId -> Text -> AltId -> Int -> Estado Purepecha
            -> Either Rechazo (Estado Purepecha, [Hecho])
iniciarObra c eds fac eid alt cuadrilla est = do
  d <- maybe (Left (Rechazo ("edificio desconocido: " <> eid))) Right (Map.lookup eid (edDefs eds))
  a <- maybe (Left (Rechazo "el altépetl no existe")) Right (Map.lookup alt (ppAltepetl jue))
  if altFaccion a /= fac then Left (Rechazo (altNombre a <> " no es de tu facción")) else Right ()
  case altObra a of
    Just o  -> Left (Rechazo (altNombre a <> " ya tiene una obra en curso: " <> obEdificio o))
    Nothing -> Right ()
  let copias = length (filter (== eid) (altEdificios a))
  case deMaximo d of
    Just m | copias >= m -> Left (Rechazo (altNombre a <> " ya tiene " <> tshow copias <> " de " <> eid
                                          <> ", el máximo"))
    _ -> Right ()
  if conCuadrilla d
    then do
      if cuadrilla < 1 || cuadrilla > deCuadrillaMax d
        then Left (Rechazo ("la cuadrilla de " <> eid <> " va de 1 a " <> tshow (deCuadrillaMax d)))
        else Right ()
      let libres = Map.findWithDefault 0 alt (trabajadoresDe c jue)
      if cuadrilla > libres
        then Left (Rechazo (altNombre a <> " solo tiene " <> tshow libres <> " trabajadores libres"))
        else Right ()
    else if cuadrilla /= 0
      then Left (Rechazo (eid <> " no lleva cuadrilla"))
      else Right ()
  case deOficio d of
    Just (k, dmin) | dominio est fac k < dmin ->
      Left (Rechazo ("falta oficio para " <> eid <> ": " <> k <> " " <> mostrarFijo (dominio est fac k)
                     <> ", mínimo " <> mostrarFijo dmin))
    _ -> Right ()
  let tesoro = baseFaccion fac magTesoro est
  if tesoro < deCostoValor d
    then Left (Rechazo ("no alcanza el tesoro: " <> eid <> " cuesta " <> mostrarFijo (deCostoValor d)
                        <> " y hay " <> mostrarFijo tesoro))
    else Right ()
  let obra = Obra eid 0 (deVeintenas d) (if conCuadrilla d then cuadrilla else 0) (Fijo 0) Map.empty Map.empty []
      jue' = jue { ppAltepetl = Map.insert alt a { altObra = Just obra } (ppAltepetl jue) }
      alm' = sumarBase (entFac fac) magTesoro (negarF (deCostoValor d)) (comunMagnitudes com)
  pure (est { estadoPersistente = p { persistenteJuego = jue', persistenteComun = com { comunMagnitudes = alm' } } }, [])
  where
    p   = estadoPersistente est
    jue = persistenteJuego p
    com = persistenteComun p

-- | El sistema de construcción (paso 10, cada veintena). Primero avanza las
-- obras en orden de altépetl: recibe el tributo en especie que llega y cobra
-- su transporte del tesoro (por eso el tesoro tiene dos escritores, la
-- hacienda y este), manda a extraer el que se pidió, y trabaja con la
-- cuadrilla local. Después recalcula el beneficio de cada tipo de edificio en
-- cada altépetl que tiene alguno. Es el único que añade o cambia
-- modificadores de edificio y el único que escribe la base de lo que sumen
-- los efectos al terminar (el prestigio).
construccion :: Constantes -> Edificios -> Sistema Purepecha
construccion c eds = Sistema
  { sisNombre   = NombreSistema "construccion"
  , sisCadencia = Periodo
  , sisLee      = Set.empty
  , sisEscribe  = Set.fromList (magTesoro : map (magTacito . cnId) (edConocimientos eds)
                                ++ [ dmeMagnitud m | d <- Map.elems (edDefs eds), m <- deMods d ]
                                ++ [ m | d <- Map.elems (edDefs eds), SumarBase _ m _ <- deAlTerminar d ])
  , sisEjecutar = \_ est ->
      if Map.null (edDefs eds) then (est, []) else
      let jue = persistenteJuego (estadoPersistente est)
          -- La partida de obras es de cada facción: lo que sobra a una no
          -- sostiene las cuadrillas de otra.
          partidas = Map.fromList [ (facId f, gastoPunto c (pbObras (facPresupuesto f)) ./. cTicksPorAnio c)
                                  | f <- activas jue ]
          umbrales = Map.fromList [ (facId f, pbObras (facPresupuesto f) >= cObrasPresupuestoMinimo c)
                                  | f <- activas jue ]
          enObra = [ (altId a, o) | a <- Map.elems (ppAltepetl jue), Just o <- [altObra a] ]
          paso (e, hs0, rs) (alt, o) =
            let f = facDeAlt jue alt
                (e', hs', r') = avanzar c eds (Map.findWithDefault False f umbrales) f
                                        (e, hs0, Map.findWithDefault (Fijo 0) f rs) (alt, o)
            in (e', hs', Map.insert f r' rs)
          (est1, hs, _) = foldl' paso (est, [], partidas) enObra
      in (recalcularBeneficios eds est1, hs)
  }

avanzar :: Constantes -> Edificios -> Bool -> FaccionId -> (Estado Purepecha, [Hecho], Fijo) -> (AltId, Obra)
        -> (Estado Purepecha, [Hecho], Fijo)
avanzar c eds umbral fac (est, hs, restante) (alt, o) = case Map.lookup (obEdificio o) (edDefs eds) of
  -- Un edificio que desapareció de los datos (un guardado con otro archivo):
  -- la obra se termina sin efectos, para no quedar colgada.
  Nothing -> (conObra Nothing [] est, hs, restante)
  Just d
    | obCuadrilla o == 0 ->
        if umbral then terminarSi d o { obAvance = obAvance o + 1 } restante est else (est, hs, restante)
    | otherwise ->
        let t = let Tick x = estadoTick est in fromIntegral x :: Int
            der = derivadoJuego (estadoDerivado est)
            -- η, el oficio: el dominio del conocimiento entre 100 (1 sin oficio).
            -- Sin ningún dominio la gente no rinde nada: la obra espera.
            eta = max (Fijo 1) (productividad est fac d)
            -- 1. Llegan las entregas de tributo cuyo día llegó, si el tesoro
            --    paga su transporte; si no, esperan a la veintena siguiente.
            llegar (e, acop, quedan) en
              | enLlega en > t = (e, acop, quedan ++ [en])
              | baseFaccion fac magTesoro e < enCosto en = (e, acop, quedan ++ [en])
              | otherwise =
                  let m = Map.findWithDefault (Fijo 0) (enMaterial en) (deMateriales d)
                      ya = Map.findWithDefault (Fijo 0) (enMaterial en) acop
                  in (pagar (enCosto en) e, Map.insert (enMaterial en) (min m (ya .+. enCantidad en)) acop, quedan)
            (est1, acopio1, enCamino1) = foldl' llegar (est, obAcopio o, []) (obEnCamino o)
            enCaminoDe g ec = foldl' (.+.) (Fijo 0) [ enCantidad en | en <- ec, enMaterial en == g ]
            faltaDe g acop ec = Map.findWithDefault (Fijo 0) g (deMateriales d)
                                .-. Map.findWithDefault (Fijo 0) g acop .-. enCaminoDe g ec
            -- 2. Los altépetl que envían tributo extraen con su gente y lo
            --    mandan; tarda y cuesta según la distancia por el grafo.
            enviar ec (g, tr) =
              let falta = faltaDe g acopio1 ec
                  celdas = Map.findWithDefault [] g (Map.findWithDefault Map.empty (toFuente tr) (dpMateriales der))
                  dist = Map.lookup alt (dpDistancias der) >>= Map.lookup (toFuente tr)
              in case dist of
                   Just dd | falta > Fijo 0, not (null celdas) ->
                     let e = min (toCuadrilla tr) (trabajadoresPara (falta ./. eta) celdas)
                         x = min falta (eta .*. Map.findWithDefault (Fijo 0) g (produccionCeldas e celdas))
                     in if x <= Fijo 0 then ec
                        else ec ++ [Entrega g x (toFuente tr) (t + diasDeTransporte c dd) (cCostoTransporte c .*. x .*. dd)]
                   _ -> ec
            enCamino2 = foldl' enviar enCamino1 (Map.toList (obTributos o))
            -- 3. La cuadrilla local, si la partida de obras la sostiene.
            s = cSustentoCuadrilla c
            sostenibles = if s <= Fijo 0 then obCuadrilla o
                          else let Fijo r = restante; Fijo sv = s in fromIntegral (r `div` sv)
            cef = max 0 (min (obCuadrilla o) sostenibles)
            restante' = restante .-. desdeEntero cef .*. s
            mats = Map.findWithDefault Map.empty alt (dpMateriales der)
            extraer (libres, acop) (g, _) =
              let falta = faltaDe g acop enCamino2
                  celdas = Map.findWithDefault [] g mats
              in if falta <= Fijo 0 || libres <= 0 || null celdas then (libres, acop) else
                 let e = min libres (trabajadoresPara (falta ./. eta) celdas)
                     x = min falta (eta .*. Map.findWithDefault (Fijo 0) g (produccionCeldas e celdas))
                 in (libres - e, Map.insert g (Map.findWithDefault (Fijo 0) g acop .+. x) acop)
            (libresL, acopio2) = foldl' extraer (cef, acopio1) (Map.toList (deMateriales d))
            fraccion = if Map.null (deMateriales d) then uno
                       else minimum [ min uno (Map.findWithDefault (Fijo 0) g acopio2 ./. m)
                                    | (g, m) <- Map.toList (deMateriales d) ]
            tope = deTrabajo d .*. fraccion
            trabajo' = max (obTrabajo o) (min tope (obTrabajo o .+. eta .*. desdeEntero libresL))
            o' = o { obAcopio = acopio2, obEnCamino = enCamino2 }
        in if cef == 0
             then terminarSi d o' restante est1
             else terminarSi d o' { obAvance = obAvance o + 1, obTrabajo = trabajo' } restante' est1
  where
    pagar costo e = let p = estadoPersistente e; com = persistenteComun p
                    in e { estadoPersistente = p { persistenteComun = com { comunMagnitudes =
                             sumarBase (entFac fac) magTesoro (negarF costo) (comunMagnitudes com) } } }
    terminarSi d o' rest e0
      | listo d o' =
          let ref  = entRefAlt alt
              entD AlAltepetl = ref
              entD AlaFaccion = entFac fac
              est1 = conObra Nothing [deId d] e0
              p    = estadoPersistente est1
              com  = persistenteComun p
              alm  = foldl' (\al (SumarBase e m v) -> sumarBase (entD e) m v al) (comunMagnitudes com) (deAlTerminar d)
              (alm', fuera) = quitarAgravioTributo alt (obTributos o') alm
              alm'' = maybe alm' (\(k, _) -> practica eds fac k (persistenteJuego p) alm') (deOficio d)
              est2 = est1 { estadoPersistente = p { persistenteComun = com { comunMagnitudes = alm'' } } }
              t = estadoTick e0
          in (est2, hs ++ [Hecho "edificio_terminado" t [ref] (Map.fromList [("edificio", deId d)])]
                       ++ map (hechoModificadorTerminado t "fuente") fuera, rest)
      | otherwise = (conObra (Just o') [] e0, hs, rest)
    listo d o' = obAvance o' >= obTotal o' && obTrabajo o' >= deTrabajo d
                 && and [ Map.findWithDefault (Fijo 0) g (obAcopio o') >= m | (g, m) <- Map.toList (deMateriales d) ]
    conObra mo nuevos e =
      let p   = estadoPersistente e
          jue = persistenteJuego p
          upd a = a { altObra = mo, altEdificios = altEdificios a ++ nuevos }
      in e { estadoPersistente = p { persistenteJuego = jue { ppAltepetl = Map.adjust upd alt (ppAltepetl jue) } } }

-- | El beneficio de cada tipo de edificio en cada altépetl que tiene alguno
-- (sección 14i): un modificador por (tipo, altépetl, magnitud), con fuente
-- @edificio:<id>:<alt>@, cuyo valor se fija con la fórmula. Los fieles salen
-- del derivado; los sacerdotes, de los pops del altépetl.
recalcularBeneficios :: Edificios -> Estado Purepecha -> Estado Purepecha
recalcularBeneficios eds est =
  let p    = estadoPersistente est
      jue  = persistenteJuego p
      com  = persistenteComun p
      der  = derivadoJuego (estadoDerivado est)
      conEd = [ a | a <- Map.elems (ppAltepetl jue), not (null (altEdificios a)) ]
      altsCon = Set.fromList (map altId conEd)
      sacerdotes = Map.fromListWith (.+.)
        [ ((popAltepetl pop, trId t), fi (popTamano pop) .*. afinidad t pop)
        | pop <- Map.elems (ppPops jue), popEstrato pop == estratoSacerdote
        , Set.member (popAltepetl pop) altsCon, t <- edTradiciones eds ]
      valores = concat
        [ [ (fuenteEdificio e (altId a), entD (dmeEntidad m), dmeMagnitud m
            , beneficio (dmeFormula m) (deCulto d) n (fieles (deCulto d)) (sac (deCulto d)) (dmeAporte m)
            , detalleBeneficio (dmeFormula m) (deCulto d) n (fieles (deCulto d)) (sac (deCulto d)))
          | m <- deMods d ]
        | a <- conEd
        , (e, n) <- Map.toList (Map.fromListWith (+) [ (x, 1 :: Int) | x <- altEdificios a ])
        , Just d <- [Map.lookup e (edDefs eds)]
        , let entD AlAltepetl = entRefAlt (altId a)
              entD AlaFaccion = entFac (altFaccion a)
              clave cu = (altId a, cuTradicion cu)
              fieles = maybe (Fijo 0) (\cu -> Map.findWithDefault (Fijo 0) (clave cu)
                                               (if cuNivel cu == Local then dpFielesLocal der else dpFielesCentro der))
              sac = maybe (Fijo 0) (\cu -> Map.findWithDefault (Fijo 0) (clave cu) sacerdotes)
        ]
      -- Cambia el aporte del modificador existente; si no hay, se añade.
      fijar (alm, nuevos) (f, ent, mag, ap, det) =
        let base0 = if mag == magProduccionAlt then baseProduccionAlt else Fijo 0
            x = Map.findWithDefault (AlmacenMag base0 []) (ent, mag) alm
        in if any ((== f) . modFuente) (almacenMods x)
             then (Map.insert (ent, mag) x { almacenMods = [ if modFuente m == f then m { modAporte = ap, modDetalle = det } else m
                                                           | m <- almacenMods x ] } alm, nuevos)
             else (Map.insert (ent, mag) x alm,
                   Modificador 0 mag ent ap f Nothing Nothing Nothing AlcancePropia det : nuevos)
      -- Los nuevos se acumulan al revés y se invierten una vez: con miles de
      -- templos, pegarlos al final uno a uno era cuadrático.
      (alm1, nuevosAlReves) = foldl' fijar (comunMagnitudes com, []) valores
      alm2 = agregarVarios (reverse nuevosAlReves) alm1
  in if null conEd then est
     else est { estadoPersistente = p { persistenteComun = com { comunMagnitudes = alm2 } } }

-- ---------------------------------------------------------------------------
-- Tributo en especie (etapa 2)
-- ---------------------------------------------------------------------------

-- | La fuente del agravio que paga quien envía tributo para una obra.
fuenteTributo :: AltId -> Text -> Fuente
fuenteTributo (AltId a) g = Fuente "tributo_obra" (T.pack (show a) <> ":" <> g)

-- | Los días que tarda una carga en recorrer d km de llano: veintenas
-- enteras, al menos una (sección 14i).
diasDeTransporte :: Constantes -> Fijo -> Int
diasDeTransporte c (Fijo d) =
  let Fijo v = cVelocidadTransporte c
      veintenas = if v <= 0 then 1 else max 1 (fromIntegral ((d + v - 1) `div` v))
  in 20 * veintenas

-- | Las distancias por el costo del grafo de cada altépetl con obra en curso
-- a las cabeceras de los demás, hasta 'cAlcanceTributo' (paso 16). Un
-- recorrido acotado por obra: las obras se cuentan por decenas aunque los
-- altépetl sean miles.
derivarDistancias :: Constantes -> Grafo -> Purepecha -> Map AltId (Map AltId Fijo)
derivarDistancias c gr p
  | null conObra = Map.empty
  | otherwise = Map.fromList [ (altId a, dist a) | a <- conObra ]
  where
    alts = ppAltepetl p
    conObra = [ a | a <- Map.elems alts, Just _ <- [altObra a] ]
    -- Qué altépetl tiene su cabecera en cada celda, una sola vez.
    porCelda = IntMap.fromListWith (++) [ (altCelda b, [altId b]) | b <- Map.elems alts ]
    -- El recorrido persistente: su costo es lo que alcanza, no el tamaño del
    -- mapa, como pasaría con los arreglos de 'propagarGrafo'.
    dist a =
      let et = propagar UnGrupo (Just (cAlcanceTributo c)) (grafoMapa gr)
                 [(CeldaId (altCelda a), Etiqueta (Fijo 0) 0 0)] IntMap.empty
      in Map.fromList [ (b, etDistancia (primera m))
                      | (cel, m) <- IntMap.toList et, b <- IntMap.findWithDefault [] cel porCelda, b /= altId a ]

-- | Pide a otro altépetl de la facción que envíe un material como tributo en
-- especie para la obra de @alt@, con @cuadrilla@ trabajadores suyos. Se
-- rechaza sin daño si no hay obra con cuadrilla, si la obra no pide ese
-- material o ya lo tiene pedido, si el que envía es el mismo altépetl, no
-- existe, no tiene el material al alcance o le faltan trabajadores, o si está
-- fuera de alcance o la obra aún no pasó una veintena (la distancia sale del
-- derivado). Al aceptarse, sus trabajadores se retiran y su altépetl recibe
-- el agravio del tributo, con fuente @tributo_obra@, hasta que la obra
-- termine.
pedirTributo :: Constantes -> Edificios -> FaccionId -> AltId -> Text -> AltId -> Int -> Estado Purepecha
             -> Either Rechazo (Estado Purepecha, [Hecho])
pedirTributo c eds fac alt g fuente cuadrilla est = do
  a <- maybe (Left (Rechazo "el altépetl no existe")) Right (Map.lookup alt (ppAltepetl jue))
  if altFaccion a /= fac then Left (Rechazo (altNombre a <> " no es de tu facción")) else Right ()
  o <- maybe (Left (Rechazo (altNombre a <> " no tiene obra en curso"))) Right (altObra a)
  d <- maybe (Left (Rechazo ("edificio desconocido: " <> obEdificio o))) Right (Map.lookup (obEdificio o) (edDefs eds))
  if obCuadrilla o == 0 then Left (Rechazo (obEdificio o <> " no lleva cuadrilla ni material")) else Right ()
  if Map.member g (deMateriales d) then Right () else Left (Rechazo (obEdificio o <> " no pide " <> g))
  if Map.member g (obTributos o) then Left (Rechazo ("ya hay un pedido de " <> g <> " para " <> altNombre a)) else Right ()
  if fuente == alt then Left (Rechazo "un altépetl no se manda tributo a sí mismo") else Right ()
  f <- maybe (Left (Rechazo "el altépetl que envía no existe")) Right (Map.lookup fuente (ppAltepetl jue))
  -- Quien envía tributo en especie es de la misma facción: un altépetl de otra
  -- no envía, su lado es el comercio (V5, *Las obras*).
  if altFaccion f /= fac then Left (Rechazo (altNombre f <> " es de otra facción y no envía tributo")) else Right ()
  if null (Map.findWithDefault [] g (Map.findWithDefault Map.empty fuente (dpMateriales der)))
    then Left (Rechazo ("no hay " <> g <> " al alcance de " <> altNombre f)) else Right ()
  case Map.lookup alt (dpDistancias der) of
    Nothing -> Left (Rechazo ("el tributo para la obra de " <> altNombre a <> " se pide desde la veintena siguiente a su inicio"))
    Just ds | not (Map.member fuente ds) -> Left (Rechazo (altNombre f <> " está fuera del alcance del tributo"))
    _ -> Right ()
  let libres = Map.findWithDefault 0 fuente (trabajadoresDe c jue)
  if cuadrilla < 1 || cuadrilla > libres
    then Left (Rechazo (altNombre f <> " puede poner de 1 a " <> tshow libres <> " trabajadores"))
    else Right ()
  let o' = o { obTributos = Map.insert g (TributoObra fuente cuadrilla) (obTributos o) }
      jue' = jue { ppAltepetl = Map.insert alt a { altObra = Just o' } (ppAltepetl jue) }
      m = Modificador 0 magTasaAgravio (entRefAlt fuente) (Aporte (cAgravioTributoObra c) (Fijo 0))
                      (fuenteTributo alt g) Nothing Nothing Nothing AlcancePropia []
      alm' = agregarVarios [m] (comunMagnitudes com)
  pure (est { estadoPersistente = p { persistenteJuego = jue', persistenteComun = com { comunMagnitudes = alm' } } }, [])
  where
    p   = estadoPersistente est
    jue = persistenteJuego p
    com = persistenteComun p
    der = derivadoJuego (estadoDerivado est)

-- | Quita los agravios de tributo de una obra que terminó y los devuelve,
-- para que cada uno emita @modificador_terminado@.
quitarAgravioTributo :: AltId -> Map Text TributoObra -> Almacen -> (Almacen, [Modificador])
quitarAgravioTributo alt trs alm0 = foldl' quitar (alm0, []) (Map.toList trs)
  where
    quitar (alm, fuera) (g, tr) =
      let k = (entRefAlt (toFuente tr), magTasaAgravio)
          f = fuenteTributo alt g
      in case Map.lookup k alm of
           Nothing -> (alm, fuera)
           Just x  -> (Map.insert k x { almacenMods = filter ((/= f) . modFuente) (almacenMods x) } alm,
                       fuera ++ filter ((== f) . modFuente) (almacenMods x))

-- | Aprender haciendo (sección 14i): el modificador de la práctica sobre el
-- conocimiento tácito de la facción que construye, con fuente @practica:<k>@ y valor
-- α · ln(1 + n), con n los edificios terminados que piden ese oficio. Se fija
-- al terminar cada obra; no hay otro escritor de ese modificador.
practica :: Edificios -> FaccionId -> Text -> Purepecha -> Almacen -> Almacen
practica eds fac k jue alm =
  case [ cn | cn <- edConocimientos eds, cnId cn == k ] of
    [] -> alm
    (cn : _) ->
      let n = length [ () | a <- Map.elems (ppAltepetl jue), altFaccion a == fac, e <- altEdificios a
                          , Just d <- [Map.lookup e (edDefs eds)], fmap fst (deOficio d) == Just k ]
          ap = Aporte (cnPractica cn .*. lnF (desdeEntero (n + 1))) (Fijo 0)
          det = [("obras", desdeEntero n)]
          clave = (entFac fac, magTacito k)
          f = fuentePractica k
          x = Map.findWithDefault (AlmacenMag (Fijo 0) []) clave alm
      in if any ((== f) . modFuente) (almacenMods x)
           then Map.insert clave x { almacenMods = [ if modFuente m == f then m { modAporte = ap, modDetalle = det } else m
                                                 | m <- almacenMods x ] } alm
           else agregarVarios [Modificador 0 (magTacito k) (entFac fac) ap f Nothing Nothing Nothing AlcancePropia det] alm

negarF :: Fijo -> Fijo
negarF (Fijo x) = Fijo (negate x)

tshow :: Int -> Text
tshow = T.pack . show

mostrarFijo :: Fijo -> Text
mostrarFijo f = case A.toJSON f of
  A.String t -> t
  otro       -> T.pack (show otro)
