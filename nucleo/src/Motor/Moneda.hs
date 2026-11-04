{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Moneda designada e inflación (V5, *La moneda y la inflación*; documento
-- funcional, sección 14g).
--
-- El tesoro y los costos se cuentan en **unidades de valor**, que no cambian.
-- Cada bien tiene un precio en esas unidades, que depende de cuánto hay:
--
-- > p(g) = valor(g) · calidad(g) · (referencia(g) / disponible(g)) ^ elasticidad(g)
-- > disponible(g) = max(1, existencias(g) + producción(g) · horizonte)
--
-- Una entidad (una facción) puede designar un bien como su moneda. Entonces
-- algo que vale C cuesta C · P unidades de moneda, con P = 1 / p(moneda) el
-- **nivel de precios**. Si la moneda abunda, su precio baja, P sube y todo se
-- encarece: eso es la inflación, y sale sola de la fórmula. No hay dado.
--
-- El motor no sabe de dónde salen las existencias ni la producción: las lee de
-- dos magnitudes de la entidad (@bien.<id>.existencias@, @bien.<id>.produccion@)
-- que escribe el juego. Y escribe tres: @moneda.precio@, @moneda.nivel_precios@
-- y @moneda.inflacion@ (anual), que el cliente muestra como cualquier otra.
--
-- Las magnitudes nominales (@magnitudes_nominales@, típicamente el tesoro) se
-- cuentan en la moneda: al designar, cambiar o retirar la moneda se convierten
-- al tipo del día, sin ganar ni perder valor real. Después la inflación sí les
-- quita valor: un tesoro guardado en una moneda que abunda vale cada vez menos.
--
-- Un bien perecedero tiene merma (@merma@, por periodo): el juego la aplica a
-- sus existencias, y este módulo a las magnitudes nominales de quien lo tiene
-- por moneda. Un tesoro guardado en maíz se pudre con el maíz; guardar cuesta.
module Motor.Moneda
  ( -- * Bienes y parámetros
    Bien (..)
  , ParamsMoneda (..)
  , paramsMonedaPorOmision
  , Economia (..)
  , economiaVacia
  , cargarEconomia
    -- * Magnitudes
  , magExistencias
  , magProduccion
  , magMerma
  , rangoMerma
  , mermaEn
  , magPrecioMoneda
  , magNivelPrecios
  , magInflacion
    -- * Precios
  , precioBien
  , precioEn
  , precioMonedaDe
  , costoEnMoneda
  , enCuenta
  , aValor
  , inflacionDe
    -- * Designar y avanzar
  , designarMoneda
  , pasoMoneda
  ) where

import Data.Aeson (Value)
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import Data.IntSet (IntSet)
import Data.List (foldl')
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Calendario (CalendarioInterno (..), esInicioDePeriodo)
import Motor.Carga (CategoriaError (..), ErrorCarga (..), Validacion (..), falla)
import Motor.Estado
import Motor.Hechos
import Motor.Magnitudes

-- | Un bien que puede valer como pago. Todo es dato del escenario.
data Bien = Bien
  { bnId          :: Text
  , bnValor       :: Fijo   -- ^ valor por unidad con escasez 1 y calidad 1
  , bnCalidad     :: Fijo   -- ^ calidad monetaria, de 0 a 1: durabilidad, divisibilidad, portabilidad
  , bnReferencia  :: Fijo   -- ^ disponibilidad con la que la escasez vale 1
  , bnElasticidad :: Fijo   -- ^ de 0 (precio fijo) a 1 (proporcional a la escasez)
  , bnDesignable  :: Bool   -- ^ si puede designarse como moneda
  , bnMerma       :: Fijo   -- ^ fracción de lo guardado que se pierde cada periodo, de 0 (no se estropea) a menos de 1
  } deriving (Eq, Show)

data ParamsMoneda = ParamsMoneda
  { pmHorizonte    :: Fijo        -- ^ periodos de producción que cuentan como disponibles
  , pmPrecioMinimo :: Fijo        -- ^ piso del precio, para que P = 1/p nunca divida entre 0
  , pmNominales    :: [Magnitud]  -- ^ magnitudes de la entidad que se cuentan en su moneda (el tesoro)
  } deriving (Eq, Show)

paramsMonedaPorOmision :: ParamsMoneda
paramsMonedaPorOmision = ParamsMoneda (desdeEntero 6) (Fijo 1) []

data Economia = Economia
  { ecoBienes :: Map Text Bien
  , ecoParams :: ParamsMoneda
  } deriving (Eq, Show)

-- | Sin bienes: nadie puede designar moneda y el paso monetario no hace nada.
economiaVacia :: Economia
economiaVacia = Economia Map.empty paramsMonedaPorOmision

-- ---------------------------------------------------------------------------
-- Magnitudes
-- ---------------------------------------------------------------------------

magExistencias, magProduccion, magMerma :: Text -> Magnitud
magExistencias b = Magnitud ("bien." <> b <> ".existencias")
magProduccion b = Magnitud ("bien." <> b <> ".produccion")
-- | La merma efectiva del bien para la entidad, si el juego la lleva como
-- magnitud (para que una troje pueda bajarla con un modificador).
magMerma b = Magnitud ("bien." <> b <> ".merma")

-- | De 0 a menos de 1: nunca se pierde todo en un periodo.
rangoMerma :: RangoMag
rangoMerma = RangoMag (Fijo 0) (Fijo 9999)

-- | La merma del bien para la entidad: el valor efectivo de
-- @bien.<id>.merma@ si la entidad la tiene (base y modificadores), o la del
-- catálogo ('bnMerma') si no. La usan el paso monetario, para lo nominal, y
-- el juego, para las existencias: así las dos mermas son siempre la misma.
mermaEn :: IntSet -> Tick -> Almacen -> EntRef -> Bien -> Fijo
mermaEn vig t alm ent b = maybe (bnMerma b) (valorEn vig t rangoMerma) (Map.lookup (ent, magMerma (bnId b)) alm)

-- | Las tres que escribe este módulo, y solo este módulo.
magPrecioMoneda, magNivelPrecios, magInflacion :: Magnitud
magPrecioMoneda = Magnitud "moneda.precio"
magNivelPrecios = Magnitud "moneda.nivel_precios"
magInflacion = Magnitud "moneda.inflacion"

-- ---------------------------------------------------------------------------
-- Precios
-- ---------------------------------------------------------------------------

-- | El precio de un bien en unidades de valor, con sus existencias @x@ y su
-- producción por periodo @y@. No crece con @x@ ni con @y@; con elasticidad 0
-- vale siempre valor · calidad; nunca baja del piso.
precioBien :: ParamsMoneda -> Bien -> Fijo -> Fijo -> Fijo
precioBien pm b x y =
  let disponible = max uno (max (Fijo 0) x .+. max (Fijo 0) y .*. pmHorizonte pm)
      razon      = max (Fijo 1) (bnReferencia b ./. disponible)
      escasez
        | bnElasticidad b == Fijo 0 = uno
        | otherwise = case lnFijo razon of
            Right l -> expFijo (bnElasticidad b .*. l)
            Left _  -> uno           -- no ocurre: razon ≥ 0,0001
  in max (pmPrecioMinimo pm) (bnValor b .*. bnCalidad b .*. escasez)

-- | El precio de un bien para una entidad, leyendo sus existencias y su
-- producción (valores efectivos, con los modificadores condicionales
-- vigentes que diga @vig@; 0 si la entidad no las tiene).
precioEn :: ParamsMoneda -> IntSet -> Tick -> Almacen -> EntRef -> Bien -> Fijo
precioEn pm vig t alm ent b = precioBien pm b (leer (magExistencias (bnId b))) (leer (magProduccion (bnId b)))
  where
    leer m = maybe (Fijo 0) (valorEn vig t rangoAmplio) (Map.lookup (ent, m) alm)
    rangoAmplio = RangoMag (Fijo minBound) (Fijo maxBound)

-- | El precio actual de la moneda de una entidad, si designó una.
precioMonedaDe :: Economia -> Tick -> Estado s -> EntRef -> Maybe Fijo
precioMonedaDe ec t e ent = do
  em <- Map.lookup ent (comunMonedas (comun e))
  b  <- Map.lookup (emMoneda em) (ecoBienes ec)
  pure (precioEn (ecoParams ec) (derivadoVigentes (estadoDerivado e)) t (comunMagnitudes (comun e)) ent b)

-- | Cuántas unidades de moneda cuesta algo que vale @c@: c · P = c / p(moneda).
-- Nothing si la entidad no designó moneda (entonces se paga en valor).
costoEnMoneda :: Economia -> Tick -> Estado s -> EntRef -> Fijo -> Maybe Fijo
costoEnMoneda ec t e ent c = (c ./.) <$> precioMonedaDe ec t e ent

-- | Una cantidad en valor, expresada en la cuenta de la entidad: en su moneda
-- (c · P) si designó una, o igual si no. Es lo que cuesta un comando, y en lo
-- que se convierte un ingreso calculado en valor, al tipo del día.
enCuenta :: Economia -> Tick -> Estado s -> EntRef -> Fijo -> Fijo
enCuenta ec t e ent c = maybe c id (costoEnMoneda ec t e ent c)

-- | La inversa: cuánto vale una cantidad de la cuenta de la entidad (n · p).
aValor :: Economia -> Tick -> Estado s -> EntRef -> Fijo -> Fijo
aValor ec t e ent n = maybe n (n .*.) (precioMonedaDe ec t e ent)

-- | Inflación anual: cuánto subió el nivel de precios desde hace un año,
-- P(t) / P(t − 1 año) − 1 = p(hace un año) / p(ahora) − 1. Nothing hasta que
-- haya un año de historial.
inflacionDe :: CalendarioInterno -> EstadoMonetario -> Maybe Fijo
inflacionDe cal em =
  let n = ciPeriodosPorAnio cal
      h = emHistorial em
  in case h of
       ((_, ahora) : _) | n > 0, length h > n -> Just ((snd (h !! n) ./. ahora) .-. uno)
       _ -> Nothing

-- ---------------------------------------------------------------------------
-- Designar y avanzar
-- ---------------------------------------------------------------------------

-- | Designa un bien como moneda de la entidad (Just) o retira la designación
-- (Nothing). Cambiar de moneda empieza el historial de cero: la inflación de
-- la moneda anterior no se mezcla con la nueva. Si se rechaza, el estado no
-- cambia. Los precios se escriben en el acto, para que se vean enseguida.
designarMoneda :: Economia -> EntRef -> Maybe Text -> Tick -> Estado s -> Either Text (Estado s, [Hecho])
designarMoneda ec ent destino t e =
  let actual = emMoneda <$> Map.lookup ent (comunMonedas (comun e))
      -- Pasar de una cuenta cuyo precio es pDe a otra cuyo precio es pA: n · pDe / pA.
      convertir pDe pA alm = foldl' (\a mg -> Map.adjust (\x -> x { almacenBase = almacenBase x .*. pDe ./. pA }) (ent, mg) a)
                                    alm (pmNominales (ecoParams ec))
  in case destino of
       Nothing -> case actual of
         Nothing -> Left "no hay moneda designada"
         Just m  ->
           -- Lo nominal vuelve a contarse en valor: n · p(moneda), con el precio del día.
           let pAnt = maybe uno id (precioMonedaDe ec t e ent)
               e' = conComun e (\c -> c { comunMonedas = Map.delete ent (comunMonedas c)
                                        , comunMagnitudes = convertir pAnt uno
                                            (foldl' (\a mg -> Map.delete (ent, mg) a) (comunMagnitudes c)
                                              [magPrecioMoneda, magNivelPrecios, magInflacion]) })
           in Right (e', [Hecho "moneda_retirada" t [ent] (Map.fromList [("moneda", m)])])
       Just b -> case Map.lookup b (ecoBienes ec) of
         Nothing -> Left ("no hay ningún bien «" <> b <> "»")
         Just bien
           | not (bnDesignable bien) -> Left ("«" <> b <> "» no puede ser moneda")
           | actual == Just b        -> Left ("«" <> b <> "» ya es la moneda")
           | otherwise ->
               -- Lo nominal se convierte al tipo del día: de valor (o de la moneda
               -- anterior) a la nueva, sin ganar ni perder valor real.
               let p    = precioEn (ecoParams ec) (derivadoVigentes (estadoDerivado e)) t (comunMagnitudes (comun e)) ent bien
                   pAnt = maybe uno id (precioMonedaDe ec t e ent)
                   e' = conComun e (\c -> c
                          { comunMonedas = Map.insert ent (EstadoMonetario b t []) (comunMonedas c)
                          , comunMagnitudes = Map.delete (ent, magInflacion)
                                                (escribirPrecio ent p (convertir pAnt p (comunMagnitudes c))) })
               in Right (e', [Hecho "moneda_designada" t [ent]
                               (Map.fromList [("moneda", b), ("anterior", maybe "" id actual)])])

