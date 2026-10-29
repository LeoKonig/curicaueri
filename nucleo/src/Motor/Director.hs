{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | El director: decide en qué fase está la partida y qué situación se le
-- presenta al jugador, y cuándo. Es el narrador del paso 17 de V5, ampliado
-- con tensión, variedad y novedad. Es puro y determinista: su azar sale de
-- su propio generador y su memoria es estado persistente ('EstadoDirector').
module Motor.Director
  ( -- * Fases
    pasoFases
  , intensidad
    -- * Situaciones
  , pasoDirector
  , responderDecision
  , evaluar
    -- * Métricas del hito 0
  , Metricas (..)
  , metricas
  , cumpleVariedad
  ) where

import Data.List (sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Azar
import Motor.Base
import Motor.Efectos
import Motor.Estado
import Motor.Guion
import Motor.Hechos
import Motor.Magnitudes

-- ---------------------------------------------------------------------------
-- Estado del director dentro del estado
-- ---------------------------------------------------------------------------

director :: Estado s -> EstadoDirector
director = comunDirector . persistenteComun . estadoPersistente

conDirector :: EstadoDirector -> Estado s -> Estado s
conDirector d e =
  let p = estadoPersistente e
      c = persistenteComun p
  in e { estadoPersistente = p { persistenteComun = c { comunDirector = d } } }

-- | La intensidad de una fuente de presión en la fase en curso (1 si la fase
-- no la menciona). Los sistemas de presión la leen para escalar su efecto.
intensidad :: Text -> Estado s -> Fijo
intensidad fuente e = Map.findWithDefault uno fuente (edIntensidades (director e))

-- ---------------------------------------------------------------------------
-- Condiciones
-- ---------------------------------------------------------------------------

evaluar :: Map Magnitud DefMagnitud -> Estado s -> Condicion -> Bool
evaluar cat e = go
  where
    alm = comunMagnitudes (persistenteComun (estadoPersistente e))
    valor r m = case (Map.lookup (r, m) alm, Map.lookup m cat) of
      (Just x, Just d)  -> valorEn (estadoTick e) (dmRango d) x
      (Just x, Nothing) -> valorEn (estadoTick e) (RangoMag (Fijo minBound) (Fijo maxBound)) x
      _                 -> Fijo 0
    go = \c -> case c of
      Siempre     -> True
      Mayor r m u -> valor r m > u
      Menor r m u -> valor r m < u
      DesdeTick n -> let Tick t = estadoTick e in t >= n
      Todas cs    -> all go cs
      Alguna cs   -> any go cs
      No c'       -> not (go c')

-- ---------------------------------------------------------------------------
-- Fases
-- ---------------------------------------------------------------------------

-- | Al empezar el tick: entra en la primera fase si aún no hay ninguna, y
-- avanza mientras la siguiente ya debería haber empezado (por su día o por
-- su condición, lo que llegue primero). Nunca retrocede. Al entrar en una
-- fase, copia al estado sus sistemas activos y sus intensidades, y emite el
-- hecho `fase`.
--
-- Una fuente de presión que la nueva fase apaga deja de correr; lo que ya
-- aportó vive en modificadores que expiran solos, así que su magnitud vuelve
-- a la base sin saltos.
pasoFases :: Map Magnitud DefMagnitud -> Guion -> Tick -> Estado s -> (Estado s, [Hecho])
pasoFases cat g t@(Tick tt) e
  | null fases = (e, [])
  | otherwise =
      let actual = edFase (director e)
          destino = avanzar (max 0 actual)
          avanzar i
            | i + 1 < length fases && empieza (fases !! (i + 1)) = avanzar (i + 1)
            | otherwise = i
          empieza f = maybe False (<= tt) (faDesde f) || maybe False (evaluar cat e) (faCondicion f)
      in if destino == actual then (e, []) else
           let f = fases !! destino
               d = (director e) { edFase = destino, edSistemas = faSistemas f, edIntensidades = faIntensidades f }
           in (conDirector d e, [Hecho "fase" t [] (Map.fromList [("fase", faId f)])])
  where
    fases = guFases g

faseEnCurso :: Guion -> Estado s -> Text
faseEnCurso g e = case drop (edFase (director e)) (guFases g) of
  (f : _) | edFase (director e) >= 0 -> faId f
  _ -> ""

-- ---------------------------------------------------------------------------
-- Situaciones
-- ---------------------------------------------------------------------------

-- | Paso 17. Primero aplica la opción por omisión a las decisiones cuyo plazo
-- venció; después decide si presenta una situación nueva y cuál.
pasoDirector :: Map Magnitud DefMagnitud -> Guion -> Rng -> Tick -> Estado s -> (Estado s, [Hecho])
pasoDirector cat g rng0 t e0 =
  let (e1, hs1) = vencerPlazos g t e0
      (e2, hs2) = presentar cat g rng0 t e1
  in (e2, hs1 ++ hs2)

vencerPlazos :: Guion -> Tick -> Estado s -> (Estado s, [Hecho])
vencerPlazos g t e0 = foldl vencer (e0, []) vencidas
  where
    vencidas = [ i | (i, limite) <- Map.toAscList (edPlazos (director e0)), limite <= t ]
    vencer (e, hs) i =
      let pendiente = Map.lookup i (comunDecisiones (persistenteComun (estadoPersistente e)))
          resolver respuesta = case responderDecision g i respuesta e of
            Right (e', hs') -> (e', hs ++ hs' ++ [Hecho "plazo_vencido" t [] (Map.fromList [("decision", tshow i), ("opcion", respuesta)])])
            Left _ -> (quitarPlazo i e, hs)
      in case pendiente of
           Just dp -> case dpPregunta dp of
             PreguntaOpcion _ (o : _) -> resolver o
             PreguntaCantidad _ lo _  -> resolver (tshow lo)
             _                        -> (quitarPlazo i e, hs)
           Nothing -> (e, hs)

quitarPlazo :: Int -> Estado s -> Estado s
quitarPlazo i e = let d = director e in conDirector d { edPlazos = Map.delete i (edPlazos d) } e

presentar :: Map Magnitud DefMagnitud -> Guion -> Rng -> Tick -> Estado s -> (Estado s, [Hecho])
presentar cat g rng0 t@(Tick tt) e
  | null (guSituaciones g) = (e, [])
  | diasDesde < fromIntegral (pdEspaciado p) = (e, [])
  | u1 >= prob = (e, [])
  | otherwise = maybe (e, []) disparar elegida
  where
    p = guDirector g
    d = director e
    diasDesde = maybe (tt + fromIntegral (pdEspaciado p)) (\(Tick u) -> tt - u) (edUltima d)
    extra = Fijo (fromIntegral (diasDesde - fromIntegral (pdEspaciado p)) * 10000)
    prob = min (pdProbMax p) (pdProbBase p .+. pdTension p .*. extra)
    (u1, rng1) = uniforme rng0
    (u2, _)    = uniforme rng1
    fase = faseEnCurso g e
    decada = tt `div` fromIntegral (pdDiasDecada p)
    recientes = map diTipo (take (pdVentanaVariedad p) (edHistorial d))
    enDecada = Set.fromList [ diTipo x | x <- edHistorial d, let Tick xt = diTick x, xt `div` fromIntegral (pdDiasDecada p) == decada ]
    pendientes = Set.fromList [ rnEvento (dpReanudacion dp) | dp <- Map.elems (comunDecisiones (persistenteComun (estadoPersistente e))) ]
    ultimaDe sid = case [ xt | x <- edHistorial d, diSituacion x == sid, let Tick xt = diTick x ] of
      (xt : _) -> Just xt
      []       -> Nothing
    elegible s =
         (null (siFases s) || fase `elem` siFases s)
      && maybe True (\xt -> tt - xt >= fromIntegral (siEnfriamiento s)) (ultimaDe (siId s))
      && not (siId s `Set.member` pendientes)
      && evaluar cat e (siCondicion s)
    peso s =
      let n = length (filter (== siTipo s) recientes)
          variedad = uno ./. (uno .+. pdPenalVariedad p .*. Fijo (fromIntegral n * 10000))
          novedad = if siTipo s `Set.member` enDecada then uno else uno .+. pdBonoNovedad p
      in siPeso s .*. variedad .*. novedad
    elegibles = [ (s, peso s) | s <- sortOn siId (guSituaciones g), elegible s, peso s > Fijo 0 ]
    total = foldr ((.+.) . snd) (Fijo 0) elegibles
    objetivo = u2 .*. total
    elegida = escoger objetivo elegibles
    -- Elección ponderada: recorre las elegibles (ordenadas por id) restando
    -- pesos hasta que el objetivo cae dentro de una. Sin elegibles, nada.
    escoger _ [] = Nothing
    escoger _ [(s, _)] = Just s
    escoger r ((s, w) : resto) = if r < w then Just s else escoger (r .-. w) resto
    disparar s =
      let i = siguienteId e
          dp = DecisionPendiente i (PreguntaOpcion "opcion" (map fst (siOpciones s))) (Reanudacion (siId s) "" 0 Map.empty)
          c = persistenteComun (estadoPersistente e)
          e' = e { estadoPersistente = (estadoPersistente e)
                     { persistenteComun = c { comunDecisiones = Map.insert i dp (comunDecisiones c) } } }
          d' = d { edUltima = Just t
                 , edHistorial = Disparo t (siId s) (siTipo s) fase : edHistorial d
                 , edPlazos = Map.insert i (Tick (tt + fromIntegral (siPlazo s))) (edPlazos d)
                 , edProximaDecision = i + 1 }
      in ( conDirector d' e'
         , [Hecho "situacion" t [] (Map.fromList
             [("situacion", siId s), ("tipo", siTipo s), ("fase", fase), ("decision", tshow i)])] )

