{-# LANGUAGE StrictData #-}
module Reglas.Escenario where

import qualified Data.IntSet as IntSet
import Data.Text (Text)
import qualified Data.Map.Strict as Map
import qualified Data.Sequence as Seq

import Motor.Base
import Motor.Calendario (CalendarioVisible (..), Fecha (..), calendarioVeintenas)
import Motor.Mapa (DatosHex (..))
import Motor.Estado
import Motor.Magnitudes
import Reglas.Base
import Reglas.Estado

escenario1475 :: Purepecha
escenario1475 = Purepecha
  { ppAltepetl = Map.fromList
      [ (AltId 1, Altepetl (AltId 1) "Tzintzuntzan"
                    (Just (PerId 2)) (fi 0) Nothing (fi 80) 63)
      , (AltId 2, Altepetl (AltId 2) "Zacapu"
                    (Just (PerId 3)) (fi 2) (Just (AltId 1)) (fi 60) 33)
      , (AltId 3, Altepetl (AltId 3) "Uruapan"
                    (Just (PerId 4)) (fi 1) (Just (AltId 1)) (fi 75) 101)
      ]
  , ppPops = Map.fromList
      [ (PopId 1, Pop (PopId 1) (AltId 1) "purepecha" "nobleza" 3000  (fi 80))
      , (PopId 2, Pop (PopId 2) (AltId 1) "purepecha" "comun"   27000 (fi 70))
      , (PopId 3, Pop (PopId 3) (AltId 2) "purepecha" "comun"   8400  (fi 55))
      , (PopId 4, Pop (PopId 4) (AltId 2) "hnahnu"    "comun"   3600  (fi 45))
      , (PopId 5, Pop (PopId 5) (AltId 3) "purepecha" "comun"   15300 (fi 70))
      , (PopId 6, Pop (PopId 6) (AltId 3) "nahua"     "comun"   2700  (fi 50))
      ]
  , ppPersonajes = Map.fromList
      [ (PerId 1, Personaje (PerId 1) "Zuangua"          3 2 40 True)
      , (PerId 2, Personaje (PerId 2) "Tangáxoan"        4 3 28 True)
      , (PerId 3, Personaje (PerId 3) "Gobernador Inepto" 1 2 45 True)
      , (PerId 4, Personaje (PerId 4) "Gobernador Capaz"   3 2 38 True)
      ]
  , ppCazonci     = PerId 1          -- Zuangua, administración 3
  , ppTasas       = Tasas 3 3
  , ppPresupuesto = Presupuesto 30 25 30 15 0
  }

estadoInicial1475 :: Estado Purepecha
estadoInicial1475 =
  let p    = escenario1475
      mags = Map.fromList $
        [ ((entRefPop (PopId i), Magnitud "agravio"), AlmacenMag (fi ag) [])
        | (i, ag) <- [(1, 10), (2, 20), (3, 40), (4, 45), (5, 15), (6, 20)]
        ] ++
        [ ((entFaccion, magTesoro),      AlmacenMag (fi 1000) [])
        , ((entFaccion, magPrestigio),   AlmacenMag (fi 20) [])
        , ((entFaccion, magLegitimidad), AlmacenMag (fi 50) [])
        ]
      com  = Comun
        { comunMagnitudes = mags
        , comunDecisiones = Map.empty
        , comunPlanes     = Map.empty
        , comunCronica    = Seq.empty
        , comunCalendario = calendarioVeintenas 0
        , comunDirector   = directorInicial
        , comunMonedas    = Map.empty
        }
      per  = Persistente com p
  in Estado (Tick 0) per (Origen (Tick 0) per) (Derivado IntSet.empty ())

-- | Mapa provisional del escenario: una cuadrícula hexagonal de 14 × 10 con
-- terrenos pseudoaleatorios. Tzintzuntzan en la celda 63, Zacapu al noroeste
-- (33) y Uruapan al suroeste (101). El mapa real llega con el atlas.
datosMapa1475 :: DatosHex
datosMapa1475 = DatosHex 14 10 (fi 20) 1475

-- | Fecha juliana del tick 0.
inicio1475 :: Fecha
inicio1475 = Fecha 1475 1 1

-- | Calendario visible: juliano y, en la Nueva España, gregoriano desde
-- octubre de 1583, un año después que en Europa (V5, *Calendario visible*).
-- El último día juliano exacto está por verificar con fuente; el prototipo
-- termina en 1530, así que aún no se usa.
-- | Ejes de poder activos en el escenario (V5, *Cinco ejes de poder*): por
-- omisión, todos los de @datos/ejes.json@. En el prototipo ninguna fórmula los
-- lee, así que declararlos o no solo cambia lo que el cliente puede mostrar.
ejesActivos1475 :: Maybe [Text]
ejesActivos1475 = Nothing

visible1475 :: CalendarioVisible
visible1475 = CambioAGregoriano (Fecha 1583 10 4)

-- | El escenario sobre un mapa hexagonal de otro tamaño: las cabeceras se
-- colocan en la misma posición relativa que en el mapa de 14 × 10. Sirve
-- para la prueba de rendimiento del hito 2 (unos 2 700 hexágonos).
reubicar :: Int -> Int -> Estado Purepecha -> Estado Purepecha
reubicar ancho alto e =
  let mover a = let (f, c) = altCelda a `divMod` 14
                    c' = c * ancho `div` 14
                    f' = f * alto `div` 10
                in a { altCelda = f' * ancho + c' }
      p  = estadoPersistente e
      j  = persistenteJuego p
      j' = j { ppAltepetl = Map.map mover (ppAltepetl j) }
      p' = p { persistenteJuego = j' }
  in e { estadoPersistente = p', estadoOrigen = Origen (Tick 0) p' }
