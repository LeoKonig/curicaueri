{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | La tabla de terrenos como dato (@datos/terrenos.json@): capacidad base,
-- recursos y erosión base de cada terreno. El mapa solo dice qué terreno es
-- cada celda; lo que ese terreno rinde sale de aquí, de modo que cambiar de
-- terreno (la roturación del hito 3) cambia las tres cosas sin escribir
-- valores sueltos. Ver V5, *La tierra y la gente*.
module Motor.Terrenos
  ( DefTerreno (..)
  , cargarTerrenos
  , validarTerrenosDelMapa
  ) where

import Data.Aeson (Value)
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import Data.List (nub, sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.IntMap.Strict as IntMap

import Motor.Base
import Motor.Carga (CategoriaError (..), ErrorCarga (..), Validacion (..), falla)
import Motor.Mapa (Mapa (..), Celda (..), Recurso (..), Terreno (..))

data DefTerreno = DefTerreno
  { dtTerreno   :: Terreno
  , dtCapacidad :: Fijo         -- ^ personas que sostiene una celda de este terreno
  , dtRecursos  :: [Recurso]
  , dtErosion   :: Fijo         -- ^ degradación base por veintena (la usa la erosión, hito 6a)
  } deriving (Eq, Show)

-- | Carga @terrenos.json@ acumulando todos los errores: terrenos repetidos,
-- capacidad o erosión negativas y recursos repetidos dentro de un terreno.
cargarTerrenos :: Text -> Value -> Validacion (Map Terreno DefTerreno)
cargarTerrenos archivo v = case A.parseEither leer v of
  Left err -> falla (ErrorCarga ErrorEstructura archivo "" (T.pack err))
  Right ts ->
    let ids = [ i | (i, _, _, _) <- ts ]
        repetidos = traverse (\i -> if length (filter (== i) ids) > 1
                                      then falla (ErrorCarga ErrorEsquema archivo ("terrenos." <> i) "terreno repetido")
                                      else pure ()) (nub ids)
    in repetidos *> (Map.fromList . map (\t -> (dtTerreno t, t)) <$> traverse validar ts)
  where
    leer = A.withObject "terrenos" $ \o -> o A..: "terrenos" >>= mapM terreno
    terreno = A.withObject "terreno" $ \o ->
      (,,,) <$> o A..: "id" <*> o A..: "capacidad" <*> o A..:? "recursos" A..!= [] <*> o A..: "erosion"
    validar (i, cap, recs, ero) =
      let ruta = "terrenos." <> i
          capOk = if cap >= Fijo 0 then pure ()
                  else falla (ErrorCarga ErrorRango archivo (ruta <> ".capacidad") "la capacidad no puede ser negativa")
          eroOk = if ero >= Fijo 0 then pure ()
                  else falla (ErrorCarga ErrorRango archivo (ruta <> ".erosion") "la erosión no puede ser negativa")
          recsOk = if length (nub recs) == length recs then pure ()
                   else falla (ErrorCarga ErrorEsquema archivo (ruta <> ".recursos") "recurso repetido")
      in DefTerreno (Terreno i) cap (map Recurso recs) ero <$ capOk <* eroOk <* recsOk

-- | Todo terreno que el mapa usa tiene que estar en la tabla: se rechaza al
-- cargar, no en el tick 47. Un error por terreno, no por celda.
validarTerrenosDelMapa :: Text -> Map Terreno DefTerreno -> Mapa -> Validacion ()
validarTerrenosDelMapa archivo tabla m =
  () <$ traverse (\t@(Terreno n) ->
         if Map.member t tabla then pure ()
         else falla (ErrorCarga ErrorReferencia archivo ("terrenos." <> n)
                       ("el mapa usa el terreno «" <> n <> "» y la tabla no lo declara")))
       usados
  where
    usados = map Terreno (sort (nub [ n | c <- IntMap.elems (mapaCeldas m), let Terreno n = celdaTerreno c ]))
