{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Los escenarios. Un escenario es un archivo de @escenarios/@ con sus
-- fechas, su calendario, su mapa provisional y la lista de archivos de
-- facciones (@datos/facciones/@) con sus altépetl, pops y personajes
-- (documento funcional, sección 17; V5, *Alcance*). 'cargarEscenario' lo
-- convierte en el estado inicial y acumula todos los errores, como el guion.
--
-- 'estadoInicial1475' es el mismo tutorial escrito en Haskell: lo usan las
-- pruebas y la cáscara cuando no se le da @--escenario@. Una prueba comprueba
-- que @escenarios/tutorial_1475.json@ da exactamente este estado, así que no
-- pueden separarse.
module Reglas.Escenario where

import Data.Aeson (Value, withObject, (.:), (.:?), (.!=))
import qualified Data.Aeson.Types as A
import qualified Data.IntSet as IntSet
import Data.List (group, sort)
import Data.Maybe (isJust, isNothing, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as Map
import qualified Data.Sequence as Seq
import Data.Word (Word64)

import Motor.Base
import Motor.Calendario (CalendarioVisible (..), Fecha (..), calendarioVeintenas, diaJuliano)
import Motor.Carga (CategoriaError (..), ErrorCarga (..), Validacion (..), falla)
import Motor.Mapa (DatosHex (..))
import Motor.Estado
import Motor.Magnitudes
import Reglas.Base
import Reglas.Estado

escenario1475 :: Purepecha
escenario1475 = Purepecha
  { ppAltepetl = Map.fromList
      [ (AltId 1, Altepetl (AltId 1) "Tzintzuntzan"
                    (Just (PerId 2)) (fi 0) Nothing (fi 80) 63 Nothing [] f1 (Cabecera f1))
      , (AltId 2, Altepetl (AltId 2) "Zacapu"
                    (Just (PerId 3)) (fi 2) (Just (AltId 1)) (fi 60) 33 Nothing [] f1 Sujeto)
      , (AltId 3, Altepetl (AltId 3) "Uruapan"
                    (Just (PerId 4)) (fi 1) (Just (AltId 1)) (fi 75) 101 Nothing [] f1 Sujeto)
      ]
  , ppPops = Map.fromList
      [ (PopId 1, Pop (PopId 1) (AltId 1) "purepecha" "nobleza" 3000  (fi 80) (Fijo 0))
      , (PopId 2, Pop (PopId 2) (AltId 1) "purepecha" "comun"   27000 (fi 70) (Fijo 0))
      , (PopId 3, Pop (PopId 3) (AltId 2) "purepecha" "comun"   8400  (fi 55) (Fijo 0))
      , (PopId 4, Pop (PopId 4) (AltId 2) "hnahnu"    "comun"   3600  (fi 45) (Fijo 0))
      , (PopId 5, Pop (PopId 5) (AltId 3) "purepecha" "comun"   15300 (fi 70) (Fijo 0))
      , (PopId 6, Pop (PopId 6) (AltId 3) "nahua"     "comun"   2700  (fi 50) (Fijo 0))
        -- Sacerdotes de los templos de cada altépetl (V5, *Las obras*). Cifras de
        -- relleno, por verificar con la *Relación de Michoacán*: Tzintzuntzan,
        -- centro del culto de Curicaueri, concentra a la mayoría.
      , (PopId 7, Pop (PopId 7) (AltId 1) "purepecha" "sacerdote" 400 (fi 85) (Fijo 0))
      , (PopId 8, Pop (PopId 8) (AltId 2) "purepecha" "sacerdote" 60  (fi 70) (Fijo 0))
      , (PopId 9, Pop (PopId 9) (AltId 3) "purepecha" "sacerdote" 100 (fi 75) (Fijo 0))
      ]
  , ppPersonajes = Map.fromList
      -- Grupos ilustrativos, por verificar: el linaje real y el Inepto son de la
      -- nobleza guerrera; el Capaz, de los administradores. El cazonci no tiene grupo.
      [ (PerId 1, Personaje (PerId 1) "Zuangua"          3 2 40 True Nothing f1)
      , (PerId 2, Personaje (PerId 2) "Tangáxoan"        4 3 28 True (Just "nobleza_guerrera") f1)
      , (PerId 3, Personaje (PerId 3) "Gobernador Inepto" 1 2 45 True (Just "nobleza_guerrera") f1)
      , (PerId 4, Personaje (PerId 4) "Gobernador Capaz"   3 2 38 True (Just "administradores") f1)
      ]
  , ppFacciones   = Map.singleton f1 $
      -- El cazonci es Zuangua, de administración 3.
      (faccionUnica (PerId 1) (Tasas 3 3) (Presupuesto 30 25 30 15 0))
        { facTipo = tipoFaccion1475 }
  }
  where f1 = FaccionId 1

estadoInicial1475 :: Estado Purepecha
estadoInicial1475 =
  let p    = escenario1475
      mags = Map.fromList $
        [ ((entRefPop (PopId i), Magnitud "agravio"), AlmacenMag (fi ag) [])
        | (i, ag) <- [(1, 10), (2, 20), (3, 40), (4, 45), (5, 15), (6, 20)]
        ] ++
        [ ((entRefAlt (AltId i), magProduccionAlt), AlmacenMag baseProduccionAlt []) | i <- [1, 2, 3] ] ++
        [ ((entFac (FaccionId 1), magTesoro),      AlmacenMag (fi 1000) [])
        , ((entFac (FaccionId 1), magPrestigio),   AlmacenMag (fi 20) [])
        , ((entFac (FaccionId 1), magLegitimidad), AlmacenMag (fi 50) [])
        ]
  in estadoDe 0 p mags

-- | El tipo de facción del reino purépecha, que elige las bases de sus grupos
-- de poder en @datos/grupos.json@ (V5, *Tipos de facción*).
tipoFaccion1475 :: Text
tipoFaccion1475 = "reino_centralizado"

-- | Mapa provisional del escenario: una cuadrícula hexagonal de 14 × 10 con
-- terrenos pseudoaleatorios. Tzintzuntzan en la celda 63, Zacapu al noroeste
-- (33) y Uruapan al suroeste (101). El mapa real llega con el atlas.
datosMapa1475 :: DatosHex
datosMapa1475 = DatosHex 14 10 (fi 20) 1475

-- | Fecha juliana del tick 0.
inicio1475 :: Fecha
inicio1475 = Fecha 1475 1 1

-- | Calendario visible: juliano y, en la Nueva España, gregoriano desde
-- octubre de 1583, un año después que en Europa (V5, *Calendario visible*).
-- El último día juliano exacto está por verificar con fuente; el prototipo
-- termina en 1530, así que aún no se usa.
-- | Ejes de poder activos en el escenario (V5, *Cinco ejes de poder*): por
-- omisión, todos los de @datos/ejes.json@. En el prototipo ninguna fórmula los
-- lee, así que declararlos o no solo cambia lo que el cliente puede mostrar.
ejesActivos1475 :: Maybe [Text]
ejesActivos1475 = Nothing

visible1475 :: CalendarioVisible
visible1475 = CambioAGregoriano (Fecha 1583 10 4)

-- | El escenario sobre un mapa hexagonal de otro tamaño: las cabeceras se
-- colocan en la misma posición relativa que en su mapa de @ancho0@ ×
-- @alto0@. Sirve para la prueba de rendimiento del hito 2 (unos 2 700
-- hexágonos).
reubicar :: (Int, Int) -> Int -> Int -> Estado Purepecha -> Estado Purepecha
reubicar (ancho0, alto0) ancho alto e =
  let mover a = let (f, c) = altCelda a `divMod` ancho0
                    c' = c * ancho `div` ancho0
                    f' = f * alto `div` alto0
                in a { altCelda = f' * ancho + c' }
      p  = estadoPersistente e
      j  = persistenteJuego p
      j' = j { ppAltepetl = Map.map mover (ppAltepetl j) }
      p' = p { persistenteJuego = j' }
  in e { estadoPersistente = p', estadoOrigen = Origen (Tick 0) p' }

-- | El escenario con @n@ altépetl sujetos más, de @k@ pops cada uno, repartidos
-- por un mapa de @celdas@ celdas. Solo sirve para medir cuánto cuesta la
-- simulación a la escala del mapa completo (unos 7 500 asentamientos y
-- 150 000 celdas) antes de diseñar optimizaciones. Los altépetl copian a
-- Zacapu: sujetos de Tzintzuntzan, con su gobernador y su distancia.
escalar :: Int -> Int -> Int -> Estado Purepecha -> Estado Purepecha
escalar celdas n k e
  | n <= 0 || k <= 0 = e
  | otherwise =
      let p   = estadoPersistente e
          j   = persistenteJuego p
          com = persistenteComun p
          a0  = 1 + maximum (0 : [ i | AltId i <- Map.keys (ppAltepetl j) ])
          p0  = 1 + maximum (0 : [ i | PopId i <- Map.keys (ppPops j) ])
          identidades = ["purepecha", "hnahnu", "nahua"]
          alts = [ Altepetl (AltId (a0 + x)) "Sujeto de prueba" (Just (PerId 3)) (fi (1 + x `mod` 3))
                            (Just (AltId 1)) (fi 60) ((x * 7919) `mod` max 1 celdas) Nothing [] (FaccionId 1) Sujeto
                 | x <- [0 .. n - 1] ]
          pops = [ Pop (PopId (p0 + x * k + y)) (AltId (a0 + x)) (identidades !! (y `mod` 3)) "comun" 500 (fi 60) (Fijo 0)
                 | x <- [0 .. n - 1], y <- [0 .. k - 1] ]
          ags  = [ ((entRefPop (popId q), Magnitud "agravio"), AlmacenMag (fi 30) []) | q <- pops ]
              ++ [ ((entRefAlt (altId a), magProduccionAlt), AlmacenMag baseProduccionAlt []) | a <- alts ]
          j'   = j { ppAltepetl = Map.union (ppAltepetl j) (Map.fromList [ (altId a, a) | a <- alts ])
                   , ppPops     = Map.union (ppPops j) (Map.fromList [ (popId q, q) | q <- pops ]) }
          com' = com { comunMagnitudes = Map.union (comunMagnitudes com) (Map.fromList ags) }
          p'   = p { persistenteJuego = j', persistenteComun = com' }
      in e { estadoPersistente = p', estadoOrigen = Origen (Tick 0) p' }

