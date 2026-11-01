{-# LANGUAGE StrictData, TypeFamilies #-}
module Reglas.Juego where

import qualified Data.Aeson as A
import Data.List (foldl')
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
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
  , (magTesoro,
     DefMagnitud "tesoro" rangoTesoro "m.tesoro" Nothing False)
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

-- El motor no conoce estos tipos; aquí los traducimos a valores genéricos
-- de `Motor.Vista` para que el cliente pueda mostrarlos sin saber de reglas.
proyectar :: Estado Purepecha -> [EntidadJuego]
proyectar est =
  let p = persistenteJuego (estadoPersistente est)
      der = derivadoJuego (estadoDerivado est)
      celdas = dpCeldas der
      fieles a = foldl' (.+.) (Fijo 0) [ f | ((b, _), f) <- Map.toList (dpFielesLocal der) ++ Map.toList (dpFielesCentro der), b == a ]
      acopio o = VLista [ VTexto (g <> " " <> textoFijo q) | (g, q) <- Map.toList (obAcopio o) ]
  in  [EntidadJuego (entRefAlt (altId a)) (Map.fromList
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
        , ("fieles",         VFijo (fieles (altId a)))
        , ("edificios", VLista (map VTexto (altEdificios a)))
        , ("celdas_trabajadas", VEntero (length (Map.findWithDefault [] (altId a) celdas)))
        ])
      | a <- Map.elems (ppAltepetl p)]
   ++ [EntidadJuego (entRefPop (popId pop)) (Map.fromList
        [ ("altepetl",  VRef    (entRefAlt (popAltepetl pop)))
        , ("identidad", VTexto  (popIdentidad pop))
        , ("estrato",   VTexto  (popEstrato pop))
        , ("tamano",    VEntero (popTamano pop))
        , ("lealtad",   VFijo   (popLealtad pop))
        ])
      | pop <- Map.elems (ppPops p)]
   ++ [EntidadJuego entFaccion (Map.fromList
        [ ("tesoro",      VFijo (baseFaccion magTesoro est))
        , ("prestigio",   VFijo (baseFaccion magPrestigio est))
        , ("legitimidad", VFijo (baseFaccion magLegitimidad est))
        ])]

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
  in DerivadoPurepecha celdas mats loc cen

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
  , juegoAgentes     = Map.empty
  , juegoCatalogoMag = Map.unions [catalogoMag, catalogoGrupos (drGrupos dr), catalogoBienes bienes]
  }