-- | Al empezar cada periodo, anota el precio de cada moneda designada y
-- actualiza precio, nivel de precios e inflación; si la moneda tiene merma,
-- lo nominal de la entidad (el tesoro) pierde esa fracción, como lo guardado
-- del bien: n · (1 − merma). Fuera de ese día, nada. Va después de los
-- sistemas (que mueven existencias y producción) y antes del derivado, así
-- que la merma alcanza lo que hay al cerrar el periodo, con lo que entró en
-- él.
pasoMoneda :: Economia -> Tick -> Estado s -> Estado s
pasoMoneda ec t e
  | Map.null monedas || not (esInicioDePeriodo cal t) = e
  | otherwise = conComun e (\c -> c { comunMonedas = monedas', comunMagnitudes = alm' })
  where
    com     = comun e
    cal     = comunCalendario com
    monedas = comunMonedas com
    n       = ciPeriodosPorAnio cal
    (monedas', alm') = Map.foldlWithKey' anotar (monedas, comunMagnitudes com) monedas
    anotar (ms, alm) ent em = case Map.lookup (emMoneda em) (ecoBienes ec) of
      Nothing -> (ms, alm)            -- el bien ya no está en el escenario: no se anota
      Just b ->
        let p   = precioEn (ecoParams ec) (derivadoVigentes (estadoDerivado e)) t alm ent b
            em' = em { emHistorial = take (n + 1) ((t, p) : emHistorial em) }
            alm1 = escribirPrecio ent p alm
            alm2 = maybe alm1 (\i -> fijarBase ent magInflacion i alm1) (inflacionDe cal em')
            alm3 = mermarNominales (ecoParams ec) ent (mermaEn (derivadoVigentes (estadoDerivado e)) t alm ent b) alm2
        in (Map.insert ent em' ms, alm3)

-- | Lo nominal de la entidad pierde la fracción @m@: n · (1 − m). Con
-- merma 0 no cambia nada.
mermarNominales :: ParamsMoneda -> EntRef -> Fijo -> Almacen -> Almacen
mermarNominales pm ent m alm
  | m <= Fijo 0 = alm
  | otherwise = foldl' (\a mg -> Map.adjust (\x -> x { almacenBase = almacenBase x .*. (uno .-. m) }) (ent, mg) a)
                       alm (pmNominales pm)

escribirPrecio :: EntRef -> Fijo -> Almacen -> Almacen
escribirPrecio ent p = fijarBase ent magNivelPrecios (uno ./. p) . fijarBase ent magPrecioMoneda p

comun :: Estado s -> Comun s
comun = persistenteComun . estadoPersistente

conComun :: Estado s -> (Comun s -> Comun s) -> Estado s
conComun e f = let p = estadoPersistente e
               in e { estadoPersistente = p { persistenteComun = f (persistenteComun p) } }

-- ---------------------------------------------------------------------------
-- Carga
-- ---------------------------------------------------------------------------

-- | Carga los bienes desde JSON y acumula todos los errores:
--
-- > {"horizonte": "6", "magnitudes_nominales": ["tesoro"], "bienes": [{"id": "plata", "valor": "2", "calidad_monetaria": "0.95",
-- >                                 "referencia": "2000", "elasticidad": "0.15", "designable": true, "merma": "0"}]}
--
-- Sin @merma@, el bien no se estropea.
cargarEconomia :: Text -> Value -> Validacion Economia
cargarEconomia archivo v = case A.parseEither leer v of
  Left err -> falla (ErrorCarga ErrorEstructura archivo "" (T.pack err))
  Right ((horizonte, nominales), bienes) ->
    let ids = map bnId bienes
        repetidos = [ i | (k, i) <- zip [0 :: Int ..] ids, i `elem` take k ids ]
        unicos = traverse (\i -> falla (ErrorCarga ErrorEsquema archivo ("bienes." <> i) "bien repetido")) repetidos
        horizonteOk = if horizonte >= Fijo 0 then pure ()
                      else falla (ErrorCarga ErrorRango archivo "horizonte" "el horizonte no puede ser negativo")
    in (\_ _ bs -> Economia (Map.fromList [ (bnId b, b) | b <- bs ])
                            paramsMonedaPorOmision { pmHorizonte = horizonte, pmNominales = nominales })
         <$> unicos <*> horizonteOk <*> traverse validar bienes
  where
    leer = A.withObject "economia" $ \o -> do
      h  <- maybe (pmHorizonte paramsMonedaPorOmision) id <$> o A..:? "horizonte"
      ns <- maybe [] (map Magnitud) <$> o A..:? "magnitudes_nominales"
      bs <- o A..: "bienes" >>= mapM bien
      pure ((h, ns), bs)
    bien = A.withObject "bien" $ \o ->
      Bien <$> o A..: "id" <*> o A..: "valor" <*> o A..: "calidad_monetaria"
           <*> o A..: "referencia" <*> o A..: "elasticidad"
           <*> (maybe False id <$> o A..:? "designable")
           <*> (maybe (Fijo 0) id <$> o A..:? "merma")
    validar b =
      let ruta c = "bienes." <> bnId b <> "." <> c
          rango c lo hi x = if x >= lo && x <= hi then pure ()
                            else falla (ErrorCarga ErrorRango archivo (ruta c) "fuera de [0, 1]")
          positivo c x = if x > Fijo 0 then pure ()
                         else falla (ErrorCarga ErrorRango archivo (ruta c) "debe ser mayor que 0")
          mermaOk = if bnMerma b >= Fijo 0 && bnMerma b < uno then pure ()
                    else falla (ErrorCarga ErrorRango archivo (ruta "merma") "la merma va de 0 a menos de 1")
      in (\_ _ _ _ _ -> b)
           <$> mermaOk
           <*> positivo "valor" (bnValor b)
           <*> rango "calidad_monetaria" (Fijo 0) uno (bnCalidad b)
           <*> positivo "referencia" (bnReferencia b)
           <*> rango "elasticidad" (Fijo 0) uno (bnElasticidad b)