-- ---------------------------------------------------------------------------
-- Escenarios como datos (T13)
-- ---------------------------------------------------------------------------

-- | Lo que declara un archivo de @escenarios/@. Las facciones vienen en
-- archivos aparte, con rutas relativas al del escenario.
data Escenario = Escenario
  { escId        :: Text
  , escNombre    :: Text
  , escInicio    :: Fecha              -- ^ fecha juliana del tick 0
  , escFin       :: Maybe Fecha        -- ^ la partida termina ese día (el guion puede añadir derrotas)
  , escDesfase   :: Int                -- ^ día del año del calendario de veintenas en que cae el tick 0
  , escVisible   :: CalendarioVisible
  , escMapa      :: DatosHex           -- ^ el mapa provisional, hasta el atlas
  , escEjes      :: Maybe [Text]       -- ^ ejes de poder activos; sin lista, todos los de @datos/ejes.json@
  , escFacciones :: [FilePath]         -- ^ archivos de facciones, relativos al escenario
  , escGuion     :: Maybe FilePath     -- ^ el guion del escenario, relativo a él; @--guion@ lo reemplaza
  }

-- | El tutorial escrito en Haskell, como escenario: sus fechas, su
-- calendario y su mapa. Sirve a la cáscara cuando no se le da @--escenario@.
escenarioTutorial :: Escenario
escenarioTutorial = Escenario "tutorial_1475" "Tutorial 1475-1530" inicio1475 (Just (Fecha 1530 2 14)) 0
                              visible1475 datosMapa1475 ejesActivos1475 [] Nothing

