{-# LANGUAGE StrictData, OverloadedStrings #-}
-- | Subsistencia: la gente come antes de tributar (V5, *Comer antes de
-- tributar* y *La dieta*; documento funcional, sección 12, *Subsistencia y
-- cobertura* y *La dieta por grupos*; T25 y T27).
--
-- La producción reparte cada alimento al cosecharlo: la cuota de tributo en
-- especie va a las trojes de la facción y el resto se queda en el altépetl,
-- en lo cosechado de su grupo de la dieta, en toneladas de maíz equivalente.
-- Al cerrarse la ventana de cosecha del maíz, una vez por año, cada altépetl
-- cuenta su __cobertura__ con 'cierreDieta': de cada grupo cuenta, como
-- mucho, su tope de la necesidad,
--
-- > necesidad  = necesidad por persona · Σ N_p
-- > disponible = cosechado_g + reserva_g
-- > cobertura  = min(1, Σ_g min(disponible_g, tope_g · necesidad) / necesidad)
--
-- y lo que sobra de cada grupo queda en su reserva, hasta su tope de reserva.
-- La reserva se estropea cada periodo con la merma de su grupo (la del maíz de
-- la facción, con sus trojes, en la dieta por defecto). La cobertura vale
-- hasta la siguiente cosecha: el agravio ('Reglas.Sistemas.evolucionAgravio')
-- y la hacienda la leen cada veintena. Bajo 'cUmbralHambre' el cierre emite el
-- hecho @hambre@.
--
-- Este sistema escribe en el cierre la cobertura, la reserva y lo cubierto de
-- cada grupo; el efecto @repartir_bien@ ('Reglas.Propios') también los
-- escribe, y por eso están declarados con varios escritores. Antes del hito 6
-- nadie muere de hambre ni el hambre baja la producción. Sin ventana de
-- cosecha del maíz no hay subsistencia: la cobertura es 1. Sin
-- @datos/dieta.json@ todo es como en T25 ('dietaPorDefecto').
module Reglas.Subsistencia
  ( subsistencia
  , necesidades
  , necesidadDe
  , cierreAnio
  , coberturaEn
  , reservaEn
  , cubiertoEn
  , mostrarFijo
  , Abasto (..)
  , abEntregadoME
  , abastoCapital
  ) where

import qualified Data.Aeson as A
import Data.List (foldl')
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Motor.Base
import Motor.Estado
import Motor.Hechos
import Motor.Magnitudes
import Motor.Moneda (Economia (..), magExistencias, magMerma, mermaEn)
import Motor.Sistema
import Reglas.Base
import Reglas.Constantes
import Reglas.Dieta
import Reglas.Estado
import Reglas.Produccion (Cosechas (..), cierraVentana)

-- | Lo que necesita la gente de cada altépetl en un año, con @n@ la necesidad
-- por persona: por el tamaño de todos sus pops (también la nobleza y los
-- sacerdotes), en una sola pasada por los pops.
necesidades :: Fijo -> Purepecha -> Map AltId Fijo
necesidades n p = Map.map (\k -> fi k .*. n) $
  Map.fromListWith (+) [ (popAltepetl pop, popTamano pop) | pop <- Map.elems (ppPops p) ]

-- | La necesidad de un solo altépetl (recorre los pops: para un efecto, no
-- para un sistema que pasa por todos).
necesidadDe :: Fijo -> Purepecha -> AltId -> Fijo
necesidadDe n p a = fi (sum [ popTamano pop | pop <- Map.elems (ppPops p), popAltepetl pop == a ]) .*. n

-- | El cierre de T25, con un solo grupo sin tope: @(cobertura, reserva',
-- perdido)@ de la necesidad, lo cosechado y la reserva (ya con la merma).
cierreAnio :: Fijo -> Fijo -> Fijo -> (Fijo, Fijo, Fijo)
cierreAnio need cosechado reserva = case cierreDieta need [(uno, uno, cosechado .+. reserva)] of
  (cob, [(_, r', perdido)]) -> (cob, r', perdido)
  (cob, _)                  -> (cob, Fijo 0, Fijo 0)

baseAlt :: Estado Purepecha -> Magnitud -> AltId -> Maybe Fijo
baseAlt est m a = almacenBase <$> Map.lookup (entRefAlt a, m) (comunMagnitudes (persistenteComun (estadoPersistente est)))

-- | La cobertura efectiva del altépetl; 1 si nada la ha escrito (sin datos de
-- producción, o antes del primer cierre).
coberturaEn :: Estado Purepecha -> AltId -> Fijo
coberturaEn est a = maybe uno (valorEn (derivadoVigentes (estadoDerivado est)) (estadoTick est) rangoCobertura)
  (Map.lookup (entRefAlt a, magCobertura) (comunMagnitudes (persistenteComun (estadoPersistente est))))

-- | La reserva local de un grupo; 0 si nada la ha escrito.
reservaEn :: Estado Purepecha -> Text -> AltId -> Fijo
reservaEn est g a = maybe (Fijo 0) id (baseAlt est (magReservaDe g) a)

-- | Lo que el grupo cubrió en el último cierre. Si nada lo escribió (un
-- guardado de T25, o antes del primer cierre), se toma que el grupo del maíz
-- cubrió toda la cobertura y los demás nada.
cubiertoEn :: Dieta -> Fijo -> Estado Purepecha -> Text -> AltId -> Fijo
cubiertoEn d need est g a = case baseAlt est (magCubiertoDe g) a of
  Just x -> x
  Nothing | grupoDelMaiz d == Just g -> coberturaEn est a .*. need
          | otherwise                -> Fijo 0

mostrarFijo :: Fijo -> Text
mostrarFijo x = case A.toJSON x of
  A.String t -> t
  otro       -> T.pack (show otro)

-- | Lo que las trojes entregan a la capital al cerrarse la cosecha (V5, *La
-- dieta*, «El abasto de la capital»; T29).
data Abasto = Abasto
  { abPedido   :: Fijo                        -- ^ la parte ordenada del déficit, en t ME
  , abEntregas :: [(Text, Text, Fijo, Fijo)]  -- ^ grupo, alimento, toneladas que salen de las trojes y su t ME
  , abFaltaron :: Bool                        -- ^ algún alimento se acabó en las trojes y su grupo pedía más
  } deriving (Eq, Show)

-- | Lo entregado en total, en t ME.
abEntregadoME :: Abasto -> Fijo
abEntregadoME ab = foldl' (.+.) (Fijo 0) [ me | (_, _, _, me) <- abEntregas ab ]

-- | El abasto de un altépetl en el cierre del año. Solo abastece a la
-- cabecera de su facción, y solo si la facción tiene una orden mayor que 0.
-- Con @n@ la necesidad y @disponibles@ lo que tiene cada grupo (lo cosechado
-- y la reserva), como en 'cierreDieta':
--
-- > pedido = (1 − cobertura) · n · orden / 100
--
-- y las trojes lo cubren grupo por grupo, en el orden de la dieta, sin pasar
-- el tope de ninguno (tope_g · n − disponible_g), con los alimentos de cada
-- grupo en orden de nombre y a lo sumo lo que hay de cada uno. Así la capital
-- recibe maíz hasta el tope de los granos y frijol para lo demás, como
-- Tzintzuntzan, que importaba maíz y frijol. Lo entregado sale de las
-- existencias de la facción, en toneladas, y entra a lo disponible de su
-- grupo, en t ME: la masa se conserva. Sin orden o sin déficit, nada.
abastoCapital :: Dieta -> Faccion -> Altepetl -> Fijo -> [(GrupoDieta, Fijo)] -> (Text -> Fijo) -> Maybe Abasto
abastoCapital _ fa alt n disponibles existencias
  | facAbasto fa <= 0 || altCondicion alt /= Cabecera (facId fa) || n <= Fijo 0 = Nothing
  | pedido <= Fijo 0 = Nothing
  | otherwise = Just (Abasto pedido (reverse entregas) faltaron)
  where
    (cob0, _) = cierreDieta n [ (gdTope g, gdTopeReserva g, d) | (g, d) <- disponibles ]
    huecos = [ (g, max (Fijo 0) (gdTope g .*. n .-. d)) | (g, d) <- disponibles ]
    -- El déficit, sin pasar lo que cabe en los grupos (la cobertura viene
    -- redondeada; los huecos, no).
    deficit = min ((uno .-. cob0) .*. n) (foldl' (.+.) (Fijo 0) (map snd huecos))
    pedido = deficit .*. fi (facAbasto fa) ./. fi 100
    (_, entregas, faltaron) = foldl' grupo (pedido, [], False) huecos
    grupo (falta, acc, f) (g, cabe0) =
      let (falta', cabe', acc', agotado) = foldl' (alimento g) (falta, min falta cabe0, acc, False) (Map.toList (gdAlimentos g))
      in (falta', acc', f || (agotado && cabe' > Fijo 0))
    alimento g (falta, cabe, acc, f) (b, e)
      | cabe <= Fijo 0 || e <= Fijo 0 = (falta, cabe, acc, f)
      | otherwise =
          let hay = existencias b
              hayME = hay .*. e
              (t, me) | hayME <= cabe = (hay, hayME)
                      | otherwise     = let q = cabe ./. e in (q, q .*. e)
              -- Se acabó este alimento y el grupo seguía pidiendo.
              agotado = hayME < cabe
          in if t <= Fijo 0 then (falta, cabe, acc, f || agotado)
             else (falta .-. me, cabe .-. me, (gdId g, b, t, me) : acc, f || agotado)

-- | Los hechos del abasto: lo entregado de cada alimento y, si las trojes no
-- alcanzaron para lo pedido, @abasto_insuficiente@ (lo lee el guion).
hechosAbasto :: Tick -> Altepetl -> Abasto -> [Hecho]
hechosAbasto t alt ab =
  [ Hecho "abasto_capital" t ents (Map.fromList (resumen ++ [ (b, mostrarFijo q) | (_, b, q, _) <- abEntregas ab ]))
  | not (null (abEntregas ab)) ]
  ++ [ Hecho "abasto_insuficiente" t ents (Map.fromList resumen) | abFaltaron ab ]
  where ents = [entRefAlt (altId alt), entFac (altFaccion alt)]
        resumen = [("pedido", mostrarFijo (abPedido ab)), ("entregado", mostrarFijo (abEntregadoME ab))]

-- | El sistema de subsistencia (paso 7, cada periodo). Lee lo cosechado de
-- cada grupo (lo escribe la producción, que corre antes) y la merma del maíz;
-- escribe la reserva de cada grupo cada periodo y, en el periodo que cierra la
-- ventana de cosecha, la cobertura del año, lo cubierto por grupo y el hecho
-- @hambre@. Un cálculo por altépetl, grupo y periodo, y solo se escribe lo que
-- cambia. Un guardado de T25 cargado con una dieta de archivo lleva su maíz al
-- grupo del maíz en el primer periodo.
subsistencia :: Constantes -> Economia -> Dieta -> Cosechas -> Sistema Purepecha
subsistencia c ec dieta temporadas = Sistema
  { sisNombre   = NombreSistema "subsistencia"
  , sisCadencia = Periodo
  , sisLee      = Set.fromList (magMerma bienAlimento : alimentos ++ map (magCosechadoDe . gdId) grupos)
    -- Las existencias de los alimentos de la facción: las trojes que
    -- abastecen a la capital (T29). Tienen varios escritores declarados.
  , sisEscribe  = Set.fromList (magCobertura : magCosechado : magReserva : alimentos
                                ++ concat [ [magCosechadoDe g, magReservaDe g, magCubiertoDe g] | g <- map gdId grupos ])
  , sisEjecutar = \_ est -> case Map.lookup bienAlimento (csVentanas temporadas) of
      Nothing -> (est, [])
      Just co ->
        let p    = persistenteJuego (estadoPersistente est)
            com  = persistenteComun (estadoPersistente est)
            alm0 = comunMagnitudes com
            vig  = derivadoVigentes (estadoDerivado est)
            t    = estadoTick est
            cierra = cierraVentana (comunCalendario com) temporadas co t
            need = if cierra then necesidades (dtNecesidad dieta) p else Map.empty
            mermaMaiz f = maybe (Fijo 0) (mermaEn vig t alm0 (entFac f)) (Map.lookup bienAlimento (ecoBienes ec))
            mermaDe g f = maybe (mermaMaiz f) id (gdMerma g)
            base x m a = maybe (Fijo 0) almacenBase (Map.lookup (entRefAlt a, m) x)
            paso (alm00, hs) alt =
              case Map.lookup (altFaccion alt) (ppFacciones p) of
                Just fa | facEstado fa == Activa ->
                  let a = altId alt
                      alm = migrar a alm00
                      -- La reserva de cada grupo después de la merma del periodo.
                      reservas = [ (g, r0, r0 .*. (uno .-. mermaDe g (altFaccion alt)))
                                 | g <- grupos, let r0 = base alm (magReservaDe (gdId g)) a ]
                  in if not cierra
                       then ( foldl' (\x (g, r0, r1) -> if r1 /= r0 then fijarBase (entRefAlt a) (magReservaDe (gdId g)) r1 x else x)
                                     alm reservas
                            , hs )
                       else
                         let n = Map.findWithDefault (Fijo 0) a need
                             disponibles0 = [ (g, base alm (magCosechadoDe (gdId g)) a .+. r1) | (g, _, r1) <- reservas ]
                             -- El abasto de la capital (T29): las trojes cubren la parte
                             -- ordenada de su déficit antes de contar la cobertura.
                             fac = entFac (altFaccion alt)
                             abasto = abastoCapital dieta fa alt n disponibles0
                                        (\b -> maybe (Fijo 0) almacenBase (Map.lookup (fac, magExistencias b) alm))
                             (disponibles, almA, hsA) = case abasto of
                               Nothing -> (disponibles0, alm, [])
                               Just ab ->
                                 ( [ (g, d .+. foldl' (.+.) (Fijo 0) [ me | (gi, _, _, me) <- abEntregas ab, gi == gdId g ]) | (g, d) <- disponibles0 ]
                                 , foldl' (\x (_, b, q, _) -> sumarBase fac (magExistencias b) (negF q) x) alm (abEntregas ab)
                                 , hechosAbasto t alt ab )
                             (cob, porGrupo) = cierreDieta n [ (gdTope g, gdTopeReserva g, d) | (g, d) <- disponibles ]
                             escribir x ((g, _), (comido, r', _)) =
                               fijarBase (entRefAlt a) (magCosechadoDe (gdId g)) (Fijo 0)
                                 (fijarBase (entRefAlt a) (magReservaDe (gdId g)) r'
                                   (fijarBase (entRefAlt a) (magCubiertoDe (gdId g)) comido x))
                             alm1 = foldl' escribir (fijarBase (entRefAlt a) magCobertura cob almA) (zip disponibles porGrupo)
                             total = foldl' (.+.) (Fijo 0) (map snd disponibles)
                             detalle = [ ("disponible." <> gdId g, mostrarFijo d) | dtDeArchivo dieta, (g, d) <- disponibles ]
                             hecho = Hecho "hambre" t [entRefAlt a, entFac (altFaccion alt)]
                                       (Map.fromList ([ ("cobertura", mostrarFijo cob), ("necesidad", mostrarFijo n)
                                                      , ("disponible", mostrarFijo total) ] ++ detalle))
                         in (alm1, (if cob < cUmbralHambre c then (hecho :) else id) (reverse hsA ++ hs))
                _ -> (alm00, hs)
            (alm', hechos) = foldl' paso (alm0, []) (Map.elems (ppAltepetl p))
        in ( est { estadoPersistente = (estadoPersistente est) { persistenteComun = com { comunMagnitudes = alm' } } }
           , reverse hechos )
  }
  where
    grupos = dtGrupos dieta
    alimentos = [ magExistencias b | g <- grupos, b <- Map.keys (gdAlimentos g) ]
    -- Lo cosechado y la reserva de un guardado de T25 (sin sufijo de grupo)
    -- pasan al grupo del maíz cuando la dieta viene de un archivo. Se busca
    -- por altépetl: dos consultas, sin recorrer el almacén.
    migrar a alm = case grupoDelMaiz dieta of
      Just g | dtDeArchivo dieta, g /= "" ->
        let mover x (viejo, nuevo) = case Map.lookup (entRefAlt a, viejo) x of
              Just v  -> sumarBase (entRefAlt a) nuevo (almacenBase v) (Map.delete (entRefAlt a, viejo) x)
              Nothing -> x
        in foldl' mover alm [(magCosechado, magCosechadoDe g), (magReserva, magReservaDe g)]
      _ -> alm
