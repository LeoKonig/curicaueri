{-# LANGUAGE StrictData, TypeFamilies #-}
module Reglas.Juego where

import qualified Data.Map.Strict as Map

import Motor.Base
import Motor.Estado
import Motor.Hechos
import Motor.Juego
import Motor.Magnitudes
import Motor.Vista

import Reglas.Base
import Reglas.Comando
import Reglas.Constantes
import Reglas.Estado
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
  ]

aplicarComando :: Constantes -> Estado Purepecha -> Sellado Comando
               -> Either Rechazo (Estado Purepecha, [Hecho])
aplicarComando _ est sell = case sellCmd sell of
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

-- El motor no conoce estos tipos; aquí los traducimos a valores genéricos
-- de `Motor.Vista` para que el cliente pueda mostrarlos sin saber de reglas.
proyectar :: Estado Purepecha -> [EntidadJuego]
proyectar est =
  let p = persistenteJuego (estadoPersistente est)
  in  [EntidadJuego (entRefAlt (altId a)) (Map.fromList
        [ ("nombre",   VTexto (altNombre a))
        , ("lealtad",  VFijo  (altLealtad a))
        , ("distancia",VFijo  (altDistancia a))
        , ("celda",    VEntero (altCelda a))
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

type JuegoPurepecha = Juego Purepecha Comando

juego :: Constantes -> Juego Purepecha Comando
juego c = Juego
  { juegoSistemas    = [hacienda c, evolucionAgravio c]
  , juegoAplicarCmd  = aplicarComando c
  , juegoDerivar     = \_ _ _ -> ()
  , juegoProyectar   = proyectar
  , juegoAgentes     = Map.empty
  , juegoCatalogoMag = catalogoMag
  }