-- | Lee una fecha AAAA-MM-DD.
leerFecha :: Text -> A.Parser Fecha
leerFecha t = case T.splitOn "-" t of
  [a, m, d] | [(y, "")] <- reads (T.unpack a), [(mm, "")] <- reads (T.unpack m), [(dd, "")] <- reads (T.unpack d)
            , mm >= 1, mm <= 12, dd >= 1, dd <= 31 -> pure (Fecha y mm dd)
  _ -> fail ("fecha inválida (se espera AAAA-MM-DD): " <> T.unpack t)

-- | El tick de una fecha, contado desde el inicio del escenario.
tickDeFecha :: Fecha -> Fecha -> Int
tickDeFecha inicio f = diaJuliano f - diaJuliano inicio

-- | Lee el archivo del escenario. Los errores de forma son de estructura;
-- los de contenido se acumulan en 'cargarEscenario'.
leerEscenario :: Text -> Value -> Validacion Escenario
leerEscenario archivo v = case A.parseEither leer v of
  Left err -> falla (ErrorCarga ErrorEstructura archivo "" (T.pack err))
  Right e  -> pure e
  where
    leer = withObject "escenario" $ \o -> do
      eid <- o .: "id"
      nombre <- o .:? "nombre" .!= eid
      inicio <- o .: "inicio" >>= leerFecha
      fin <- o .:? "fin" >>= traverse leerFecha
      desfase <- o .:? "desfase_calendario" .!= 0
      visible <- o .:? "ultimo_dia_juliano" >>= maybe (pure SoloJuliano) (fmap CambioAGregoriano . leerFecha)
      mapa <- o .: "mapa" >>= withObject "mapa" (\m ->
                DatosHex <$> m .: "ancho" <*> m .: "alto" <*> m .:? "radio_km" .!= fi 20 <*> m .:? "semilla" .!= (0 :: Word64))
      ejes <- o .:? "ejes"
      facs <- o .: "facciones"
      guion <- o .:? "guion"
      pure (Escenario eid nombre inicio fin desfase visible mapa ejes facs guion)

