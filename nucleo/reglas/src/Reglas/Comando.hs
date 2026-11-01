{-# LANGUAGE StrictData, OverloadedStrings, LambdaCase #-}
-- | Comandos del juego y su forma en el protocolo. Los nombres JSON están
-- escritos a mano, como en Motor.Protocolo: son parte del contrato con Godot.
module Reglas.Comando
  ( Comando (..)
  , catalogoComandos
  , catalogoComandosCon
  , catalogoComandosConMateriales
  ) where

import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.:?), (.!=), (.=))
import qualified Data.Aeson.Types as A
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Autoridad (requisitoPorOmision)
import Motor.Protocolo (DeclComando (..), DeclParametro (..), TipoParametro (..))
import Reglas.Base (AltId (..), PerId (..))
import Reglas.Estado (PartePresupuesto (..))

data Comando
  = FijarTasaTributo Int
  | FijarImpuestoInterno Int
  | AsignarPresupuesto PartePresupuesto Int
  | ReclutarEjercito Int
  | NombrarGobernador AltId PerId   -- ^ el altépetl y el personaje
  | DestituirGobernador AltId
  | ConstruirEdificio Text AltId Int  -- ^ el edificio (id de @datos/edificios.json@), el altépetl y la cuadrilla (0 si no lleva)
  | PedirTributoObra AltId Text AltId Int  -- ^ la obra (su altépetl), el material, quien lo envía y cuántos trabajadores pone
  deriving (Eq, Show)

partes :: [(Text, PartePresupuesto)]
partes =
  [ ("ejercito", PEjercito), ("administracion", PAdministracion), ("obras", PObras)
  , ("diplomacia", PDiplomacia), ("culto", PCulto) ]

nombreParte :: PartePresupuesto -> Text
nombreParte p = maybe "" fst (lookup p [ (v, (k, v)) | (k, v) <- partes ])

instance FromJSON Comando where
  parseJSON = withObject "comando" $ \o -> do
    t <- o .: "tipo" :: A.Parser Text
    case t of
      "fijar_tasa_tributo"     -> FijarTasaTributo <$> o .: "valor"
      "fijar_impuesto_interno" -> FijarImpuestoInterno <$> o .: "valor"
      "asignar_presupuesto"    -> do
        p <- o .: "parte"
        case lookup p partes of
          Just parte -> AsignarPresupuesto parte <$> o .: "valor"
          Nothing    -> fail ("parte de presupuesto desconocida: " <> T.unpack p)
      "reclutar_ejercito"      -> ReclutarEjercito <$> o .: "tropas"
      "nombrar_gobernador"     -> NombrarGobernador <$> (AltId <$> o .: "altepetl") <*> (PerId <$> o .: "personaje")
      "destituir_gobernador"   -> DestituirGobernador . AltId <$> o .: "altepetl"
      "construir_edificio"     -> ConstruirEdificio <$> o .: "edificio" <*> (AltId <$> o .: "altepetl")
                                                    <*> o .:? "cuadrilla" .!= 0
      "pedir_tributo_obra"     -> PedirTributoObra <$> (AltId <$> o .: "altepetl") <*> o .: "material"
                                                   <*> (AltId <$> o .: "fuente") <*> o .: "cuadrilla"
      _                        -> fail ("comando desconocido: " <> T.unpack t)

instance ToJSON Comando where
  toJSON = \case
    FijarTasaTributo n     -> object ["tipo" .= ("fijar_tasa_tributo" :: Text), "valor" .= n]
    FijarImpuestoInterno n -> object ["tipo" .= ("fijar_impuesto_interno" :: Text), "valor" .= n]
    AsignarPresupuesto p n -> object ["tipo" .= ("asignar_presupuesto" :: Text), "parte" .= nombreParte p, "valor" .= n]
    ReclutarEjercito n     -> object ["tipo" .= ("reclutar_ejercito" :: Text), "tropas" .= n]
    NombrarGobernador (AltId a) (PerId p) ->
      object ["tipo" .= ("nombrar_gobernador" :: Text), "altepetl" .= a, "personaje" .= p]
    DestituirGobernador (AltId a) ->
      object ["tipo" .= ("destituir_gobernador" :: Text), "altepetl" .= a]
    ConstruirEdificio e (AltId a) n ->
      object ["tipo" .= ("construir_edificio" :: Text), "edificio" .= e, "altepetl" .= a, "cuadrilla" .= n]
    PedirTributoObra (AltId a) g (AltId f) n ->
      object ["tipo" .= ("pedir_tributo_obra" :: Text), "altepetl" .= a, "material" .= g, "fuente" .= f, "cuadrilla" .= n]

-- | El catálogo sin edificios cargados: @construir_edificio@ se declara con
-- una lista de opciones vacía.
catalogoComandos :: [DeclComando]
catalogoComandos = catalogoComandosCon []

-- | Lo que el cliente necesita para armar el formulario de cada comando.
-- Los rangos coinciden con la validación de 'Reglas.Juego.aplicarComando'.
-- Recibe los ids de los edificios y de los materiales de obra, que son datos.
catalogoComandosCon :: [Text] -> [DeclComando]
catalogoComandosCon edificios = catalogoComandosConMateriales edificios []

catalogoComandosConMateriales :: [Text] -> [Text] -> [DeclComando]
catalogoComandosConMateriales edificios materiales =
  [ DeclComando "fijar_tasa_tributo" "c.fijar_tasa_tributo" [DeclParametro "valor" (PEntero 1 5)] True requisitoPorOmision
  , DeclComando "fijar_impuesto_interno" "c.fijar_impuesto_interno" [DeclParametro "valor" (PEntero 1 5)] True requisitoPorOmision
  , DeclComando "asignar_presupuesto" "c.asignar_presupuesto"
      [DeclParametro "parte" (POpcion (map fst partes)), DeclParametro "valor" (PEntero 0 100)] True requisitoPorOmision
  , DeclComando "reclutar_ejercito" "c.reclutar_ejercito" [DeclParametro "tropas" (PEntero 0 100000)] False requisitoPorOmision
    -- Los ids no tienen un tipo de parámetro propio todavía: el rango solo
    -- acota el formulario, y un id que no existe vuelve como rechazo.
  , DeclComando "nombrar_gobernador" "c.nombrar_gobernador"
      [DeclParametro "altepetl" (PEntero 1 1000000), DeclParametro "personaje" (PEntero 1 1000000)] True requisitoPorOmision
  , DeclComando "destituir_gobernador" "c.destituir_gobernador"
      [DeclParametro "altepetl" (PEntero 1 1000000)] True requisitoPorOmision
  , DeclComando "construir_edificio" "c.construir_edificio"
      [ DeclParametro "edificio" (POpcion edificios), DeclParametro "altepetl" (PEntero 1 1000000)
      , DeclParametro "cuadrilla" (PEntero 0 100000) ] True requisitoPorOmision
  , DeclComando "pedir_tributo_obra" "c.pedir_tributo_obra"
      [ DeclParametro "altepetl" (PEntero 1 1000000), DeclParametro "material" (POpcion materiales)
      , DeclParametro "fuente" (PEntero 1 1000000), DeclParametro "cuadrilla" (PEntero 1 100000) ] True requisitoPorOmision
  ]
