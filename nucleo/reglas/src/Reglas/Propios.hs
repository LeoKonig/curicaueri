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
-- * @absorber_faccion@ (@faccion@ y, si se quiere, @absorbente@): una
--   facción activa desaparece y transfiere lo suyo; con absorbente, todo
--   pasa a él. La facción del jugador no se absorbe con un efecto: su final
--   es una derrota del guion.
module Reglas.Propios
  ( condicionesPropias
  , efectosPropios
  ) where

import Data.Aeson (Value, withObject, (.:), (.:?))
import Data.Aeson.Types (Parser)
import qualified Data.Map.Strict as Map
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Estado
import Motor.Hechos
import Motor.Moneda (Economia)
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
