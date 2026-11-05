{-# LANGUAGE StrictData, OverloadedStrings #-}
module Reglas.Constantes where

import Motor.Base
import Reglas.Base

-- | Constantes del hito 0a: los valores de `hito_0/datos/constantes.json`
-- (bloques `economia`, `eficiencia` y `ticks_por_anio`), que el generador de
-- tablas usa también. Si cambian allí, cambian aquí y las tablas lo confirman.
-- Las marcadas «literal» son números escritos dentro de las fórmulas del
-- prototipo, sin entrada en el JSON.
data Constantes = Constantes
  { cIngresoPorPop         :: Fijo   -- economia.ingreso_por_pop (0.012)
  , cTasaBase              :: Int    -- economia.tasa_base
  , cNeutralTasa           :: Int    -- literal: la tasa de referencia del agravio (3)
  , cAgravioSubirImpuesto  :: Fijo   -- economia.agravio_subir_impuesto
  , cAgravioBajarImpuesto  :: Fijo   -- economia.agravio_bajar_impuesto
  , cTesoroPorPunto        :: Fijo   -- economia.tesoro_por_punto_presupuesto
  , cTicksPorAnio          :: Fijo   -- ticks_por_anio: veintenas por año
    -- Eficiencia de un altépetl (`effLines`), en puntos de 0 a 100.
  , cEfBase                :: Int    -- eficiencia.base
  , cEfPorAdminGobernador  :: Int    -- eficiencia.por_admin_gobernador
  , cEfPorDistancia        :: Int    -- eficiencia.por_distancia
  , cEfBonoAdmin25         :: Int    -- eficiencia.bono_admin_25
  , cEfPorAdminCazonci     :: Int    -- eficiencia.por_admin_cazonci
  , cEfIdentidadAjena      :: Int    -- eficiencia.por_fraccion_identidad_ajena
  , cEfMin                 :: Int    -- eficiencia.clamp[0]
  , cEfMax                 :: Int    -- eficiencia.clamp[1]
  , cUmbralPresupuestoAdm  :: Int    -- literal: presupuesto de administración que da el bono (25)
  , cUmbralIdentidadAjena  :: Fijo   -- literal: fracción mínima de pobladores ajenos (0.001)
  , cAdminNeutral          :: Int    -- literal: administración que no suma ni resta (3)
    -- Agravio del gobernador (`popParts`): (base − administración) × por punto.
  , cGobernadorAgravioBase :: Int    -- literal: 2
  , cGobernadorAgravioPunto :: Int   -- literal: 3
    -- Obras (`step`): la partida de obras mínima para que avancen.
  , cObrasPresupuestoMinimo :: Int   -- construccion.presupuesto_minimo
    -- Producción (documento funcional, sección 12). PROVISIONALES: el
    -- prototipo no las tiene; se fijan al calibrar el hito 3.
  , cFraccionTrabajadora   :: Fijo   -- FRACCION_TRABAJADORA: parte de un pop productivo que trabaja
  , cRadioProduccion     :: Fijo   -- RADIO_PRODUCCION: hasta dónde trabaja un altépetl, en km de llano por el costo del grafo
    -- Obras y templos (V5, *Las obras*; sección 14i). PROVISIONALES.
  , cSustentoCuadrilla     :: Fijo   -- SUSTENTO_CUADRILLA: valor por trabajador de cuadrilla y veintena
  , cAlcanceTemploLocal    :: Fijo   -- ALCANCE_TEMPLO_LOCAL: hasta dónde va un pop a su templo local
  , cAlcanceCentro         :: Fijo   -- ALCANCE_CENTRO_CEREMONIAL: hasta dónde llega el peregrinaje
    -- Tributo en especie de materiales (etapa 2). PROVISIONALES.
  , cVelocidadTransporte   :: Fijo   -- VELOCIDAD_TRANSPORTE: km de llano que recorre una carga por veintena
  , cCostoTransporte       :: Fijo   -- COSTO_TRANSPORTE: valor por unidad y km de llano
  , cAlcanceTributo        :: Fijo   -- ALCANCE_TRIBUTO: hasta dónde se pide material
  , cAgravioTributoObra    :: Fijo   -- AGRAVIO_TRIBUTO_OBRA: puntos por año en quien lo envía
    -- Fusión de pops (V5, *Escala de la simulación*). PROVISIONALES: es una
    -- mecánica de rendimiento, como POP_MERGE_MAX_WORKFORCE de Victoria 3.
  , cFusionTamano          :: Int    -- FUSION_TAMANO: un pop más chico que esto se funde; 0, ninguno
  , cFusionGradiente       :: Fijo   -- FUSION_GRADIENTE: diferencia máxima de gradiente de catolicismo
  , cFusionLealtad         :: Fijo   -- FUSION_LEALTAD: diferencia máxima de lealtad, en puntos
  , cFusionAgravio         :: Fijo   -- FUSION_AGRAVIO: diferencia máxima de agravio, en puntos
    -- El azar de la cosecha (V5, *Decisiones recurrentes*, Mala cosecha). PROVISIONALES.
  , cCosechaMinima         :: Fijo   -- COSECHA_MINIMA: el peor año, como factor sobre la cosecha normal
  , cCosechaMaxima         :: Fijo   -- COSECHA_MAXIMA: el mejor año
    -- Subsistencia (V5, *Medidas reales y cifras de referencia*). PROVISIONAL.
  , cRacionMaiz            :: Fijo   -- RACION_MAIZ: toneladas de maíz que come una persona en un año
  , cTributoEspecie        :: Fijo   -- TRIBUTO_ESPECIE: parte de la cosecha que va a las trojes por punto de la tasa de tributo
  , cAgravioHambre         :: Fijo   -- AGRAVIO_HAMBRE: puntos de agravio por año con cobertura 0
  , cUmbralHambre          :: Fijo   -- UMBRAL_HAMBRE: la cobertura por debajo de la cual hay hecho «hambre»
    -- La dieta (V5, *La dieta*; T27). PROVISIONALES.
  , cNecesidadEnergia      :: Fijo   -- NECESIDAD_ENERGIA: t de maíz equivalente por persona y año, con datos/dieta.json
  , cKcalMaiz              :: Fijo   -- KCAL_MAIZ: kilocalorías por kilogramo de maíz, la unidad de la t ME
  } deriving (Eq, Show)

constantesDefault :: Constantes
constantesDefault = Constantes
  { cIngresoPorPop         = Fijo 120        -- 0.012 = 120 / 10 000
  , cTasaBase              = 3
  , cNeutralTasa           = 3
  , cAgravioSubirImpuesto  = fi 4
  , cAgravioBajarImpuesto  = fi 2
  , cTesoroPorPunto        = fi 6
  , cTicksPorAnio          = fi 18
  , cEfBase                = 40
  , cEfPorAdminGobernador  = 12
  , cEfPorDistancia        = -10
  , cEfBonoAdmin25         = 5
  , cEfPorAdminCazonci     = 4
  , cEfIdentidadAjena      = -20
  , cEfMin                 = 20
  , cEfMax                 = 100
  , cUmbralPresupuestoAdm  = 25
  , cUmbralIdentidadAjena  = Fijo 10         -- 0.001 = 10 / 10 000
  , cAdminNeutral          = 3
  , cGobernadorAgravioBase = 2
  , cGobernadorAgravioPunto = 3
  , cObrasPresupuestoMinimo = 20
  , cFraccionTrabajadora   = Fijo 2500       -- 0,25, provisional
    -- Provisional. V5 propone 10 km de llano con celdas de unos 5 km (dos
    -- anillos); el mapa provisional del escenario tiene celdas de 20 km, así
    -- que dos anillos de llano son 40. Una sierra (μ = 3) vecina ya cuesta 40:
    -- es la última celda que se alcanza por ese lado.
  , cRadioProduccion     = fi 40
    -- Con la partida de obras del escenario (30 puntos: 10 por veintena), el
    -- sustento alcanza para una cuadrilla de 500.
  , cSustentoCuadrilla     = Fijo 200        -- 0,02, provisional
  , cAlcanceTemploLocal    = fi 60           -- tres anillos del mapa provisional, provisional
  , cAlcanceCentro         = fi 200          -- diez anillos, provisional
    -- Los cargadores recorren unos 20 km al día (por verificar), pero el
    -- material se junta, se carga y se descarga: 100 km de llano por veintena.
  , cVelocidadTransporte   = fi 100
  , cCostoTransporte       = Fijo 100        -- 0,01, provisional
  , cAlcanceTributo        = fi 300
  , cAgravioTributoObra    = fi 2
    -- Un pop de menos de 1 000 personas es una aldea o un barrio: por debajo
    -- de eso, distinguir dos con la misma clave y casi los mismos valores no
    -- cambia ninguna decisión. Las diferencias son de relleno.
  , cFusionTamano          = 1000
  , cFusionGradiente       = Fijo 500        -- 0,05, provisional
  , cFusionLealtad         = fi 10
  , cFusionAgravio         = fi 10
    -- Un año de cosecha va de la mitad a una vez y media de lo normal, sorteado
    -- parejo: el promedio es 1 y, a la larga, la producción no cambia. Un año
    -- por debajo de 0,75 (uno de cada cuatro) es «mala cosecha». Provisional.
  , cCosechaMinima         = Fijo 5000       -- 0,5
  , cCosechaMaxima         = Fijo 15000      -- 1,5
    -- 2 000 kcal por día, 0,8 de ellas del maíz, a 3 650 kcal por kg: 0,44 kg
    -- por día, unos 0,164 t por año; por encima de los 120,5 kg del consumo
    -- moderno (FAOSTAT 2014), como cabe en una dieta menos variada. Por
    -- verificar: la parte de la energía que venía del maíz (V5).
  , cRacionMaiz            = Fijo 1640       -- 0,164 t por persona y año
    -- 5 % de la cosecha por punto de la tasa (de 5 % con tasa 1 a 25 % con
    -- tasa 5; 15 % con la neutra). Por verificar con la *Relación de
    -- Michoacán* y los estudios del tributo tarasco (V5).
  , cTributoEspecie        = Fijo 500
    -- Con cobertura 0 un pop gana 20 puntos de agravio en el año; con 0,5, 10.
  , cAgravioHambre         = fi 20
    -- Por debajo de 0,8 de cobertura el año es de hambre y entra en la crónica.
  , cUmbralHambre          = Fijo 8000
    -- 2 000 kcal por persona y día, toda la energía: 730 000 kcal al año, que
    -- son 0,2 t de maíz de 3 650 kcal/kg. Por verificar con las tablas de la FAO.
  , cNecesidadEnergia      = Fijo 2000
  , cKcalMaiz              = fi 3650         -- USDA, maíz en grano: 365 kcal por 100 g
  }