-- Lo que se lee de un archivo de facciones, antes de validarlo.
data FaccionD = FaccionD
  { fdId :: Int, fdNombre :: Text, fdTipo :: Text, fdEstado :: EstadoFaccion, fdJugable :: Bool
  , fdDesde :: Maybe Fecha, fdHasta :: Maybe Fecha, fdAbsorbente :: Maybe Int
  , fdGobernante :: Int, fdTasas :: Tasas, fdPresupuesto :: Presupuesto
  , fdTesoro :: Maybe Fijo, fdPrestigio :: Maybe Fijo, fdLegitimidad :: Maybe Fijo
  , fdPersonajes :: [PersonajeD], fdAltepetl :: [AltepetlD] }

data PersonajeD = PersonajeD
  { pdId :: Int, pdNombre :: Text, pdAdmin :: Int, pdMando :: Int, pdEdad :: Int, pdGrupo :: Maybe Text }

data AltepetlD = AltepetlD
  { adId :: Int, adNombre :: Text, adCelda :: Int, adCondicion :: Text, adSujetoA :: Maybe Int
  , adGobernador :: Maybe Int, adDistancia :: Fijo, adLealtad :: Fijo, adPops :: [PopD] }

data PopD = PopD
  { qdId :: Int, qdIdentidad :: Text, qdEstrato :: Text, qdTamano :: Int, qdLealtad :: Fijo, qdAgravio :: Maybe Fijo }

