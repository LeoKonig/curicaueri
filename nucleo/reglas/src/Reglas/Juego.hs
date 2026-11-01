{-# LANGUAGE StrictData, TypeFamilies #-}
module Reglas.Juego where

import qualified Data.Aeson as A
import Data.List (foldl')
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Compartido (clavesCambiadas)
import Motor.Estado
import Motor.Hechos
import Motor.Juego
import Motor.Magnitudes
import Motor.Vista

import Reglas.Base
import Reglas.Comando
import Reglas.Constantes
import Reglas.Edificios
import Reglas.Produccion
import Motor.Mapa (Terreno)
import Motor.Recorrido (Grafo, grafoMapa)
import Motor.Terrenos (DefTerreno)
import Reglas.Estado
import Reglas.Grupos
import Reglas.Sistemas

catalogoMag :: Map.Map Magnitud DefMagnitud
catalogoMag = Map.fromList
  [ (Magnitud "agravio",
     DefMagnitud "agravio" (RangoMag (Fijo 0) (fi 100))
                  "m.agravio" Nothing False)
    -- Dos escritores: la hacienda y la construcción, que cobra el transporte
    -- del tributo en especie al llegar (V5, *Las obras*, etapa 2).
  , (magTesoro,
     DefMagnitud "tesoro" rangoTesoro "m.tesoro" Nothing True)
  , (magPrestigio,
     DefMagnitud "prestigio" rangoPrestigio "m.prestigio" Nothing False)
  , (magLegitimidad,
     DefMagnitud "legitimidad" rangoLegitimidad "m.legitimidad" Nothing False)
  , (magProduccionAlt,
     DefMagnitud "produccion" rangoProduccionAlt "m.produccion" Nothing False)
  , (magTasaAgravio,
     DefMagnitud "tasa_agravio" rangoTasaAgravio "m.tasa_agravio" Nothing False)
  , (magReservasAsedio,
     DefMagnitud "reservas_asedio" rangoReservasAsedio "m.reservas_asedio" Nothing False)
  ]

-- | Los datos de reglas que vienen de archivos: grupos de poder y edificios.
-- Sin archivos, nombrar no mueve poder y no hay nada que construir.
data DatosReglas = DatosReglas
  { drGrupos    :: Grupos
  , drEdificios :: Edificios
  , drTerrenos  :: Map.Map Terreno DefTerreno   -- ^ lo que rinde cada terreno; vacía, nada se produce
  }

datosVacios :: DatosReglas
datosVacios = DatosReglas gruposVacios edificiosVacios Map.empty

aplicarComando :: Constantes -> DatosReglas -> Estado Purepecha -> Sellado Comando
               -> Either Rechazo (Estado Purepecha, [Hecho])
aplicarComando c dr est sell = let gs = drGrupos dr in case sellCmd sell of
  FijarTasaTributo n
    | n < 1 || n > 5 -> Left (Rechazo "tasa fuera de rango (1..5)")
    | otherwise ->
        let p    = persistenteJuego (estadoPersistente est)
            t    = ppTasas p
            p'   = p { ppTasas = t { tasaTributo = n } }
            est' = est { estadoPersistente = (estadoPersistente est)
                          { persistenteJuego = p' } }
        in Right (est', [])
  FijarImpuestoInterno n
    | n < 1 || n > 5 -> Left (Rechazo "tasa fuera de rango (1..5)")
    | otherwise ->
        let p    = persistenteJuego (estadoPersistente est)
            t    = ppTasas p
            p'   = p { ppTasas = t { tasaImpuesto = n } }
            est' = est { estadoPersistente = (estadoPersistente est)
                          { persistenteJuego = p' } }
        in Right (est', [])
  AsignarPresupuesto parte n
    | n < 0 || n > 100 -> Left (Rechazo "presupuesto fuera de rango")
    | otherwise ->
        let p     = persistenteJuego (estadoPersistente est)
            pres  = ppPresupuesto p
            pres' = case parte of
              PEjercito       -> pres { pbEjercito = n }
              PAdministracion -> pres { pbAdministracion = n }
              PObras          -> pres { pbObras = n }
              PDiplomacia     -> pres { pbDiplomacia = n }
              PCulto          -> pres { pbCulto = n }
            p'    = p { ppPresupuesto = pres' }
            est'  = est { estadoPersistente = (estadoPersistente est)
                            { persistenteJuego = p' } }
        in Right (est', [])
  ReclutarEjercito _ -> Left (Rechazo "no_implementado")
  NombrarGobernador alt per -> do
    let p = persistenteJuego (estadoPersistente est)
    a  <- maybe (Left (Rechazo "el altépetl no existe")) Right (Map.lookup alt (ppAltepetl p))
    pe <- maybe (Left (Rechazo "el personaje no existe")) Right (Map.lookup per (ppPersonajes p))
    if not (perVivo pe) then Left (Rechazo (perNombre pe <> " está muerto"))
    else if altGobernador a == Just per then Left (Rechazo (perNombre pe <> " ya gobierna " <> altNombre a))
    else case [ otro | otro <- Map.elems (ppAltepetl p), altGobernador otro == Just per ] of
      (otro : _) -> Left (Rechazo (perNombre pe <> " ya gobierna " <> altNombre otro))
      []         -> Right (nombrar gs (sellTick sell) alt pe est)
  DestituirGobernador alt -> do
    let p = persistenteJuego (estadoPersistente est)
    a <- maybe (Left (Rechazo "el altépetl no existe")) Right (Map.lookup alt (ppAltepetl p))
    case altGobernador a of
      Nothing -> Left (Rechazo (altNombre a <> " no tiene gobernador"))
      Just _  -> Right (quitarNombramiento gs (sellTick sell) alt est)
  ConstruirEdificio e alt n -> iniciarObra c (drEdificios dr) e alt n est
  PedirTributoObra alt g f n -> pedirTributo c (drEdificios dr) alt g f n est

-- El motor no conoce estos tipos; aquí los traducimos a valores genéricos
-- de `Motor.Vista` para que el cliente pueda mostrarlos sin saber de reglas.
proyectar :: Estado Purepecha -> [EntidadJuego]
proyectar est =
  let p = persistenteJuego (estadoPersistente est)
  in  [ proyectarAlt est a | a <- Map.elems (ppAltepetl p) ]
   ++ [ proyectarPop pop | pop <- Map.elems (ppPops p) ]
   ++ [ proyectarFaccion est ]

-- | Lo que aporta una sola entidad: el mismo elemento que en 'proyectar'.
proyectarDe :: Estado Purepecha -> EntRef -> Maybe EntidadJuego
proyectarDe est r
  | r == entFaccion                   = Just (proyectarFaccion est)
  | entClase r == entClase altCualquiera = proyectarAlt est <$> Map.lookup (AltId (entId r)) (ppAltepetl p)
  | entClase r == entClase popCualquiera = proyectarPop <$> Map.lookup (PopId (entId r)) (ppPops p)
  | otherwise                         = Nothing
  where
    p = persistenteJuego (estadoPersistente est)
    altCualquiera = entRefAlt (AltId 0)
    popCualquiera = entRefPop (PopId 0)

-- | Las entidades cuyos campos pudieron cambiar de un estado a otro
-- ('juegoSucias'). Los altépetl y los pops que cambiaron se encuentran con
-- 'clavesCambiadas', que salta lo que los dos estados comparten. Un altépetl
-- también muestra lo que dice el derivado de él (sus fieles y sus celdas) y
-- el nombre de los que le envían tributo; los nombres no cambian, pero si
-- cambiaran, se marcan todos los que tienen obra. La facción muestra
-- magnitudes del almacén: siempre está sucia (es una).
sucias :: Estado Purepecha -> Estado Purepecha -> Maybe (Set.Set EntRef)
sucias e0 e1 = Just (Set.fromList (entFaccion : map entRefAlt alts ++ map entRefPop pops))
  where
    p0 = persistenteJuego (estadoPersistente e0)
    p1 = persistenteJuego (estadoPersistente e1)
    d0 = derivadoJuego (estadoDerivado e0)
    d1 = derivadoJuego (estadoDerivado e1)
    cambiados = clavesCambiadas (ppAltepetl p0) (ppAltepetl p1)
    nombre q a = altNombre <$> Map.lookup a (ppAltepetl q)
    conObra | any (\a -> nombre p0 a /= nombre p1 a) cambiados = [ altId a | a <- Map.elems (ppAltepetl p1), isJust (altObra a) ]
            | otherwise = []
    alts = cambiados ++ conObra
        ++ clavesCambiadas (dpCeldas d0) (dpCeldas d1)
        ++ map fst (clavesCambiadas (dpFielesLocal d0) (dpFielesLocal d1))
        ++ map fst (clavesCambiadas (dpFielesCentro d0) (dpFielesCentro d1))
    pops = clavesCambiadas (ppPops p0) (ppPops p1)

proyectarAlt :: Estado Purepecha -> Altepetl -> EntidadJuego
proyectarAlt est a =
  let p = persistenteJuego (estadoPersistente est)
      der = derivadoJuego (estadoDerivado est)
      -- Las claves de los fieles empiezan por el altépetl: los suyos son un
      -- tramo contiguo, que se toma en O(log n).
      deAlt = Map.takeWhileAntitone ((== altId a) . fst) . Map.dropWhileAntitone ((< altId a) . fst)
      fieles = foldl' (.+.) (Fijo 0) (Map.elems (deAlt (dpFielesLocal der)) ++ Map.elems (deAlt (dpFielesCentro der)))
      nombreAlt b = maybe "?" altNombre (Map.lookup b (ppAltepetl p))
      acopio o = VLista [ VTexto (g <> " " <> textoFijo q) | (g, q) <- Map.toList (obAcopio o) ]
  in  EntidadJuego (entRefAlt (altId a)) (Map.fromList
        [ ("nombre",   VTexto (altNombre a))
        , ("lealtad",  VFijo  (altLealtad a))
        , ("distancia",VFijo  (altDistancia a))
        , ("celda",    VEntero (altCelda a))
        , ("obra",     maybe VNulo (VTexto . obEdificio) (altObra a))
        , ("obra_avance", maybe VNulo (VEntero . obAvance) (altObra a))
        , ("obra_total",  maybe VNulo (VEntero . obTotal) (altObra a))
        , ("obra_cuadrilla", maybe VNulo (VEntero . obCuadrilla) (altObra a))
        , ("obra_trabajo",   maybe VNulo (VFijo . obTrabajo) (altObra a))
        , ("obra_acopio",    maybe VNulo acopio (altObra a))
        , ("obra_tributo",   maybe VNulo (\o -> VLista [ VTexto (g <> " de " <> nombreAlt (toFuente tr) <> " (" <> T.pack (show (toCuadrilla tr)) <> ")")
                                                   | (g, tr) <- Map.toList (obTributos o) ]) (altObra a))
        , ("obra_en_camino", maybe VNulo (\o -> VLista [ VTexto (enMaterial en <> " " <> textoFijo (enCantidad en) <> " de " <> nombreAlt (enDe en)
                                                              <> ", llega el día " <> T.pack (show (enLlega en))
                                                              <> ", transporte " <> textoFijo (enCosto en))
                                                   | en <- obEnCamino o ]) (altObra a))
        , ("fieles",         VFijo fieles)
        , ("edificios", VLista (map VTexto (altEdificios a)))
        , ("celdas_trabajadas", VEntero (length (Map.findWithDefault [] (altId a) (dpCeldas der))))
        ])

proyectarPop :: Pop -> EntidadJuego
proyectarPop pop = EntidadJuego (entRefPop (popId pop)) (Map.fromList
  [ ("altepetl",  VRef    (entRefAlt (popAltepetl pop)))
  , ("identidad", VTexto  (popIdentidad pop))
  , ("estrato",   VTexto  (popEstrato pop))
  , ("tamano",    VEntero (popTamano pop))
  , ("lealtad",   VFijo   (popLealtad pop))
  ])

proyectarFaccion :: Estado Purepecha -> EntidadJuego
proyectarFaccion est = EntidadJuego entFaccion (Map.fromList
  [ ("tesoro",      VFijo (baseFaccion magTesoro est))
  , ("prestigio",   VFijo (baseFaccion magPrestigio est))
  , ("legitimidad", VFijo (baseFaccion magLegitimidad est))
  ])

textoFijo :: Fijo -> Text
textoFijo f = case A.toJSON f of
  A.String t -> t
  otro       -> T.pack (show otro)

type JuegoPurepecha = Juego Purepecha Comando

-- | El derivado del juego (paso 16). El grafo compacto viene del entorno,
-- construido una vez por partida, y lo comparten la asignación de celdas y la
-- asistencia a los templos.
derivarPurepecha :: Constantes -> DatosReglas -> Grafo -> Purepecha -> DerivadoPurepecha
derivarPurepecha c dr gr p =
  let (celdas, mats) = derivarTerritorio c (drTerrenos dr) (grafoMapa gr) gr p
      (loc, cen) = derivarFieles c (drEdificios dr) gr p
  in DerivadoPurepecha celdas mats loc cen (derivarDistancias c gr p)

-- | El juego sin archivo de grupos: nombrar gobernadores no mueve poder.
juego :: Constantes -> Juego Purepecha Comando
juego c = juegoCon c gruposVacios

-- | El juego con sus grupos de poder (@datos/grupos.json@) y sin edificios.
juegoCon :: Constantes -> Grupos -> Juego Purepecha Comando
juegoCon c gs = juegoDatos c datosVacios { drGrupos = gs }

-- | El juego con sus datos de reglas. El estado inicial tiene que pasar por
-- 'conGrupos' con los mismos grupos.
--
-- La construcción corre antes que la producción, la hacienda y el agravio: un
-- edificio que se termina en una veintena ya cuenta en ella, y así ningún
-- sistema lee lo que escribe otro posterior.
juegoDatos :: Constantes -> DatosReglas -> Juego Purepecha Comando
juegoDatos c dr = let bienes = bienesDe (drTerrenos dr) in Juego
  { juegoSistemas    = [ construccion c (drEdificios dr), produccion c bienes
                       , hacienda c, evolucionAgravio c ]
  , juegoAplicarCmd  = aplicarComando c dr
  , juegoDerivar     = \g _ p -> derivarPurepecha c dr g (persistenteJuego p)
  , juegoProyectar   = proyectar
  , juegoProyectarDe = proyectarDe
  , juegoSucias      = sucias
  , juegoAgentes     = Map.empty
  , juegoCatalogoMag = Map.unions [ catalogoMag, catalogoGrupos (drGrupos dr), catalogoBienes bienes
                                  , catalogoConocimientos (drEdificios dr) ]
  }