-- | Responde una decisión pendiente presentada por el director: elegir una
-- opción, o dar la cantidad que pide un efecto de esa opción. La opción se
-- ejecuta con el intérprete de efectos; si vuelve a preguntar algo, queda
-- otra decisión pendiente.
responderDecision :: Guion -> Int -> Text -> Estado s -> Either Rechazo' (Estado s, [Hecho])
responderDecision g i respuesta e = do
  dp <- maybe (Left "decisión no encontrada") Right
          (Map.lookup i (comunDecisiones (persistenteComun (estadoPersistente e))))
  let rn = dpReanudacion dp
  s <- maybe (Left "la decisión no es de una situación del guion") Right
         (lookupSit (rnEvento rn))
  let e0 = quitarPlazo i (quitarDecision i e)
  resultado <- case dpPregunta dp of
    PreguntaOpcion _ opciones
      | respuesta `notElem` opciones -> Left ("opción inválida: " <> respuesta)
      | otherwise -> do
          prog <- maybe (Left "opción sin programa") Right (lookup respuesta (siOpciones s))
          pure (interpretar (siId s) respuesta prog 0 Map.empty e0)
    PreguntaCantidad _ lo hi -> case reads (T.unpack respuesta) of
      [(n, "")] | n >= lo && n <= hi -> do
        prog <- maybe (Left "opción sin programa") Right (lookup (rnOpcion rn) (siOpciones s))
        pure (reanudar (CEntero n) dp prog e0)
      _ -> Left ("cantidad fuera de rango (" <> tshow lo <> " a " <> tshow hi <> ")")
  let resuelta = Hecho "situacion_resuelta" (estadoTick e) []
                   (Map.fromList [("situacion", siId s), ("decision", tshow i), ("respuesta", respuesta)])
  case resultado of
    Completado (_, e', hs) -> Right (e', hs ++ [resuelta])
    Suspendido q rn' (e', hs) -> Right (aplicarResultado (siguienteId e') (Suspendido q rn' (e', [])) e', hs)
    Fallo m -> Left m
  where
    lookupSit sid = case [ s | s <- guSituaciones g, siId s == sid ] of
      (s : _) -> Just s
      []      -> Nothing

type Rechazo' = Text

tshow :: Show a => a -> Text
tshow = T.pack . show

-- ---------------------------------------------------------------------------
-- Métricas del hito 0, sobre el historial del director
-- ---------------------------------------------------------------------------

data Metricas = Metricas
  { mTotal          :: Int
  , mPorTipo        :: Map Text Int
  , mParteMaxima    :: Double            -- ^ fracción del tipo más frecuente
  , mNovedades      :: [Int]             -- ^ por década completa desde la segunda: tipos que no salieron en la anterior
  } deriving (Eq, Show)

-- | Métricas de una partida de @dias@ días, con décadas de @diasDecada@.
-- Solo cuentan las décadas completas.
metricas :: Int -> Int -> EstadoDirector -> Metricas
metricas diasDecada dias d =
  let hist = reverse (edHistorial d)
      porTipo = Map.fromListWith (+) [ (diTipo x, 1 :: Int) | x <- hist ]
      total = length hist
      parte = if total == 0 then 0 else fromIntegral (maximum (Map.elems porTipo)) / fromIntegral total
      decadas = dias `div` diasDecada
      tiposDe k = Set.fromList [ diTipo x | x <- hist, let Tick xt = diTick x, fromIntegral xt `div` diasDecada == k ]
      novedades = [ Set.size (tiposDe k `Set.difference` tiposDe (k - 1)) | k <- [1 .. decadas - 1] ]
  in Metricas total porTipo parte novedades

-- | El criterio de variedad del hito 0: ningún tipo supera la fracción dada
-- (0,25 en V5) y cada década trae al menos @n@ tipos nuevos (2 en V5).
cumpleVariedad :: Double -> Int -> Metricas -> Bool
cumpleVariedad parteMax n m = mTotal m > 0 && mParteMaxima m <= parteMax && all (>= n) (mNovedades m)