leerFacciones :: Value -> A.Parser [FaccionD]
leerFacciones = withObject "archivo de facciones" $ \o -> o .: "facciones" >>= mapM faccion
  where
    faccion = withObject "faccion" $ \o -> do
      estado <- o .:? "estado" .!= ("activa" :: Text) >>= \t -> case t of
        "activa"    -> pure Activa
        "potencial" -> pure Potencial
        _           -> fail ("estado de facción desconocido (activa o potencial): " <> T.unpack t)
      FaccionD <$> o .: "id" <*> o .: "nombre" <*> o .: "tipo" <*> pure estado <*> o .:? "jugable" .!= False
        <*> (o .:? "desde" >>= traverse leerFecha) <*> (o .:? "hasta" >>= traverse leerFecha) <*> o .:? "absorbente"
        <*> o .: "gobernante"
        <*> (o .:? "tasas" >>= maybe (pure (Tasas 3 3)) (withObject "tasas" (\t -> Tasas <$> t .: "tributo" <*> t .: "impuesto")))
        <*> (o .:? "presupuesto" >>= maybe (pure (Presupuesto 30 25 30 15 0)) (withObject "presupuesto" (\p ->
               Presupuesto <$> p .: "ejercito" <*> p .: "administracion" <*> p .: "obras" <*> p .: "diplomacia" <*> p .: "culto")))
        <*> o .:? "tesoro" <*> o .:? "prestigio" <*> o .:? "legitimidad"
        <*> (o .:? "personajes" .!= [] >>= mapM personaje)
        <*> (o .: "altepetl" >>= mapM altepetl)
    personaje = withObject "personaje" $ \o ->
      PersonajeD <$> o .: "id" <*> o .: "nombre" <*> o .: "admin" <*> o .: "mando" <*> o .: "edad" <*> o .:? "grupo"
    altepetl = withObject "altepetl" $ \o ->
      AltepetlD <$> o .: "id" <*> o .: "nombre" <*> o .: "celda" <*> o .: "condicion" <*> o .:? "sujeto_a"
        <*> o .:? "gobernador" <*> o .:? "distancia" .!= Fijo 0 <*> o .:? "lealtad" .!= fi 70
        <*> (o .: "pops" >>= mapM pop)
    pop = withObject "pop" $ \o ->
      PopD <$> o .: "id" <*> o .: "identidad" <*> o .: "estrato" <*> o .: "tamano" <*> o .:? "lealtad" .!= fi 60
        <*> o .:? "agravio"

