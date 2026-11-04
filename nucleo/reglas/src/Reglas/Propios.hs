{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Las condiciones y los efectos propios que el juego añade al lenguaje del
-- guion (documento funcional, secciones 1, 11 y 14b; V5, *Aparición y
-- desaparición de facciones*). El motor los llama por nombre
-- ('Motor.Propios'); aquí se dice qué leen y qué hacen.
--
-- Condiciones:
--
-- * @soberano@ (@altepetl@, @faccion@): el altépetl es de esa facción.
-- * @faccion_activa@ (@faccion@): la facción está activa.
-- * @personaje_vivo@ (@personaje@): el personaje existe y vive.
--
-- Efectos (un rechazo deja la opción entera sin aplicar):
--
-- * @transferir_altepetl@ (@altepetl@, @faccion@): el altépetl, con sus pops,
--   pasa a una facción activa; queda sujeto a su cabecera y sin gobernador.
--   No transfiere la cabecera de una facción: para eso, @absorber_faccion@.
-- * @cambiar_condicion@ (@altepetl@, @condicion@: «sujeto» o «senorio»).
-- * @activar_faccion@ (@faccion@): una facción potencial aparece.
-- * @consumir_bien@ (@faccion@, @bien@, @cantidad@): resta esa cantidad de las
--   existencias del bien de la facción; se rechaza si no alcanzan. Es el
--   único consumo de bienes del juego por ahora.
-- * @gastar_valor@ (@faccion@, @valor@): resta del tesoro de la facción un
--   costo dado en unidades de valor, pasado a su cuenta (la moneda designada,
--   si la hay) al tipo del día con @enCuenta@; se rechaza si el tesoro no
--   alcanza.
-- * @absorber_faccion@ (@faccion@ y, si se quiere, @absorbente@): una
--   facción activa desaparece y transfiere lo suyo; con absorbente, todo
--   pasa a él. La facción del jugador no se absorbe con un efecto: su final
--   es una derrota del guion.
module Reglas.Propios
  ( condicionesPropias
  , efectosPropios
  ) where

import Data.Aeson (Value, withObject, (.:), (.:?))
import qualified Data.Aeson as A
import Data.Aeson.Types (Parser)
import qualified Data.Map.Strict as Map
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Estado
import Motor.Hechos
import Motor.Magnitudes
import Motor.Moneda (Economia (..), enCuenta, magExistencias)
import Motor.Propios
import Reglas.Base
import Reglas.Estado
import Reglas.Facciones (activarFaccionPor, eliminarFaccionPor, pasarAltepetl)
import Reglas.Grupos (Grupos)

juegoDe :: Persistente Purepecha -> Purepecha
juegoDe = persistenteJuego

campoFac :: Value -> Parser FaccionId
campoFac = withObject "argumentos" $ \o -> FaccionId <$> o .: "faccion"

condicionesPropias :: Map.Map Text (CondicionPropia Purepecha)
condicionesPropias = Map.fromList
  [ ("soberano", condicionPropia
      (withObject "soberano" $ \o -> (,) <$> (AltId <$> o .: "altepetl") <*> (FaccionId <$> o .: "faccion"))
      (\(a, f) p -> fmap altFaccion (Map.lookup a (ppAltepetl (juegoDe p))) == Just f))
  , ("faccion_activa", condicionPropia campoFac
      (\f p -> fmap facEstado (Map.lookup f (ppFacciones (juegoDe p))) == Just Activa))
  , ("personaje_vivo", condicionPropia
      (withObject "personaje_vivo" $ \o -> PerId <$> o .: "personaje")
      (\i p -> maybe False perVivo (Map.lookup i (ppPersonajes (juegoDe p)))))
  ]

efectosPropios :: Grupos -> Economia -> Map.Map Text (EfectoPropio Purepecha)
efectosPropios gs ec = Map.fromList
  [ ("transferir_altepetl", efectoPropio
      (withObject "transferir_altepetl" $ \o -> (,) <$> (AltId <$> o .: "altepetl") <*> (FaccionId <$> o .: "faccion"))
      transferir)
  , ("cambiar_condicion", efectoPropio
      (withObject "cambiar_condicion" $ \o -> (,) <$> (AltId <$> o .: "altepetl") <*> (o .: "condicion" >>= condicionDe))
      cambiarCondicion)
  , ("consumir_bien", efectoPropio
      (withObject "consumir_bien" $ \o -> (,,) <$> (FaccionId <$> o .: "faccion") <*> o .: "bien" <*> o .: "cantidad")
      consumir)
  , ("gastar_valor", efectoPropio
      (withObject "gastar_valor" $ \o -> (,) <$> (FaccionId <$> o .: "faccion") <*> o .: "valor")
      gastar)
  , ("activar_faccion", efectoPropio campoFac activar)
  , ("absorber_faccion", efectoPropio
      (withObject "absorber_faccion" $ \o -> (,) <$> (FaccionId <$> o .: "faccion") <*> (fmap FaccionId <$> o .:? "absorbente"))
      absorber)
  ]
  where
    p e = persistenteJuego (estadoPersistente e)
    activa e f = fmap facEstado (Map.lookup f (ppFacciones (p e))) == Just Activa
    nombreAlt (AltId i) = T.pack (show i)
    nombreFac (FaccionId i) = T.pack (show i)

    condicionDe :: Text -> Parser CondicionAlt
    condicionDe t = case t of
      "sujeto"  -> pure Sujeto
      "senorio" -> pure Senorio
      _         -> fail ("condición de altépetl desconocida (sujeto o senorio): " <> T.unpack t)

    transferir (a, f) e = case Map.lookup a (ppAltepetl (p e)) of
      Nothing -> Left ("no existe el altépetl " <> nombreAlt a)
      Just alt
        | not (activa e f) -> Left ("la facción " <> nombreFac f <> " no está activa")
        | altFaccion alt == f -> Left ("el altépetl " <> nombreAlt a <> " ya es de la facción " <> nombreFac f)
        | Cabecera _ <- altCondicion alt -> Left ("el altépetl " <> nombreAlt a <> " es la cabecera de su facción; para eso, absorber_faccion")
        | otherwise ->
            let t = estadoTick e
                cabecera = listToMaybe [ altId x | x <- Map.elems (ppAltepetl (p e)), altCondicion x == Cabecera f ]
                (e1, hs) = pasarAltepetl gs t f cabecera False (e, []) alt
                e2 = conJuego (\j -> j { ppAltepetl = Map.adjust (\x -> x { altSujetoA = cabecera }) a (ppAltepetl j) }) e1
                hecho = Hecho "altepetl_transferido" t [entRefAlt a, entFac f]
                          (Map.fromList [("de", nombreFac (altFaccion alt)), ("a", nombreFac f)])
            in Right (e2, hs ++ [hecho])

    cambiarCondicion (a, c) e = case Map.lookup a (ppAltepetl (p e)) of
      Nothing -> Left ("no existe el altépetl " <> nombreAlt a)
      Just alt
        | Cabecera _ <- altCondicion alt -> Left ("el altépetl " <> nombreAlt a <> " es la cabecera de su facción")
        | altCondicion alt == c -> Left ("el altépetl " <> nombreAlt a <> " ya tiene esa condición")
        | otherwise ->
            Right ( conJuego (\j -> j { ppAltepetl = Map.adjust (\x -> x { altCondicion = c }) a (ppAltepetl j) }) e
                  , [Hecho "condicion_cambiada" (estadoTick e) [entRefAlt a]
                       (Map.fromList [("condicion", case c of { Sujeto -> "sujeto"; Senorio -> "senorio"; Cabecera _ -> "cabecera" })])] )

    negarF :: Fijo -> Fijo
    negarF (Fijo x) = Fijo (negate x)

    mostrar :: Fijo -> Text
    mostrar x = case A.toJSON x of
      A.String t -> t
      otro       -> T.pack (show otro)

    consumir :: (FaccionId, Text, Fijo) -> Estado Purepecha -> Either Text (Estado Purepecha, [Hecho])
    consumir (f, b, q) e
      | q <= Fijo 0 = Left "consumir_bien: la cantidad tiene que ser positiva"
      | not (activa e f) = Left ("la facción " <> nombreFac f <> " no está activa")
      | not (Map.member b (ecoBienes ec)) = Left ("no existe el bien " <> b)
      | hay < q = Left ("no alcanzan las existencias de " <> b <> ": hay " <> mostrar hay <> " y se piden " <> mostrar q)
      | otherwise =
          Right ( conComun (\com -> com { comunMagnitudes = sumarBase (entFac f) (magExistencias b) (negarF q) (comunMagnitudes com) }) e
                , [Hecho "bien_consumido" (estadoTick e) [entFac f] (Map.fromList [("bien", b), ("cantidad", mostrar q)])] )
      where hay = maybe (Fijo 0) almacenBase
                    (Map.lookup (entFac f, magExistencias b) (comunMagnitudes (persistenteComun (estadoPersistente e))))

    gastar :: (FaccionId, Fijo) -> Estado Purepecha -> Either Text (Estado Purepecha, [Hecho])
    gastar (f, v) e
      | v <= Fijo 0 = Left "gastar_valor: el valor tiene que ser positivo"
      | not (activa e f) = Left ("la facción " <> nombreFac f <> " no está activa")
      | tesoro < costo = Left ("no alcanza el tesoro: cuesta " <> mostrar costo <> " y hay " <> mostrar tesoro)
      | otherwise =
          Right ( conComun (\com -> com { comunMagnitudes = sumarBase (entFac f) magTesoro (negarF costo) (comunMagnitudes com) }) e
                , [Hecho "valor_gastado" (estadoTick e) [entFac f] (Map.fromList [("costo", mostrar costo)])] )
      where tesoro = maybe (Fijo 0) almacenBase
                       (Map.lookup (entFac f, magTesoro) (comunMagnitudes (persistenteComun (estadoPersistente e))))
            costo = enCuenta ec (estadoTick e) e (entFac f) v

    conComun :: (Comun Purepecha -> Comun Purepecha) -> Estado Purepecha -> Estado Purepecha
    conComun g e = let per = estadoPersistente e in e { estadoPersistente = per { persistenteComun = g (persistenteComun per) } }

    activar f e = case Map.lookup f (ppFacciones (p e)) of
      Nothing -> Left ("no existe la facción " <> nombreFac f)
      Just fac
        | facEstado fac /= Potencial -> Left ("la facción " <> nombreFac f <> " no es potencial")
        | otherwise -> Right (activarFaccionPor "evento" (estadoTick e) fac e)

    absorber (f, absorbente) e = case Map.lookup f (ppFacciones (p e)) of
      Nothing -> Left ("no existe la facción " <> nombreFac f)
      Just fac
        | facEstado fac /= Activa -> Left ("la facción " <> nombreFac f <> " no está activa")
        | facJugable fac -> Left "la facción del jugador no se absorbe con un efecto: su final es una derrota del guion"
        | Just a <- absorbente, a == f || not (activa e a) -> Left ("el absorbente " <> nombreFac a <> " no es otra facción activa")
        | otherwise -> Right (eliminarFaccionPor gs ec "evento" absorbente (estadoTick e) f e)

    conJuego :: (Purepecha -> Purepecha) -> Estado Purepecha -> Estado Purepecha
    conJuego g e = let per = estadoPersistente e in e { estadoPersistente = per { persistenteJuego = g (persistenteJuego per) } }