-- | El estado inicial de un escenario a partir de sus archivos de facciones
-- (nombre del archivo y contenido, en el orden del escenario). Acumula todos
-- los errores: ids repetidos, referencias a personajes, altépetl o
-- facciones que no existen, cabeceras que faltan o sobran, celdas fuera del
-- mapa, fechas fuera del escenario y absorbentes que no estarán activos.
cargarEscenario :: Escenario -> [(Text, Value)] -> Validacion (Estado Purepecha)
cargarEscenario esc archivos = do
  porArchivo <- traverse leerArchivo archivos
  let fs = [ (a, f) | (a, xs) <- porArchivo, f <- xs ]
  () <$ traverse id (validaciones fs)
  pure (construir (map snd fs))
  where
    leerArchivo (a, v) = case A.parseEither leerFacciones v of
      Left m -> falla (ErrorCarga ErrorEstructura a "" (T.pack m))
      Right xs -> pure (a, xs)

    err cat a ruta m = falla (ErrorCarga cat a ruta m)
    tick = tickDeFecha (escInicio esc)
    celdas = hexAncho (escMapa esc) * hexAlto (escMapa esc)
    finTick = fmap tick (escFin esc)
    num :: Int -> Text
    num = T.pack . show

    validaciones fs =
      let facs = map snd fs
          porId = Map.fromList [ (fdId f, f) | f <- facs ]
          repetidos xs = [ head g | g <- group (sort xs), length g > 1 ]
          todosAlt = [ a | f <- facs, a <- fdAltepetl f ]
          altFac = Map.fromList [ (adId a, fdId f) | f <- facs, a <- fdAltepetl f ]
          enRango t = t >= 0 && maybe True (t <=) finTick
          activaAl f t = case Map.lookup f porId of
            Nothing -> False
            Just x -> maybe True (\d -> tick d <= t) (fdDesde x) && maybe True (\h -> tick h > t) (fdHasta x)
          jugables = [ f | f <- facs, fdJugable f ]
      in
      [ err ErrorEsquema "escenario" "facciones" ("id de facción repetido: " <> num i) | i <- repetidos (map fdId facs) ] ++
      [ err ErrorEsquema "escenario" "altepetl" ("id de altépetl repetido: " <> num i) | i <- repetidos (map adId todosAlt) ] ++
      [ err ErrorEsquema "escenario" "pops" ("id de pop repetido: " <> num i) | i <- repetidos [ qdId q | a <- todosAlt, q <- adPops a ] ] ++
      [ err ErrorEsquema "escenario" "personajes" ("id de personaje repetido: " <> num i) | i <- repetidos [ pdId p | f <- facs, p <- fdPersonajes f ] ] ++
      [ err ErrorEsquema (escId esc) "facciones" ("hace falta exactamente una facción jugable; hay " <> num (length jugables)) | length jugables /= 1 ] ++
      [ err ErrorEsquema (escId esc) "facciones" ("la facción jugable " <> num (fdId f) <> " tiene que estar activa al empezar")
      | f <- jugables, fdEstado f /= Activa ] ++
      concat [ validarFaccion a f altFac activaAl enRango | (a, f) <- fs ]

    validarFaccion archivo f altFac activaAl enRango =
      let ruta x = "facciones." <> num (fdId f) <> x
          pers = map pdId (fdPersonajes f)
          cabeceras = [ a | a <- fdAltepetl f, adCondicion a == "cabecera" ]
      in
      [ err ErrorReferencia archivo (ruta ".gobernante") ("el gobernante " <> num (fdGobernante f) <> " no es un personaje de la facción")
      | fdGobernante f `notElem` pers ] ++
      [ err ErrorEsquema archivo (ruta ".altepetl") ("hace falta exactamente una cabecera; hay " <> num (length cabeceras))
      | length cabeceras /= 1 ] ++
      [ err ErrorEsquema archivo (ruta ".desde") "una facción potencial necesita «desde»" | fdEstado f == Potencial, isNothing (fdDesde f) ] ++
      [ err ErrorEsquema archivo (ruta ".desde") "una facción activa al empezar no lleva «desde»" | fdEstado f == Activa, isJust (fdDesde f) ] ++
      [ err ErrorRango archivo (ruta ".desde") "la fecha queda fuera del escenario" | Just d <- [fdDesde f], not (enRango (tick d)) ] ++
      [ err ErrorRango archivo (ruta ".hasta") "la fecha queda fuera del escenario" | Just h <- [fdHasta f], not (enRango (tick h)) ] ++
      [ err ErrorRango archivo (ruta ".hasta") "«hasta» tiene que ser posterior a «desde»"
      | Just d <- [fdDesde f], Just h <- [fdHasta f], tick h <= tick d ] ++
      [ err ErrorReferencia archivo (ruta ".absorbente") ("el absorbente " <> num ab <> " no estará activo cuando la facción desaparezca")
      | Just ab <- [fdAbsorbente f], ab == fdId f || maybe True (not . activaAl ab . tick) (fdHasta f) ] ++
      [ err ErrorEsquema archivo (ruta ".absorbente") "un absorbente sin «hasta» nunca se usa" | isJust (fdAbsorbente f), isNothing (fdHasta f) ] ++
      concat [ validarAltepetl archivo f altFac pers a | a <- fdAltepetl f ]

    validarAltepetl archivo f altFac pers a =
      let ruta x = "altepetl." <> num (adId a) <> x
      in
      [ err ErrorRango archivo (ruta ".celda") ("la celda " <> num (adCelda a) <> " no está en el mapa de " <> num celdas <> " celdas")
      | adCelda a < 0 || adCelda a >= celdas ] ++
      [ err ErrorEsquema archivo (ruta ".condicion") ("condición desconocida (cabecera, sujeto o senorio): " <> adCondicion a)
      | adCondicion a `notElem` ["cabecera", "sujeto", "senorio"] ] ++
      [ err ErrorEsquema archivo (ruta ".sujeto_a") "una cabecera no está sujeta a otro altépetl"
      | adCondicion a == "cabecera", isJust (adSujetoA a) ] ++
      [ err ErrorReferencia archivo (ruta ".sujeto_a") "un sujeto o señorío tiene que estar sujeto a un altépetl de su facción"
      | adCondicion a `elem` ["sujeto", "senorio"]
      , maybe True (\s' -> Map.lookup s' altFac /= Just (fdId f)) (adSujetoA a) ] ++
      [ err ErrorReferencia archivo (ruta ".gobernador") ("el gobernador " <> num g <> " no es un personaje de la facción")
      | Just g <- [adGobernador a], g `notElem` pers ] ++
      [ err ErrorEsquema archivo (ruta ".pops") "un altépetl necesita al menos un pop" | null (adPops a) ]

    construir facs =
      let fac f = Faccion (FaccionId (fdId f)) (fdNombre f) (fdTipo f) (fdEstado f) (PerId (fdGobernante f))
                          (fdTasas f) (fdPresupuesto f) (fdJugable f) (fmap tick (fdDesde f)) (fmap tick (fdHasta f))
                          (maybe transferenciaNada (\ab -> let d = AlAbsorbente (FaccionId ab) in Transferencia d d d) (fdAbsorbente f))
          alt f a = Altepetl (AltId (adId a)) (adNombre a) (fmap PerId (adGobernador a)) (adDistancia a)
                             (fmap AltId (adSujetoA a)) (adLealtad a) (adCelda a) Nothing [] (FaccionId (fdId f))
                             (case adCondicion a of
                                "cabecera" -> Cabecera (FaccionId (fdId f))
                                "senorio"  -> Senorio
                                _          -> Sujeto)
          pop a q = Pop (PopId (qdId q)) (AltId (adId a)) (qdIdentidad q) (qdEstrato q) (qdTamano q) (qdLealtad q) (Fijo 0)
          per f p = Personaje (PerId (pdId p)) (pdNombre p) (pdAdmin p) (pdMando p) (pdEdad p) True (pdGrupo p) (FaccionId (fdId f))
          jue = Purepecha
            { ppAltepetl   = Map.fromList [ (AltId (adId a), alt f a) | f <- facs, a <- fdAltepetl f ]
            , ppPops       = Map.fromList [ (PopId (qdId q), pop a q) | f <- facs, a <- fdAltepetl f, q <- adPops a ]
            , ppPersonajes = Map.fromList [ (PerId (pdId p), per f p) | f <- facs, p <- fdPersonajes f ]
            , ppFacciones  = Map.fromList [ (FaccionId (fdId f), fac f) | f <- facs ]
            }
          mags = Map.fromList $
            [ ((entRefPop (PopId (qdId q)), Magnitud "agravio"), AlmacenMag ag [])
            | f <- facs, a <- fdAltepetl f, q <- adPops a, Just ag <- [qdAgravio q] ] ++
            [ ((entRefAlt (AltId (adId a)), magProduccionAlt), AlmacenMag baseProduccionAlt []) | f <- facs, a <- fdAltepetl f ] ++
            concat [ mapMaybe (\(m, x) -> fmap (\v -> ((entFac (FaccionId (fdId f)), m), AlmacenMag v [])) x)
                       [(magTesoro, fdTesoro f), (magPrestigio, fdPrestigio f), (magLegitimidad, fdLegitimidad f)]
                   | f <- facs ]
      in estadoDe (escDesfase esc) jue mags

-- | El estado en el tick 0 con el juego y el almacén dados.
estadoDe :: Int -> Purepecha -> Almacen -> Estado Purepecha
estadoDe desfase jue mags =
  let com = Comun
        { comunMagnitudes = mags
        , comunDecisiones = Map.empty
        , comunPlanes     = Map.empty
        , comunCronica    = Seq.empty
        , comunCalendario = calendarioVeintenas desfase
        , comunDirector   = directorInicial
        , comunMonedas    = Map.empty
        , comunFin        = Nothing
        , comunOcurridos  = Map.empty
        }
      per = Persistente com jue
  in Estado (Tick 0) per (Origen (Tick 0) per) (Derivado IntSet.empty derivadoPurepechaVacio)

