# Curicaueri: Flor y Canto — arquitectura del prototipo en clave funcional y matemática

25 de octubre de 2026 (revisado el 27 de octubre) · Leonardo Gómez

Este documento acompaña a `arquitectura-prototipoV5.md`. V5 dice **qué** es el juego; este dice **cómo** se modela: el juego como sistema dinámico discreto, cada mecánica como función pura y cada regla del diseño como una ley comprobable. Cuando los dos documentos difieran en una cifra o una regla de diseño, manda V5; cuando difieran en un tipo, una firma o una ley, manda este.

**Notación.** `t` es un tick (un día); `S` el estado; `σ` la semilla de la partida; `⌊x⌋` la parte entera; `⌊x⌉ = ⌊x + ½⌋` el redondeo al entero más cercano, con medios hacia arriba; `clamp(x, a, b)` limita x al intervalo [a, b]. Las firmas se escriben en Haskell. Toda cantidad que afecta al estado es de tipo `Fijo` (punto fijo, ver sección 15).

## 1. Principio: núcleo funcional, cáscara imperativa

El núcleo es un conjunto de funciones puras. Toda la entrada y salida (el socket, el reloj real, los archivos, los agentes externos) vive en una cáscara delgada, en `Main`, que nunca decide nada del estado del juego.

| Capa | Qué contiene | Efectos |
| --- | --- | --- |
| Núcleo | Estado, sistemas, magnitudes, mapa, eventos, agentes internos, proyección, diferencias | Ninguno: funciones puras |
| Cáscara | Lectura del socket, sello de tiempo de los comandos, reloj real y velocidades, pausa, guardado en disco, llamadas a agentes externos | `IO` |

**Regla de la cáscara.** La cáscara solo influye en la partida a través de comandos sellados con su tick y su número de secuencia, que quedan en el registro. La pausa y la velocidad deciden *cuándo* se llama a la función de paso, nunca *qué* devuelve.

**El bucle de la cáscara.** Es lo único imperativo del núcleo, y no valida nada:

1. Leer los mensajes que llegaron por el socket.
2. Una `consulta` se responde al momento con `consultar` sobre el estado actual, sin tocarlo.
3. Un `comando` se sella con `(tick siguiente, facción, secuencia)`, se añade al registro y se encola. No se valida aquí: se valida al aplicarse, en el paso 1 (sección 10).
4. Si el reloj real indica que toca un tick (según la velocidad y la pausa), llamar a `paso` con los comandos sellados para ese tick.
5. Enviar a Godot los `cambios` y hechos del tick, y los rechazos a quien mandó cada comando rechazado.
6. Guardar en disco cuando lo pida el jugador o el autoguardado: el persistente y el registro de comandos.

**El motor y las reglas: un núcleo polimórfico en el juego.** El núcleo son dos paquetes, para que el motor pueda escribirse y probarse antes de que el hito 0 fije las reglas (ver *Dos vías en paralelo* en V5). El motor no conoce el tipo del estado del juego ni sus comandos; los recibe como un registro de funciones:

```haskell
-- paquete motor: s es el estado propio del juego y c su tipo de comando
type family DerivadoDe s     -- el derivado propio del juego
type family PlanDe s         -- el plan de su IA

data Juego s c = Juego
  { sistemas       :: [Sistema s]
  , aplicarCmd     :: Estado s -> Sellado c -> Either Rechazo (Estado s, [Hecho])
  , derivarJuego   :: Grafo -> Tick -> Persistente s -> DerivadoDe s   -- el grafo compacto trae el mapa
  , proyectarJuego :: Estado s -> [EntidadJuego]   -- clase, ref y campos propios
  , agentes        :: Map FaccionId (Agente s c)
  , efectosPropios :: Map NombreEfecto (EfectoJSON -> Either ErrorCarga (Efecto s))
  }

data Agente s c = Agente
  { planificar :: Proyeccion -> Rng -> PlanDe s              -- por veintena
  , ejecutar   :: PlanDe s -> Proyeccion -> Rng -> [c]       -- por tick; el motor sella
  }

-- lo inmutable de la partida: no cambia nunca y no se guarda con el estado
data Entorno = Entorno
  { mapa      :: Mapa
  , grafo     :: Grafo        -- el grafo compacto del mapa (Motor.Recorrido), construido una vez
  , catalogo  :: Catalogo     -- magnitudes con sus rangos, clases, condiciones compiladas
  , desfase   :: Int          -- del escenario (sección 2)
  }

paso :: Juego s c -> Entorno -> Semilla -> Tick -> [Sellado c] -> Estado s -> (Estado s, [Hecho])
```

- **Lo inmutable va en un `Entorno`, no en el estado.** El mapa, el catálogo y el desfase del calendario no cambian durante la partida, pero `paso` los necesita: `derivar` usa el mapa y `valorEfectivo` usa los rangos. Guardarlos dentro del estado los copiaría en cada guardado; dejarlos fuera de `paso` obliga a improvisar, como pasar un mapa vacío. El `Entorno` se reconstruye al cargar desde los datos y el escenario.
- **El derivado recibe el grafo compacto, no el mapa.** Construir el grafo compacto de 150 000 celdas cuesta medio segundo y solo depende del mapa, así que el `Entorno` lo construye una vez, de forma perezosa, y `derivarJuego` lo recibe hecho. El mapa sigue a mano: el grafo lo lleva dentro (`grafoMapa`). `cargar` recibe el mapa y construye su grafo una vez por carga.
- **El derivado del juego se calcula desde el persistente, no desde el estado.** Si `derivarJuego` recibiera `Estado s`, tendría a mano el derivado viejo y podría usarlo para calcularse a sí mismo sin que nada lo impida. Recibe `Persistente s` completo, y no solo `s`, porque necesita las magnitudes del motor: la fuerza de una fuente de influencia es un valor efectivo con modificadores.
- **Los agentes van en un mapa por facción.** Se recorren en orden de `FaccionId`, que no depende del orden de carga, y la clave ya identifica la facción, así que `Agente` no lleva un campo de facción que pudiera contradecirla. En el paso 0 el motor quita del mapa la facción del jugador antes de recorrerlo; como el jugador puede cambiar de facción después de 1530 (`ElegirFaccion`), eso se decide en cada tick y no al cargar.
- **El plan es del juego y lo guarda el motor.** `PlanDe s` es el tipo de plan de cada juego (`()` en el juguete). El motor lo guarda en `planes` dentro de `Comun` (sección 4), así que el agente sigue sin poder escribir en el estado: devuelve un plan y unos comandos, y el motor los guarda y los sella.

**La vista es genérica; el juego solo aporta sus campos.** El cliente ya es genérico: una magnitud nueva aparece en la interfaz sin código nuevo en Godot. Por eso `Vista` es un tipo del motor, igual para cualquier juego. Esto es lo que lee el cliente:

```haskell
type Clase = Text                          -- "asentamiento", "pop", "personaje", "aldea"…
data EntRef = EntRef { clase :: Clase, ident :: Int }

data ValorVista = VTexto Text | VClave ClaveLoc [ValorVista] | VEntero Int | VFijo Fijo
                | VBool Bool | VRef EntRef | VLista [ValorVista] | VNulo

data AporteVista = AporteVista
  { fuente :: ClaveLoc, argumentos :: [ValorVista]   -- el cliente localiza; el núcleo no
  , aporte :: Aporte, vence :: Maybe Tick }

data MagnitudVista = MagnitudVista
  { base :: Fijo, aportes :: [AporteVista], efectivo :: Fijo }

data EntidadJuego = EntidadJuego { ref :: EntRef, campos :: Map Text ValorVista }
data EntidadVista = EntidadVista
  { ref :: EntRef, campos :: Map Text ValorVista, magnitudes :: Map Magnitud MagnitudVista }

data Vista = Vista { tick :: Tick, entidades :: Map EntRef EntidadVista }

proyeccion :: Juego s c -> Estado s -> Vista
-- el motor toma las entidades del juego y les añade sus magnitudes, desde su almacén
```

- **Las magnitudes van dentro de cada entidad.** Así, cuando cambia una magnitud cambia su entidad, y la ley de completitud del espejo (sección 16) se enuncia sobre entidades. El juego no toca las magnitudes: las proyecta el motor, con base, desglose y valor efectivo.
- **El juego proyecta sus campos propios** (dueño, nombre, rango del asentamiento). Recibe `Estado s` completo porque varios campos visibles salen del derivado (dueño, capacidad).
- **`Clase` es texto,** porque el motor no conoce las clases del juego y una clase nueva debe ser un dato. Un error de escritura no lo detecta el compilador: lo detecta `cargarDatos`, que comprueba que cada clase proyectada está declarada en el catálogo.
- **Las fuentes del desglose son claves de localización con argumentos,** no texto ya traducido. V5 exige que los textos visibles usen claves, y el núcleo no sabe en qué idioma juega cada persona. El modificador conserva además su fuente estructurada (tipo e id), que es la que se compara para detectar "la fuente desapareció".
- **`cambios` y sus dos leyes** (sección 16) quedan en el motor y valen para cualquier juego, porque comparan vistas genéricas.

**Por qué la interfaz no debería moverse.** Los seis campos son los seis puntos donde un juego se engancha al motor:

- **Un comando nuevo** es un constructor más en el tipo `c` del juego y un caso más en `aplicarCmd`.
- **Un sistema nuevo** es un elemento más de la lista.
- **Un efecto nuevo** es una entrada más en el mapa.

Ninguna de las tres cosas cambia la forma de `Juego`. Si al escribir el juego de juguete o el 1b hace falta un campo nuevo, es la señal de que apareció un punto de enganche que no estaba previsto: se discute entonces, no se añade sin más. La prueba práctica es escribir `juguete` completo, añadirle un segundo comando y un tercer sistema, y comprobar que el registro no cambia.

- **El motor pone lo común.** `Estado s` lleva lo que cualquier juego necesita: el tick, el almacén de magnitudes y modificadores, las decisiones suspendidas, los planes de la IA, la crónica y el `s` del juego (sección 4). Las secciones 3 y 5 a 18 escriben `Estado`, `Persistente`, `Sistema` y `paso` sin parámetro y sin el argumento `Juego`, para leerse mejor. Son la versión monomórfica de las firmas de esta sección, con s igual al estado del juego purépecha; las firmas de esta sección son las que se implementan.
- **Las leyes se escriben una vez para cualquier juego.** `prop_repeticion :: Juego s c -> Property`, y así las demás. En el hito 1a se comprueban con el juego de juguete; en el 1b, con el juego real, sin reescribir ninguna.
- **El juego de juguete** vive en las pruebas del motor. Si el motor funciona con un juego que no es el nuestro, no depende de las reglas que el hito 0 todavía no fija. Tiene el tamaño mínimo, pero tiene que pasar por las rutas difíciles del motor: si no las ejercita, sus huecos los descubre el juego real en el peor momento.

```haskell
data Aldeas = Aldeas { poblacion :: IntMap Int }   -- grano y descontento son magnitudes del almacén
data ComandoJuguete = SubirImpuesto AldeaId Fijo | ResponderSequia DecisionId Int
type instance DerivadoDe Aldeas = IntMap FaccionId     -- dueño de cada aldea
type instance PlanDe     Aldeas = ()
juguete :: Juego Aldeas ComandoJuguete                 -- agentes = un agente nulo por facción de IA
```

| Ruta del motor | Cómo la ejercita el juguete |
| --- | --- |
| Sistemas de veintena, nemontemi y comandos | La cosecha corre cada veintena y respeta los nemontemi; `SubirImpuesto` sube el ingreso y el descontento, y un impuesto negativo se rechaza sin dañar el estado |
| Efecto suspendido | El evento "Sequía" pide al jugador cuánto grano repartir (`elegir_cantidad`), queda `Suspendido` y se reanuda con `ResponderSequia` |
| Guardar con una decisión pendiente, a mitad de veintena | Se guarda mientras la sequía espera respuesta, varios días después del último paso 16 y con comandos aplicados desde entonces; al cargar, el derivado se recalcula desde su origen y la respuesta reanuda el evento igual que sin guardar |
| Restos | Las aldeas crecen y migran entre sí con restos persistentes y reparto por mayor resto; la población total se conserva |
| Modificador que expira | La "fiesta" da −10 al descontento durante 3 veintenas; al expirar emite `modificador_terminado` y el valor vuelve a su base |
| Cambio de proyección | Cuando una aldea cambia de dueño, su entidad aparece en `cambios`; las dos leyes del espejo se comprueban sobre las vistas del juguete |

**Del hito 0 llegan especificaciones, no código.** Cada fórmula que sobrevive al prototipo de mesa llega con una tabla de casos (x_k, y_k) calculada con los flotantes de JavaScript. En el hito 1b, la fórmula en punto fijo debe cumplir:

```math
\big|\, f_{\text{Haskell}}(x_k) - y_k \,\big| \le \text{tol}\cdot\max\big(1,\ |y_k|\big) \qquad \text{para todo caso } k
```

Se compara fórmula por fórmula y no la partida entera. Dos implementaciones con distinto redondeo y distinto generador de azar divergen tras unos cientos de ticks aunque las dos sean correctas, así que reproducir el registro del prototipo en Haskell no es una prueba posible.

## 2. Dominios básicos

```haskell
{-# LANGUAGE StrictData, DuplicateRecordFields, OverloadedRecordDot, TypeFamilies #-}

newtype Tick     = Tick Int64            -- días desde el inicio del escenario
newtype Fijo     = Fijo Int64            -- punto fijo, escala 10 000
newtype Semilla  = Semilla Word64
newtype CeldaId  = CeldaId Int
newtype AsentId  = AsentId Int
newtype FaccionId = FaccionId Int
-- … un newtype por cada clase de id: nunca se confunde un id con otro
```

**Calendario interno: un dato del escenario.** El motor no sabe qué es una veintena. Cada escenario declara su calendario como una tupla (n, P, F, δ₀): P periodos de n días por año, F días fuera de periodo al final y el desfase δ₀ del tick 0. El año tiene N = nP + F días:

```math
\text{díaDelAño}(t) = (t + \delta_0) \bmod N
\qquad
\text{esInicioDePeriodo}(t) \iff \text{díaDelAño}(t) < nP \ \wedge\ \text{díaDelAño}(t) \bmod n = 0
```

El prototipo usa (20, 18, 5, δ₀): veintenas y nemontemi. Otra época puede usar meses (30, 12, 5) o semanas sin tocar el motor. El desfase δ₀ lo fija el escenario para que el día 0 caiga en la veintena correcta según la correlación elegida. **El calendario visible** (juliano, gregoriano, o el cambio entre los dos en una fecha) también es del escenario. En este documento, "veintena" y "esVeintena" se leen como "periodo" y "esInicioDePeriodo" con el calendario del prototipo. La **estación**, en cambio, se calcula con la fecha solar visible, porque el año interno se desfasa (sección 13).

## 3. El juego como sistema dinámico

```math
S_{t+1} = \text{paso}_\sigma\big(t,\ C_t,\ S_t\big)
```

donde C_t son los comandos sellados para el tick t. Una partida es un pliegue:

```haskell
-- versión monomórfica de la firma de la sección 1
paso    :: Semilla -> Tick -> [Comando] -> Estado -> (Estado, [Hecho])
partida :: Semilla -> Estado -> [[Comando]] -> [Estado]
partida σ s0 = scanl avanzar s0 . zip [t0 ..]
  where
    Tick t0 = tick s0
    avanzar s (t, cs) = fst (paso σ (Tick t) cs s)
```

- **Comando i en el tick t₀ + i.** La i-ésima lista de comandos se aplica en el tick `tick s0 + i`. El escenario no empieza necesariamente en el tick 0 (un guardado tampoco), así que el índice se cuenta desde el tick del estado inicial.
- `partida σ s0 []` devuelve `[s0]`: la traza incluye el origen.

**Relojes como pliegues anidados.** La jerarquía de relojes de V5 es una jerarquía de funciones:

| Reloj | Función | Relación |
| --- | --- | --- |
| Tick estratégico | `paso` | Un pliegue sobre los días |
| Veintena | Los sistemas con cadencia `Veintena` dentro de `paso` | Condicionados por `esVeintena` |
| Tick táctico | `pasoTactico :: Semilla -> TickTactico -> [OrdenTactica] -> Batalla -> Batalla` | Un pliegue completo *dentro* de un solo tick estratégico, que termina en un `BattleResult` |
| Fotograma | `interpolar :: Fijo -> Vista -> Vista -> Vista` en el cliente | Fuera del núcleo; solo para la capa táctica del juego completo |

## 4. El estado: persistente y derivado

```haskell
data Estado s = Estado
  { tick        :: Tick
  , persistente :: Persistente s   -- se guarda
  , origen      :: Origen s        -- de qué se calculó el derivado; se guarda
  , derivado    :: Derivado s      -- se recalcula; nunca se guarda
  }

data Persistente s = Persistente { comun :: Comun s, juego :: s }

-- del motor, idéntico para cualquier juego
data Comun s = Comun
  { magnitudes :: Almacen                              -- bases y modificadores, por (EntRef, Magnitud)
  , decisiones :: Map DecisionId DecisionPendiente     -- efectos suspendidos (sección 10)
  , planes     :: Map FaccionId (PlanDe s)             -- plan vigente de cada IA
  , cronica    :: Seq EntradaCronica
  }

data Derivado s = Derivado
  { vigentes :: IntSet          -- del motor: modificadores con condición cumplida en la última veintena
  , delJuego :: DerivadoDe s }  -- del juego

data Origen s = Origen { tickOrigen :: Tick, persistenteOrigen :: Persistente s }

-- el juego purépecha
data Purepecha = Purepecha
  { celdas, asentamientos, altepetl, pops, personajes, facciones, ejercitos :: …
  , tributos, obras, treguas, crisis :: …
  , restos :: Restos }                                 -- fracciones de crecimiento y migración
type instance DerivadoDe Purepecha = DerivadoPurepecha
data DerivadoPurepecha = DerivadoPurepecha
  { influencia :: Influencia, duenos :: IntMap FaccionId, asignacion :: IntMap AsentId
  , capacidad, presion, eficiencia :: IntMap Fijo, cargaAdmin :: Map FaccionId Fijo
  , casusBelli :: Set CasusBelli, rutas :: Rutas }
```

- **Lo común va en `Comun`.** Las magnitudes, las decisiones suspendidas, los planes y la crónica son iguales en cualquier juego, así que ningún juego los redefine.
- **Los restos van en el juego.** Son fracciones de lo que crezca o migre en cada juego. El motor da las funciones genéricas (crecer con resto, repartir por mayor resto), pero no sabe qué cantidades existen.
- **El derivado tiene dos partes, y las dos existen.** El motor también deriva algo: qué modificadores condicionales están vigentes. Su condición se evalúa en el paso 16 contra el derivado recién calculado del juego, y vale durante toda la veintena (sección 6). Por eso `derivar` calcula primero la parte del juego y luego la del motor.
- **Todo lo que perderse al guardar cambiaría la partida es persistente:** las decisiones pendientes, los planes de la IA, los restos y la crónica.

**Un problema que hay que resolver: guardar a mitad de una veintena.** El derivado se calcula en el paso 16 de un tick de veintena, y la partida se puede guardar cualquier día de la veintena. Si `cargar` recalculara el derivado desde el persistente del momento de guardar, usaría un estado que ya cambió (comandos, movimientos y combates de los días siguientes, el narrador de ese mismo tick). El derivado resultante sería distinto del que tenía la partida, y la partida cargada se separaría de la original: la ley de derivado reproducible fallaría.

La solución es guardar **de qué** se calculó el derivado. `origen` es el persistente tal como estaba al ejecutarse el paso 16, junto con su tick. En memoria casi no cuesta: las estructuras persistentes de Haskell comparten casi todo entre las dos versiones. En el guardado se escribe como diferencia respecto al persistente actual.

```haskell
-- El tick hace falta porque parte del derivado depende de la fecha: casus belli
-- y treguas con vencimiento, condiciones de modificadores con ventana, estación.
derivar :: Juego s c -> Grafo -> Tick -> Persistente s -> Derivado s
derivar j g t p = let dj = derivarJuego j g t p in Derivado (vigentesEn t p dj) dj

guardar :: Serialise s => Estado s -> ByteString      -- persistente y origen, en CBOR
cargar  :: Serialise s => Juego s c -> Mapa -> ByteString -> Either ErrorCarga (Estado s)
cargar j m b = do
  (t, p, Origen tf pf) <- decodificar b
  pure (Estado t p (Origen tf pf) (derivar j (grafoDe m) tf pf))
```

El derivado sigue sin guardarse: se guardan sus entradas, y por eso la ley se cumple exactamente. Al cambiar de versión, la migración de guardados (sección 18) migra el persistente y el origen con la misma cadena, y el derivado se recalcula con el código nuevo.

**Cuándo se recalcula el derivado.** Dos cosas distintas, que no deben confundirse:

1. **El estado derivado de veintena** (influencia, dueños, asignación de celdas, capacidad, presión, eficiencia, carga, casus belli, rutas, modificadores vigentes) se calcula en el paso 16 y se lee durante la veintena siguiente. Vive en `derivado`; al cargar se recalcula desde `origen`.
2. **El valor efectivo de una magnitud** se calcula al leerlo, a partir de su base y sus modificadores (sección 6). Puede memoizarse, pero la memoización se invalida al escribir; nunca es estado autoritativo.

## 5. El azar sin estado

```math
\text{rng}(\sigma, \text{sistema}, t) = \text{SplitMix64}\big(\text{mezcla}(\sigma, \text{hash}_{64}(\text{sistema}), t)\big)
```

- **Hash y generador implementados en el proyecto,** no tomados de bibliotecas cuyo resultado puede cambiar entre versiones de GHC o arquitecturas (como `hashable`). SplitMix64 y un hash de 64 bits fijo, con pruebas contra valores conocidos.
- **Una tirada** de probabilidad p es `u < p`, con `u` uniforme en [0, 1) en punto fijo.
- **Los agentes tienen su propio espacio:** `rng(σ, "plan:" ++ faccion, veintena)` y `rng(σ, "ejec:" ++ faccion, t)`.

## 6. Magnitudes y modificadores: un monoide conmutativo

Un modificador aporta a una magnitud un par (sumando, porcentaje). Los aportes forman un **monoide conmutativo**:

```haskell
data Aporte = Aporte { sumando :: Fijo, porcentaje :: Fijo }
instance Semigroup Aporte where Aporte a p <> Aporte a' p' = Aporte (a + a') (p + p')
instance Monoid    Aporte where mempty = Aporte 0 0
```

```math
\text{valor}(m, e, t) = \text{clamp}\Big( \big(b_{m,e} + \textstyle\sum_{i \in M(m,e,t)} a_i\big)\cdot\big(1 + \sum_{i \in M(m,e,t)} p_i\big),\ \min_m,\ \max_m \Big)
```

donde M(m, e, t) son los modificadores **activos** en el tick t sobre la magnitud m de la entidad e:

```math
i \in M(m,e,t) \iff \text{destino}(i) = (m,e)\ \wedge\ t_i^{\text{inicio}} \le t < t_i^{\text{fin}}\ \wedge\ \text{cond}_i(\text{derivado}) \text{ en la última veintena}
```

```haskell
valorEfectivo :: Magnitud -> Fijo -> [Modificador] -> Fijo
valorEfectivo m b mods = rango m (aplicar b (foldMap aporte mods))
  where aplicar b (Aporte a p) = (b + a) * (1 + p)

desglose :: Magnitud -> Fijo -> [Modificador] -> Desglose   -- la misma lista, con fuentes
```

- **La explicación es el cálculo, por construcción.** El desglose es la lista que se plegó; no existe otro camino para obtener el valor.
- **El orden no importa** (conmutatividad): el valor es el mismo para cualquier permutación de la lista.
- **El retorno a la base es automático.** Una magnitud cuyas fuentes son modificadores temporales (la legitimidad) vuelve a su base cuando estos expiran: es constante a trozos y no necesita una regla de decaimiento.
- **Quién escribe qué.** Los sistemas escriben la base o crean y terminan modificadores; nunca el valor efectivo.
- **Las condiciones usan el lenguaje del guion.** Un modificador puede llevar una `Condicion` (la misma de la sección 11b; no hay otro lenguaje). Se evalúa en el paso 16, al empezar la veintena, y el conjunto de ids de los modificadores condicionales cuya condición se cumple es `derivadoVigentes`. Un condicional cuenta en `valorEn` solo si su id está en ese conjunto (`cuentaEn`); uno sin condición cuenta siempre que esté en su ventana.
- **Qué leen las condiciones: el valor sin condicionales.** Al evaluar la condición de un modificador, las magnitudes que lee se calculan sin los modificadores condicionales (con un conjunto de vigentes vacío). Es deliberado: si una condición pudiera leer algo que otro condicional modifica, el resultado dependería del orden de evaluación o de un punto fijo, y `derivar` dejaría de ser una función pura de `(tick, persistente)`, que es lo que exige la ley del derivado reproducible (sección 4). Las condiciones de fases y situaciones, que se evalúan después del derivado, sí ven los vigentes.
- **Dejar de cumplirse no es terminar.** Cuando un modificador vigente deja de estarlo en el paso 16, emite `modificador_terminado` con la razón `condicion`, pero no se quita del almacén: si su condición vuelve a cumplirse, vuelve a contar. Un modificador que además venció ya emitió su hecho con la razón `expiro` y no se anuncia dos veces.

## 7. Sistemas y el tick

```haskell
data Cadencia = Diario | Periodo | Anual   -- Periodo: la veintena, en el prototipo

data Sistema s = Sistema
  { nombre   :: NombreSistema
  , cadencia :: Cadencia
  , lee      :: Set Magnitud
  , escribe  :: Set Magnitud
  , ejecutar :: Rng -> Estado s -> (Estado s, [Hecho])
  }

activo :: CalendarioInterno -> Cadencia -> Tick -> Bool
activo _ Diario  _ = True
activo c Periodo t = esInicioDePeriodo c t
activo c Anual   t = díaDelAño c t == 0
```

`Anual` sirve para lo que V5 define por año: la edad de los personajes sube en 1 y se tira su probabilidad anual de muerte, que crece con la edad y baja con la salud. Se ejecuta dentro del paso 12, porque el día 0 del año siempre es día de veintena.

**El tick es una composición** de los pasos en orden fijo. Los hechos se acumulan en una lista por diferencias, para evitar el costo cuadrático de concatenar:

```haskell
correr :: Semilla -> Tick -> [Sistema s] -> Estado s -> (Estado s, [Hecho])
correr σ t sistemas s0 = (s, acc [])
  where
    (s, acc) = foldl' uno (s0, id) sistemas
    uno (e, k) sis
      | activo (cadencia sis) t = let (e', hs) = ejecutar sis (rng σ (nombre sis) t) e
                                  in (e', k . (hs ++))
      | otherwise = (e, k)
```

Un paso reservado es un sistema cuyo `ejecutar` es `\_ e -> (e, [])`: implementar una mecánica es sustituir esa identidad.

**Validación estática del orden.** Con `lee` y `escribe`, el núcleo comprueba al cargar, sobre la lista ordenada de sistemas:

- **Error:** dos sistemas del mismo paso escriben la misma magnitud.
- **Aviso:** un sistema lee una magnitud que un sistema *posterior* del mismo tick escribe. Significa que lee el valor del tick anterior; es válido (el paso 8 lo hace a propósito), pero debe ser deliberado y quedar marcado.
- **Error en tiempo de ejecución, en modo de prueba:** un sistema modifica una magnitud que no declaró en `escribe`.

**El paso completo** compone los 19 pasos de V5, con los de veintena bajo una guarda:

```math
\text{paso}_\sigma(t, C) = s_{18} \circ s_{17} \circ \nu_t\big(s_{16} \circ s_{15} \circ \cdots \circ s_4\big) \circ s_3 \circ s_2 \circ s_1^{\,C \,\cup\, C^{\text{IA}}} \circ s_0
\qquad
\nu_t(f) = \begin{cases} f & \text{si esVeintena}(t) \\ \text{id} & \text{si no} \end{cases}
```

- s₀ produce los comandos de la IA, C^IA; s₁ aplica la cola con los del jugador y los de la IA.
- s₂ (movimiento) y s₃ (combate) son diarios, igual que s₁₇ (narrador) y s₁₈ (crónica y publicación).
- El derivado (s₁₆) solo se recalcula en veintena, y en nemontemi no corre ningún paso de veintena.
- Cuando el paso de veintena 11 se ejecuta, lo hace con su orden interno (epidemia, crecimiento, dispersión y migración).

## 8. El mapa como grafo

```haskell
data Mapa = Mapa
  { celdas  :: Vector CeldaId
  , vecinos :: CeldaId -> [(CeldaId, Conexion)]
  , escala  :: Fijo                                   -- km por celda
  }
data Conexion = Conexion { longitudKm :: Fijo, costo :: Fijo, atributos :: Set AtributoConexion }

type Proveedor = DatosMapa -> Either ErrorMapa Mapa  -- hexagonal, poligonal, exportado desde Godot
validarMapa   :: Mapa -> [ErrorMapa]
```

**Leyes del mapa** (las comprueba `validarMapa`): ids únicos; simetría (si b es vecino de a con conexión k, a es vecino de b con la misma k); sin celdas aisladas en la región jugable; escala presente.

**Dos métricas.** Con caminos mínimos en el grafo:

```math
d_{\text{km}}(a,b) = \min_{\text{camino } a \to b} \sum \text{longitudKm}
\qquad
d_{\text{costo}}(a,b) = \min_{\text{camino } a \to b} \sum \text{costo}
```

La longitud es fija; el costo, no (V5, *Costo del grafo*). Con μ(c) el valor efectivo de `celda.costo_movimiento` (base de la tabla de terrenos, modificadores de camino y otras obras) y ρ el factor de la conexión:

```math
\text{costo}(a,b) = \text{longitud}(a,b)\cdot\frac{\mu(a)+\mu(b)}{2}\cdot\rho(a,b),
\qquad
\rho(a,b) = \begin{cases}
\texttt{COSTO\_NAVEGACION} & a, b \text{ navegables} \\
\texttt{COSTO\_SIN\_PUERTO} & \text{una navegable, la otra de tierra sin puerto} \\
\texttt{COSTO\_CRUCE\_RIO} & \text{atributo } \texttt{Rio} \\
1 & \text{si no}
\end{cases}
```

El costo es simétrico por construcción: μ entra como promedio y ρ solo depende del par, así que la ley de simetría del mapa sigue valiendo. Todas las reglas usan d_costo; d_km queda para lo que es geometría.

**Implementado (hito 3).** μ por terreno (`costo_movimiento` en `datos/terrenos.json`, `conCostoDeTerreno` en `Motor.Terrenos`), aplicado al cargar el mapa. Todavía es estático: ninguna obra lo cambia, así que el grafo se construye una vez en el `Entorno`. El factor ρ del río y del agua navegable entra con los puertos (V5, *Las obras*, etapa 4): sin puertos, la regla del agua dejaría a los pescadores sin lago, y el mapa provisional no tiene ríos. El parche entra con el primer modificador de μ, que es el camino.

**Grafo parcheado.** El grafo compacto (`Motor.Recorrido`) guarda el costo de cada conexión. Cuando cambia μ(c) o ρ de una conexión, se reescriben solo las conexiones de las celdas afectadas:

```haskell
parchearCostos :: (CeldaId -> Fijo) -> (CeldaId -> CeldaId -> Fijo) -> [CeldaId] -> Grafo -> Grafo
-- ley: parchearCostos μ ρ cs (grafoCon μ0 ρ0 m) == grafoCon μ ρ m   si μ y ρ solo difieren de μ0, ρ0 en cs
```

Por fuera es una función pura, aunque por dentro copie un arreglo con `ST`. Con el mapa completo (unas 900 000 conexiones), parchear las de unas decenas de celdas es lo que mantiene el paso 16 barato.

**Asignación de celdas: un diagrama de Voronoi en el grafo.**

```math
\text{asig}(c) = \arg\min_{a \in \text{Asent}} \big(d_{\text{costo}}(c, \text{celda}(a)),\ \text{id}(a)\big)
\quad \text{con } d_{\text{costo}} \le R_{\text{prod}}
```

El orden lexicográfico (distancia, id) hace el desempate determinista. Se calcula con el mismo Dijkstra multifuente que la influencia (sección 9), con un grupo por asentamiento, una etiqueta por celda y R_prod (`RADIO_PRODUCCION`, en km de llano) como tope. Las tierras de un pueblo son las que alcanza a pie: una ladera detrás de una sierra puede quedar fuera aunque esté cerca en línea recta.

**Ids globales de celda (V5, *El mapa completo*).** La malla se traza en hojas con proyección de área igual; cada celda tiene coordenadas axiales (q, r) con origen fijo en su hoja h. El id las codifica en el `CeldaId` entero que ya existe, así que el tipo, el `IntMap` y el protocolo no cambian:

```math
\text{id}(h, q, r) = h \cdot 2^{42} + (q + 2^{20}) \cdot 2^{21} + (r + 2^{20}),
\qquad |q|, |r| < 2^{20}
```

Los vecinos se deducen de (q, r); solo las excepciones (ríos, pasos, costas, lagos navegables) se guardan. **Ley de ampliación:** para dos máscaras M ⊆ M', toda celda de M tiene en el mapa de M' el mismo id, los mismos atributos y las mismas conexiones con sus vecinos de M. El proveedor actual (`fila × ancho + columna`) no la cumple y se reemplaza antes de ampliar el mapa.

**Costo y escala.** Las celdas son datos casi fijos: el trabajo de cada tick es proporcional a las entidades que cambian, no a las celdas. Con 150 000 celdas y 150 000 pops de prueba (`--escala 7500x20`), el tick cuesta hoy unos 0,53 s, casi todo en proyectar y comparar la vista entera; lo que lo baja es pasar a `cambiosOpt` (en `Motor.Proyeccion`) el registro de entidades sucias del tick, en lugar de todas.

## 9. La influencia en el semianillo tropical

La influencia de una fuente s sobre una celda c decae con el costo de llegar:

```math
I(c) = \max_s F_s\, e^{-d_{\text{costo}}(s,c)/\lambda}
```

Tomando φ = −λ ln I, el máximo de productos se convierte en un mínimo de sumas:

```math
\varphi(c) = \min_s \big(\pi_s + d_{\text{costo}}(s,c)\big), \qquad \pi_s = -\lambda \ln F_s
```

Es un producto matriz-vector en el **semianillo tropical** (ℝ ∪ {∞}, min, +), y se calcula con un Dijkstra multifuente donde cada fuente arranca con potencial π_s. Todo lo que el juego necesita se resuelve dentro del dominio tropical:

| Necesidad | Forma tropical |
| --- | --- |
| Dueño de la celda | `argmin` de φ entre facciones |
| Zona disputada (la segunda influencia alcanza el 80 % de la primera) | φ₂(c) − φ₁(c) ≤ −λ ln 0,8, comparando las dos mejores facciones distintas |
| Influencia como número, para dibujar | e^(−φ/λ), calculada solo en el cliente |

- **El núcleo nunca calcula una exponencial para la influencia.** Solo necesita π_s = −λ ln F_s, una vez por fuente, de una tabla de logaritmos en punto fijo.
- **Suma saturada.** En el dominio tropical, ∞ se representa con un valor centinela (por ejemplo, `maxBound / 4`) y la suma satura en él. Así π_s + d_costo nunca desborda, aunque d_costo sea grande o la celda no tenga camino.
- **Dos mejores facciones por celda.** El Dijkstra mantiene hasta dos etiquetas por celda, de facciones distintas; el costo sigue siendo O((V + E) log V) por un factor constante.
- **La fuerza de cada fuente es una magnitud** (población, guarnición, ejército ocupante, modificadores), así que edificios, personajes y migración la mueven sin tocar el algoritmo.
- **Umbral: tierra de nadie.** Con influencia mínima I_min, una celda tiene dueño solo si φ(c) ≤ φ_max = −λ ln I_min. El recorrido no extiende etiquetas más allá de φ_max. Sin umbral (I_min = 0), toda celda alcanzable tiene dueño.
- **Empates.** Las etiquetas son ternas (φ, facción, fuente) en orden lexicográfico; sumar un costo no negativo conserva el orden, así que el Dijkstra es correcto con empates y con conexiones de costo 0. Por eso dentro de una misma distancia el orden de proceso no importa: una celda solo acepta una etiqueta que mejore lo que tiene.
- **Cola por cubetas.** Las claves que mete Dijkstra nunca bajan de la última que sacó, así que la cola es un montículo de radix: 65 cubetas según el bit más alto en que la clave difiere de la última. Meter es O(1) y cada entrada baja de cubeta a lo sumo 64 veces.
- **Reparación incremental.** Al cambiar unas fuentes, (1) se quitan sus etiquetas de todas las celdas; (2) a cada celda que perdió una se le vuelve a ofrecer todo lo que le llega: las etiquetas de sus vecinas y las fuentes que están en ella (una fuente que otra de su facción opacaba en todas partes no tiene etiqueta desde la cual reparar); (3) las fuentes nuevas o cambiadas arrancan con su potencial; y (4) se propaga solo lo que mejora alguna celda. Ley: el resultado es idéntico al cálculo desde cero.
- **Escalones de potencial (al conectar la influencia al juego, V5 *Rendimiento*).** Con paso δ ≥ 0, cada fuente arranca con π̂_s = δ·round(π_s/δ) (δ = 0, sin redondeo). La ley de reparación no cambia: solo las fuentes cuyo π̂ cambió cuentan como cambiadas.

**El control** es una función de consulta, no estado:

```math
\text{control}(c) = \begin{cases} \text{dueño del ejército enemigo que llegó primero a } c & \text{si lo hay (empates por id de facción y de ejército)} \\ \text{dueño}(c) & \text{si no} \end{cases}
```

## 10. Comandos, consultas y decisiones suspendidas

**La cola guarda comandos, no acciones.** La validación ocurre al aplicar, en el paso 1, contra el estado de ese momento:

```haskell
aplicarComando :: Estado -> ComandoSellado -> Either Rechazo (Estado, [Hecho])

aplicarCola :: [ComandoSellado] -> Estado -> (Estado, [Hecho], [Rechazo])
-- en orden (tick, facción, secuencia); un rechazo no detiene la cola ni cambia el estado
```

**La consulta es una predicción pura:** aplicar el comando a una copia del estado y medir la diferencia. Da el costo antes de confirmar sin efectos sobre la partida.

```haskell
consultar :: Estado -> Comando -> Either Rechazo Prediccion
```

**Efectos que piden algo al jugador.** Un efecto como `elegir_cantidad` no puede completarse sin una respuesta. El intérprete de efectos devuelve tres resultados posibles:

```haskell
data Resultado
  = Completado Contexto Estado [Hecho]
  | Suspendido Pregunta Reanudacion Estado [Hecho]
  | Fallo ErrorEfecto
```

**La reanudación es un dato, no una función.** Guardar una clausura en el estado rompería el guardado. Se *defuncionaliza*:

```haskell
data Reanudacion = Reanudacion
  { evento :: EventoId, opcion :: OpcionId, siguienteEfecto :: Int, contexto :: Contexto }
```

Se guarda en `decisiones`; el comando `ResponderCrisis` (o la respuesta a la decisión) escribe la respuesta en el contexto y el intérprete continúa desde `siguienteEfecto`. Como los efectos están compilados desde datos, reanudar es volver a interpretar el mismo evento desde ese índice.

## 11. Eventos: un lenguaje pequeño compilado a funciones

Las condiciones y los efectos en JSON son un árbol sintáctico. Al cargar se compilan a funciones y se comprueban sus tipos:

```haskell
compilarCondicion :: CondicionJSON -> Either ErrorCarga (Estado -> Bool)
compilarOpcion    :: [EfectoJSON]  -> Either ErrorCarga Programa
interpretar       :: Programa -> Int -> Contexto -> Estado -> Resultado
```

**El contexto de variables** es el estado de una mónada `State` que recorre los efectos en orden. Sus reglas, formalmente:

- **Escritura antes que lectura:** para cada efecto k que lee `$v`, existe un efecto j < k que escribe `v` en un ámbito visible. Si no, error de carga.
- **Tipos:** cada variable tiene tipo (cantidad, opción, entidad); el efecto que la lee declara el tipo que espera. Es una comprobación de tipos de un lenguaje sin bucles, decidible y barata.
- **Ámbitos:** `evento` ⊂ `crisis` ⊂ `faccion`, por duración.

**El narrador** es una función de selección pura:

```math
\text{elegibles}(t) = \{ e \mid t \in \text{ventana}(e) \wedge \text{cond}_e(S) \wedge \text{enfriado}(e, t) \}
```

```math
\text{enfriado}(e, t) \iff t - t_{\text{último evento}} \ge \texttt{DIAS\_ENTRE\_EVENTOS}\ (= 60)\ \wedge\ t - t_{\text{último}}(e) \ge \text{enfriamiento}(e)
```

Los eventos de la cadena histórica salen en su ventana sin esperar el espaciado. Entre los demás eventos elegibles se elige uno por peso, con el generador del narrador.

**Fórmulas con nombre** son un diccionario de funciones parametrizadas:

```haskell
type Formula = Params -> Estado -> Entidad -> Fijo
formulas :: Map NombreFormula Formula     -- "agravio_por_impuesto", "eficiencia_altepetl", …
```

## 11b. Actos modulares: fases, situaciones y director

El guion es un dato del entorno, junto al mapa: no cambia durante la partida y no se guarda con ella.

```haskell
data Entorno = Entorno { entMapa :: Mapa, entGuion :: Guion }
data Guion   = Guion { guTipos :: [Tipo], guFases :: [Fase], guSituaciones :: [Situacion], guDirector :: ParamsDirector }
data Fase    = Fase { faId :: Text, faDesde :: Maybe Tick, faCondicion :: Maybe Condicion
                    , faSistemas :: Maybe [NombreSistema], faIntensidades :: Map Fuente Fijo }
cargarGuion :: Text -> Fecha -> Value -> Validacion Guion     -- aplicativo: acumula todos los errores
```

**Condiciones.** Un lenguaje cerrado y sin efectos: `Siempre | Mayor r m x | Menor r m x | DesdeTick t | Todas cs | Alguna cs | No c`, evaluado sobre el estado visible: `evaluar :: Condicion -> Estado -> Bool`.

**Fases.** Sean f₀, …, fₙ las fases en orden y φ(t) el índice de la fase en curso. La transición es

```math
\varphi(t+1) = \max\big(\varphi(t),\ \max\{\, k \mid \text{desde}(f_k) \le t \ \vee\ \text{cond}_{f_k}(S_t) \,\}\big)
```

Por construcción φ es monótona: una fase nunca vuelve atrás. Al entrar en f_k se copian al estado persistente sus sistemas activos A_k y sus intensidades I_k. El paso de sistemas se restringe a A_k:

```math
\text{correr}_k = \text{correr}\ \big|_{\{\sigma \,\mid\, \text{nombre}(\sigma) \in A_k\}}
```

**Fuentes de presión.** Una fuente p es un sistema cuyo único efecto es añadir un modificador temporal de valor I_k(p) y duración d. Si la fase siguiente pone I(p) = 0 o saca p de A, el aporte de p a la magnitud en el día t es

```math
a_p(t) = \sum_{\text{mods de } p\ \text{con}\ t < \text{fin}} I_{k(\text{mod})}(p)
```

que no crece y llega a 0 a más tardar en t_cambio + d. La magnitud vuelve a su base sin discontinuidad introducida por el cambio de fase: las fases no escriben magnitudes, solo cambian qué corre.

**Situaciones.** s = (id, tipo, peso w_s, enfriamiento e_s, plazo π_s, fases F_s, condición c_s, opciones o₁…o_m), con tipo ∈ `guTipos` y m ≥ 1. Son elegibles el día t las que cumplen

```math
\text{eleg}(t) = \{\, s \mid (F_s = \varnothing \vee f_{\varphi(t)} \in F_s) \wedge c_s(S_t) \wedge t - \text{último}(s) \ge e_s \,\}
```

**Director.** Sea Δ = t − t_último los días desde la última situación, con D el espaciado. La probabilidad diaria de presentar una es

```math
P(t) = \begin{cases} 0 & \Delta < D \\ \min\big(p_{\max},\ p_0 + \tau\,(\Delta - D)\big) & \Delta \ge D \end{cases}
```

Si se presenta, se elige s ∈ eleg(t) con probabilidad proporcional a

```math
\tilde w_s = w_s \cdot \frac{1}{1 + \lambda\, n_s} \cdot \big(1 + \beta\, [\text{tipo}(s) \notin \text{década}(t)]\big)
```

donde n_s es el número de veces que el tipo de s salió en las últimas V situaciones, λ la penalización de variedad y β el bono de novedad. Los dos sorteos usan `rng σ "director" t`, de modo que el director es una función pura de (σ, t, S_t). La situación elegida suspende el programa de su primera pregunta (sección 10) con un identificador nuevo, tomado de un contador persistente que nunca se reutiliza. Al llegar t = t_presentación + π_s sin respuesta, se reanuda con o₁ y se emite `plazo_vencido`.

**Paso.** El director corre al final del tick, después de derivar:

```
fases → expirar → agentes → cola + respuestas → sistemas → moneda → derivar → director
```

```haskell
pasoCompleto :: Juego s c -> Entorno -> Semilla -> Tick -> [Sellado c] -> [Respuesta] -> Estado s
             -> (Estado s, [Hecho], [(Sellado c, Rechazo)], [(Respuesta, Rechazo)])
responderDecision :: Guion -> Int -> Text -> Estado s -> Either Text (Estado s, [Hecho])
```

**Métricas.** Sobre el historial H = [(t_i, tipo_i)] del director:

```math
\text{parte}_{\max} = \max_\theta \frac{|\{i \mid \text{tipo}_i = \theta\}|}{|H|}, \qquad
\text{nuevos}(d) = \big|\{\text{tipos de la década } d\} \setminus \textstyle\bigcup_{d' < d} \{\text{tipos de } d'\}\big|
```

El criterio del hito 0 es parte_max ≤ 0.25 y nuevos(d) ≥ 2 para cada década completa d ≥ 1. La medición (`metricas`) está separada del juicio (`cumpleVariedad` con los umbrales como parámetros), como en la sección 20.

Dos observaciones salieron de la prueba con el juego de juguete. Primera: la parte máxima es una cota de concentración, no de repetición. Un guion de muchos tipos sin fases da 0.10, pero nuevos(d) = 0 desde la segunda década. Segunda: si una fase f_k dura más de una década, para que nuevos(d) ≥ 2 se cumpla dentro de ella hace falta que la fase contenga situaciones con condición `DesdeTick` intermedia, es decir, escalada dentro del acto. Las métricas detectan un guion monótono pero no caracterizan uno bueno: optimizar el director solo para ellas sería medir lo equivocado.

## 12. Economía y población

**Trabajadores.** Para un asentamiento a, con pops productivos P(a):

```math
W_a = \max\Big(0,\ \sum_{p \in P(a)} \big\lfloor N_p \cdot \phi \big\rfloor - R_a\Big)
```

con φ = `FRACCION_TRABAJADORA` y R_a los trabajadores retirados por leva o trabajo obligatorio (`retirar_trabajadores`). El comando que recluta valida R_a contra los trabajadores disponibles. Aun así, el `max` hace falta: una epidemia puede bajar la población *después* de la leva, y los retirados siguen fuera.

**Producción: tierra y brazos, el factor escaso manda.** Cada celda c tiene un rendimiento y(c) cuando se trabaja completa y necesita ℓ(c) trabajadores para ello; las dos son magnitudes, así que el terreno, las terrazas, la erosión y la estación las mueven. Los trabajadores van primero a las mejores celdas: se ordenan las celdas asignadas K(a) por κ(c)·y(c)/ℓ(c) descendente, con empates por id, y se llenan en ese orden.

```math
Q_a = \Big(\sum_{k=1}^{|K(a)|} \kappa(c_k)\, y(c_k)\cdot \min\Big(1,\ \frac{\max\big(0,\ W_a - \sum_{j<k} \ell(c_j)\big)}{\ell(c_k)}\Big)\Big)\cdot\Big(1 + \textstyle\sum p_{\text{edificios, gobernador}}\Big)
```

donde κ(c) ∈ {1, κ_disp, κ_enem} es el factor de control de la celda.

- **Más tierra da más producción** si sobran brazos; **más brazos dan más producción** si sobra tierra.
- **Rendimientos decrecientes.** Cada trabajador nuevo va a una celda peor que la anterior, y pasado el último ℓ ya no añade nada. Eso es lo que hace atractiva la roturación cuando crece la población.
- **Sin celdas, sin producción.** Si K(a) está vacío, Q_a = 0 sin dividir entre nada.
- **Varios bienes por celda.** El rendimiento de una celda es un vector por bien (`rendimiento` en `datos/terrenos.json`), y cada bien recibe la misma fracción trabajada de la celda. Para ordenar las celdas, y(c) es la suma de sus rendimientos, sin pesos, mientras los bienes no tengan valor en el juego. Con esa y, Q_a es la suma de todos los bienes, y es lo que cumple la ley de monotonía. Un trabajador más no baja ningún bien. Una celda más puede bajar un bien, porque atrae trabajadores de otra celda, pero no baja el total.
- **Por qué no `min(W, Cap) · ȳ`.** La capacidad Cap mide cuánta gente sostiene la tierra, no cuántos trabajadores emplea. Mezclarlas acopla dos cosas que el diseño mueve por separado: una terraza sube el rendimiento, y la erosión baja la capacidad.

**Capacidad y presión:**

```math
\text{Cap}_a = \sum_{c \in K(a)} \text{valor}(\text{capacidad}, c)
\qquad
\pi_a = \begin{cases} \min\big(\pi_{\max},\ N_a / \text{Cap}_a\big) & \text{Cap}_a > 0 \\ \pi_{\max} & \text{Cap}_a = 0 \end{cases}
```

con π_max = `PRESION_MAXIMA`. Por encima de ese valor los efectos de la presión ya están saturados, así que acotarla no cambia el juego y garantiza π_a ∈ [0, π_max].

**Agravio y lealtad como ecuaciones en diferencias.** Por veintena, con los valores de la veintena anterior:

```math
A_{t+1} = \text{clamp}\big(A_t + \Delta A(S_t),\ 0,\ 100\big)
\qquad
L_{t+1} = L_t + \alpha\big(L^*(S_t) - L_t\big)
```

```math
L^* = 100 - A + g(\text{guarnición}) + (\text{Leg} - 50)\cdot \omega_{\text{leg}}
```

ΔA es la suma de aportes con fuente (impuestos, tributo, necesidades no cubiertas, campaña en temporada agrícola, ritual sobre pops no purépechas). La lealtad se relaja hacia su objetivo con tasa α: es un sistema estable, sin oscilaciones si 0 < α ≤ 1.

**Crecimiento con resto.** Para que el tamaño siga siendo entero sin perder las fracciones:

```math
x = N_t\, r_{\text{ef}} + \rho_t, \qquad N_{t+1} = \max\big(N_{\min},\ N_t + \lfloor x \rfloor\big), \qquad \rho_{t+1} = x - \lfloor x \rfloor
```

con r_ef = valor(tasa de crecimiento), cuyos modificadores incluyen la presión sobre la tierra y la epidemia, y ρ persistente en `restos`.

**Dispersión como relajación hacia un objetivo:**

```math
D_{t+1} = D_t + \big\lfloor \beta\,\big(\delta^*(S_t)\, N_t - D_t\big) \big\rceil
```

donde δ* es la proporción objetivo de población dispersa (función de la tierra disponible y la seguridad) y β = `RITMO_DISPERSION`. Mover gente entre núcleo y dispersión no cambia el total.

**Migración: una matriz de flujos que conserva la población.** Para cada par de asentamientos conectados, con atractivo A y peso w que decae con d_costo:

```math
f_{ij} = \kappa \cdot \max(0,\ A_j - A_i)\cdot w_{ij}\cdot N_i
```

Los flujos se calculan todos a la vez desde el estado anterior, **por origen y sin competencia entre orígenes**: cada origen decide su salida sin mirar a los demás, y un destino recibe la suma de lo que le llega. Para que la conservación sea exacta con enteros:

1. La salida total de cada origen es O_i = ⌊Σ_j f_ij + ρ_i⌋, con su resto ρ_i persistente.
2. O_i se reparte entre los destinos por el **método del mayor resto** (Hamilton): cada destino recibe la parte entera de su cuota y las unidades sobrantes van a los de mayor parte fraccionaria, con empates por id.

Así, lo que sale de cada origen es exactamente lo que entra en sus destinos en cada veintena, y la ley de conservación se cumple por construcción.

**Población e influencia.** La fuerza F de una fuente crece con su población, así que la migración desplaza las fronteras sin regla especial. Los frenos (presión, carga administrativa, exposición) son términos que entran en A y en la eficiencia.

**Eficiencia y carga administrativa** (fórmula `eficiencia_altepetl`, constantes en V5):

```math
\text{ef}_a = \text{clamp}\Big(E_0 \cdot \frac{h_a}{h_0}\cdot\big(1 - k_d \tfrac{d_a}{d_0}\big)\cdot\big(1 - k_i f^{\text{ajena}}_a\big)\cdot\big(1 - k_c \max(0, c_F - 1)\big),\ 0,\ 1\Big)
```

```math
c_F = \frac{\sum_{a \in F} w(d_a, f^{\text{ajena}}_a)}{\text{capacidadAdmin}(\text{presupuesto}_F, \text{gobernadores}_F)}
```

**Incursiones y saqueo.** Una incursión sobre un asentamiento resta primero de la población dispersa: con pérdida L, la parte dispersa pierde min(L, D) y el núcleo el resto. Estas pérdidas no escriben `pop.tamano` directamente: son ajustes pendientes que la demografía aplica en el paso 11, para mantener un solo escritor.

## 13. Indicadores, guerra y probabilidades

**Legitimidad.** Valor efectivo de una magnitud con base 50 y modificadores casi todos temporales (sección 6). Sus efectos:

```math
P_{\text{rebelión}} = p_0(L) \cdot \Big(1 + \frac{50 - \text{Leg}}{100}\Big),
\qquad p_0(L) = p_{\max}\cdot \max\Big(0,\ \frac{U - L}{U}\Big)
```

**Estación,** función de la fecha solar visible:

```math
\text{estación}(t) = \begin{cases} \text{Guerra} & \text{si } \text{díaSolar}(\text{fecha}(t)) \in [\,g,\ a) \text{ (con vuelta de año)} \\ \text{Agrícola} & \text{si no} \end{cases}
```

**Viruela.** Con n veintenas desde la llegada con Narváez, la probabilidad por revisión y la acumulada:

```math
p(n) = \min(0{,}75,\ 0{,}02\,n), \qquad p^{\text{alianza}}(n) = \min\big(0{,}95,\ 1{,}8\, p(n)\big),
\qquad P_N = 1 - \prod_{n=1}^{N}\big(1 - p(n)\big)
```

**Invasión mexica,** con r = ejército propio / ejército mexica, revisada solo en veintenas de temporada de guerra:

```math
P(r) = \begin{cases}
0{,}5\, e^{-k(r-1)} & r \ge 1 \\
0{,}5 + (P_{\max} - 0{,}5)\,\dfrac{1-r}{0{,}7} & 0{,}3 < r < 1 \\
0 \ \text{(exigencia de tributo)} & r \le 0{,}3
\end{cases}
```

Es continua en r = 1 y tiene un salto deliberado en r = 0,3. La exponencial se calcula en punto fijo con una serie truncada (sección 15).

**Frente abstracto del Valle de México:**

```math
\text{prog}_{k+1} = \text{clamp}\Big(\text{prog}_k + K_{\text{asedio}}\,\frac{S_k - D_k}{D_k},\ 0,\ 100\Big),
\qquad
\text{bajas}_k = \min\Big(\text{tropas}_k,\ \tau\,\frac{S_k}{D_k}\,\text{tropas}_k\, m_{\text{pos}}\Big)
```

**Combate automático.** Es la fórmula con nombre `resolver_combate`. Esta es la versión provisional para el hito 4, que se calibra después sin cambiar su forma. La fuerza efectiva de cada bando X es:

```math
E_X = \text{tropas}_X \cdot \text{calidad}_X \cdot \frac{\text{moral}_X}{100} \cdot \Big(1 + \textstyle\sum p_X\Big)
```

donde los porcentajes p_X incluyen terreno, general, estación y, para el defensor, fortificación. Con u el número uniforme del generador de combate y ε = `RUIDO_COMBATE` (por ejemplo, 0,1):

```math
q = \frac{E_A}{E_A + E_D},
\qquad
q' = \text{clamp}\big(q + \varepsilon\,(u - \tfrac12),\ 0,\ 1\big)
```

```math
\text{gana A} \iff q' > \tfrac12,
\qquad
\text{bajas}_A = \big\lfloor \tau\, \text{tropas}_A (1 - q')\, m_A \big\rfloor,
\qquad
\text{bajas}_D = \big\lfloor \tau\, \text{tropas}_D\, q'\, m_D \big\rfloor
```

con τ = `TASA_BAJAS` y m un multiplicador del perdedor por persecución. El empate exacto (q' = ½) lo gana el defensor. Si E_A + E_D = 0, no hay combate.

Cualquier versión de la fórmula debe cumplir dos leyes. Las dos se enuncian con el mismo u, porque el azar se acopla entre las dos partidas que se comparan:

- **Monotonía:** subir E_A con u fijo nunca hace que A pase de ganar a perder, ni sube las bajas de A, ni baja las de D.
- **Simetría:** intercambiar atacante y defensor (con sus modificadores) y usar 1 − u intercambia ganador y bajas, salvo en el empate exacto.

**Guerra ritual.** Es el mismo combate con τ menor, una fracción de las bajas del perdedor convertida en prisioneros y sin cambio de territorio. Es una restricción sobre el resultado, no otro sistema.

## 13b. Abasto, deserción y asedio

V5 (*La coerción como cadena*) modela el sostenimiento de un ejército como una reserva con un flujo. Vive en `reglas`; la interfaz `Juego` no cambia.

**Reserva y flujo.** Para un ejército e, la reserva A_e ∈ [0, 100] es la base de `ejercito.abasto`, escrita solo por el sistema de abasto, que corre cada día en el paso 2 después del movimiento. El flujo φ_e es el valor efectivo de `ejercito.flujo_abasto` (sección 6), con sus aportes con fuente. Los aportes que dependen de la ruta llevan la condición "ruta abierta":

```math
\text{ruta}(e) = \text{camino de menor } d_{\text{costo}} \text{ de la celda de } e \text{ al troje propio más cercano},
\qquad
\text{abierta}(e) \iff \forall c \in \text{ruta}(e).\ \text{control}(c) \ne \text{enemigo}
```

con control el de la sección 9. Como el control cambia de un día a otro, la condición se evalúa cada día al calcular el flujo, no en el paso 16.

**Un día de abasto.** Sea U = `UMBRAL_FORRAJEO` y f_e el forrajeo posible: positivo solo si A_e < U y el asentamiento al que pertenece la celda (sección 8) tiene población sobre su piso.

```math
A_{e,t+1} = \text{clamp}\Big(A_{e,t} + \varphi_e + \min\big(f_e,\ \max(0,\ U - A_{e,t} - \varphi_e)\big),\ 0,\ 100\Big)
```

El forrajeo nunca lleva la reserva por encima de U. Cuando hay forrajeo, el asentamiento recibe un modificador de agravio y uno negativo de producción, con fuente "forrajeo", y un ajuste pendiente de población por hambre si estaba en su piso. Los ajustes pasan por la demografía del paso 11 (un solo escritor de `pop.tamano`).

**Estado derivado.** El estado no se guarda:

```math
\text{estado}(e) = \begin{cases}
\text{disuelto} & \text{moral}_e = 0 \ \vee\ \text{tropas}_e < \texttt{TROPAS\_MINIMAS} \\
\text{hambre} & A_e = 0 \\
\text{forrajeo} & A_e < U \ \wedge\ f_e > 0 \\
\text{abastecido} & \text{en otro caso}
\end{cases}
```

En hambre, la moral baja `MORAL_POR_HAMBRE` por día y deserta la fracción `DESERCION_DIARIA` de las tropas.

**Desertores y disolución.** Los guerreros de un ejército vienen de pops concretos (leva con `retirar_trabajadores`, sección 12) y el ejército guarda cuántos vienen de cada asentamiento de origen. Al desertar o disolverse, k guerreros de un origen o:

- **Vuelven** si d_costo(celda de e, o) ≤ `DIAS_RETORNO`: el retiro R_o baja en k y su pop recibe un modificador temporal de lealtad "campaña fallida".
- **Se asientan** si no: el retiro baja en k, su pop de origen pierde k (ajuste pendiente) y el asentamiento más cercano a e gana k en un pop de su identidad (ajuste pendiente). Es la misma operación que `reubicar_pops`.

Las muertes en combate (sección 13) y por hambre reducen el pop de origen por el mismo canal de ajustes.

**Motín.** El paso 5 cuenta las veintenas seguidas sin paga de la partida de ejército, un campo del ejército. Al llegar a `VEINTENAS_PARA_MOTIN`: la moral baja, deserta una fracción (que vuelve a casa, como arriba), la capital recibe agravio y se emite `motin`.

**Asedio.** El sitiador sigue estas mismas reglas de abasto; si llega a disolverse, el asedio se levanta (`asedio_levantado`). Con las reservas de asedio de la plaza en 0 y sin rendición, la plaza recibe por veintena un ajuste de población por hambre y agravio. El relevo es una situación del guion con plazo. `HacerSalida` es un combate (sección 13) del sitiado contra el sitiador con un porcentaje negativo por dejar la fortificación; si gana, levanta el sitio.

**Bandas sin abasto.** Las facciones de tipo bandas nómadas no tienen trojes: sus ejércitos no usan este sistema, y su límite son las incursiones y la persecución. Es una diferencia de datos (el tipo de facción), no de motor.

## 14. Agentes

```haskell
proyectar :: Juego s c -> FaccionId -> Estado s -> Proyeccion   -- la vista que ve esa facción
-- Agente s c, de la sección 1:
--   planificar :: Proyeccion -> Rng -> PlanDe s
--   ejecutar   :: PlanDe s -> Proyeccion -> Rng -> [c]
agenteIA :: Personalidad -> Agente Purepecha Comando              -- las cuatro reglas
```

- **Un agente no puede mutar el estado porque su tipo no se lo permite.** Devuelve un plan y comandos; el motor guarda el plan en `planes` y sella los comandos.
- **La proyección es una `Vista` filtrada.** En el prototipo, `proyectar` devuelve todo; en el juego completo filtra lo que la facción no ve. La firma no cambia.
- **La personalidad es un dato** que se cierra dentro del agente al construirlo con `agenteIA`; las cuatro reglas son la función.
- **El jugador es un flujo externo** de comandos que la cáscara sella y encola. Para el motor, el jugador y la IA producen lo mismo: `[Comando]`.

**Agentes en otro proceso (juego completo).** Si el planificador vive en Mercury, `paso` no puede llamarlo directamente. Se modela como una corrutina pura: el paso devuelve una solicitud y se reanuda con la respuesta.

```haskell
data Avance
  = Listo Estado [Hecho]
  | Necesita [SolicitudAgente] ([RespuestaAgente] -> Avance)
```

La cáscara resuelve las solicitudes (en el mismo proceso, al instante; por socket, esperando) y reanuda. Dos garantías hacen que la repetición siga siendo exacta:

- **`Avance` es puro dadas las respuestas.** La continuación depende solo de las solicitudes y las respuestas, nunca del proceso que las produjo.
- **Las respuestas se registran** junto a los comandos. Con ellas, una partida se repite sin el proceso externo.

**Ley del agente externo:** una partida con el agente externo y la misma partida reanudada con sus respuestas registradas producen la misma traza.

**Implementación actual: la forma simple de la corrutina.** En el prototipo, la solicitud se conoce antes del tick: el agente solo decide al empezar cada periodo. Así que la cáscara pide el plan *antes* de llamar a `paso`, con la proyección del estado al final del tick anterior, y pasa los comandos del agente a `paso` como datos, por la misma cola que los del jugador. El motor sigue siendo puro sin necesitar `Avance`. `Avance` hará falta cuando un agente tenga que responder a algo que ocurre *dentro* del tick (por ejemplo, una decisión de crisis que pide respuesta a una facción de IA). El contrato (`agente_turno`, `agente_plan`), el tiempo límite, el registro y la reproducción están en `nucleo/app/Agente.hs` y `agentes/README.md`.

## 14b. Autoridad: soberanía, títulos y ejes (juego completo)

V5 (*Facciones, poder y autoridad*) separa la soberanía, que tiene un solo dueño por celda, de la autoridad, que varias facciones pueden tener sobre la misma entidad. Esta sección la formaliza. **Todo vive en el paquete `reglas`:** la interfaz `Juego` no cambia, porque `Sellado c` ya lleva la facción y `aplicarCmd` ya puede rechazar.

```haskell
-- El eje es un dato, no un enum: se declara en datos/ejes.json, como las clases (sección 1).
-- Cambiar el número de ejes (cuatro, cinco o seis) es cambiar datos, no tipos.
newtype Eje = Eje Text deriving (Eq, Ord, Show)

data DefEje = DefEje
  { ejeId      :: Eje
  , magnitud   :: Magnitud      -- faccion.autoridad.<id>; para la legitimidad, faccion.legitimidad
  , referencia :: Fijo }        -- el valor de capacidad que da eficacia 1 (100; 50 para la legitimidad)

data Clase    = Exclusivo | Concurrente
data Requiere = Todo | Requiere Eje Clase      -- del catálogo de comandos; Todo por defecto

-- Los ejes activos del escenario, en orden estable. Se calculan al cargar desde el catálogo
-- y el escenario (campo ejes_activos; por defecto, todos los declarados). Viven en el
-- Entorno, no en el estado, y no se guardan.
ejesActivos :: Entorno -> [DefEje]

data Titulo = Titulo
  { titular :: FaccionId, entidad :: EntRef, eje :: Eje
  , origen  :: OrigenTitulo                    -- cédula, nombramiento, tratado, fundación, encomienda
  , fuerzaExclusividad :: Bool                 -- por defecto False; True modela la encomienda
  , otorgante   :: Maybe FaccionId             -- por defecto Nothing; Just f: concesión de f (sección 14c)
  , condiciones :: [Condicion]                 -- por defecto []; el lenguaje cerrado de la sección 11b
  , desde   :: Tick, hasta :: Maybe Tick, fuente :: FuenteRef }

-- en el estado del juego: solo los títulos de quien no es soberano; vacío en el prototipo
-- data Purepecha = Purepecha { …, titulos :: Map (EntRef, Eje) [Titulo] }
```

`cargarDatos` comprueba que todo `Requiere` del catálogo de comandos nombre un eje declarado, igual que comprueba las clases proyectadas: un error de escritura en un eje falla al cargar, no en el tick 47.

**Soberano y titulares.** El soberano de una entidad sale del derivado: para una celda, su dueño; para un asentamiento o un altépetl, la facción a la que pertenece. Tiene título implícito en todos los ejes.

```math
\text{titulares}(e, j, t) = \{\text{soberano}(e)\} \cup \{\, \text{titular}(\tau) \mid \tau \in T(e,j),\ \text{desde}(\tau) \le t < \text{hasta}(\tau),\ \text{titular}(\tau) \text{ existe} \,\}
```

**Capacidad y autoridad.** Cada eje es una magnitud de la facción con base por tipo de facción y modificadores (sección 6), salvo la legitimidad, que es la magnitud `faccion.legitimidad` ya existente, con su base 50:

```haskell
capacidad :: Entorno -> Estado -> FaccionId -> Eje -> Fijo   -- valor efectivo de la magnitud del eje
autoridad :: Entorno -> Estado -> FaccionId -> EntRef -> Eje -> Maybe Fijo
autoridad en s f e j
  | f `elem` titulares s e j = Just (capacidad en s f j)
  | otherwise                = Nothing

titularExclusivo :: Entorno -> Estado -> EntRef -> Eje -> Maybe FaccionId
-- 1. Si hay títulos vigentes con fuerzaExclusividad sobre (e, j): el de mayor autoridad entre ellos.
-- 2. Si no, y hay soberano: el soberano, aunque otro titular tenga más autoridad.
-- 3. Si no: la facción de mayor autoridad. Empates siempre por el menor FaccionId.
```

```math
\text{titularExclusivo}(e, j) =
\begin{cases}
\arg\max_{f \in F^{!}(e,j)} \big(\text{autoridad}(f,e,j),\ -\text{id}(f)\big) & \text{si } F^{!}(e,j) \ne \varnothing \\
\text{soberano}(e) & \text{si no, y existe soberano} \\
\arg\max_{f \in \text{titulares}(e,j)} \big(\text{autoridad}(f,e,j),\ -\text{id}(f)\big) & \text{en otro caso}
\end{cases}
```

donde F^!(e, j) son los titulares de títulos vigentes con `fuerzaExclusividad` sobre (e, j).

**El soberano gana la exclusividad.** Su título implícito tiene prioridad sobre cualquier título explícito de otra facción, aunque esa facción tenga más capacidad en el eje. Solo la pierde de dos formas: perdiendo la soberanía de la entidad, o porque un título explícito declare `fuerzaExclusividad` sobre ese eje. Ese segundo caso modela la encomienda: la Corona cede a un encomendero la exclusividad de la Extracción sobre un pueblo, y el soberano la pierde aunque siga siendo su dueño. Es una decisión de datos por título, no una regla del motor.

`titularExclusivo` se calcula al consultarlo, como el control (sección 9): lee el dueño del derivado y valores efectivos que pueden cambiar a mitad de veintena, así que no se guarda.

**Autorizar un comando.** Es la primera línea de `aplicarCmd` en `reglas`:

```haskell
autorizar :: Entorno -> Estado -> FaccionId -> EntRef -> Requiere -> Either Rechazo Fijo   -- devuelve la eficacia
autorizar en s f e Todo
  | all (\d -> titularExclusivo en s e (ejeId d) == Just f) (ejesActivos en) = Right 1
  | otherwise = Left (NoEsTitular Nothing e)
autorizar en s f e (Requiere j Concurrente) =
  maybe (Left (SinTitulo j e)) (Right . eficacia en j) (autoridad en s f e j)
autorizar en s f e (Requiere j Exclusivo) = do
  a <- maybe (Left (SinTitulo j e)) Right (autoridad en s f e j)
  if titularExclusivo en s e j == Just f then Right (eficacia en j a) else Left (NoEsTitular (Just j) e)

eficacia :: Entorno -> Eje -> Fijo -> Fijo    -- capacidad / referencia del eje
```

**Por qué una referencia por eje.** La eficacia es `capacidad / referencia`, y la referencia es un dato de cada eje: 100 para los ejes nuevos y 50 para la legitimidad. Así un reino con legitimidad 50 actúa con eficacia 1, sin cambiar la base de la legitimidad. Subir esa base a 100 y bajar el valor inicial con un modificador de −50 que se retira con el primer culto o la primera victoria rompería el diseño de V5: la legitimidad tiene que volver sola a su base cuando dejan de alimentarla, y con base 100 un reino descuidado volvería a 100.

- **En el prototipo ningún comando requiere un eje concreto.** Todos usan `Todo`, así que ningún eje, tampoco Red, se lee en las fórmulas del prototipo. El escenario decide con `ejes_activos` cuáles existen y cuáles muestra el cliente; con los cinco o con ninguno, la ley de autoridad neutra se cumple igual, porque el soberano es titular exclusivo de todos.
- **Comandos sobre la propia facción.** Para los que no tienen otra entidad objetivo (presupuesto, tasas generales), el objetivo es la facción misma, que es su propio soberano.
- **Permiso y capacidad se separan.** `autorizar` decide si el comando se acepta con los títulos; la eficacia que devuelve entra en la fórmula del comando como argumento, y escala su costo o su efecto. `Todo` devuelve siempre 1, así que los comandos del prototipo no cambian aunque los ejes se muevan.
- **Los efectos concurrentes son aportes.** Lo que suman varios titulares concurrentes (dos extracciones, dos escuelas) se escribe como modificadores, que forman un monoide conmutativo (sección 6): el resultado no depende del orden de la cola.
- **Un rechazo por autoridad no filtra información.** Su texto solo nombra entidades presentes en la proyección del emisor (sección 14). Si el objetivo no es visible, el rechazo es el mismo que para una entidad inexistente.
- **Vencimiento.** La vigencia se comprueba al leer, así que un título vencido deja de contar de inmediato. Un sistema de veintena (en el paso 12, hoy reservado) emite `titulo_terminado` cuando un título vence o su titular desaparece, para la crónica y los eventos.
- **Proyección.** `proyectarJuego` publica los titulares de cada entidad como campo propio; en el juego completo, `proyectar` muestra a cada facción las entidades donde tiene título, además de las que ve por otras razones.

**Mezcla como flujo de nacimientos.** Parte del sistema de demografía (paso 11, entre crecimiento y dispersión), para conservar un solo escritor de `pop.tamano`. Para un asentamiento a, sea B_i los nacimientos de la veintena en los pops de identidad i (la parte positiva del crecimiento), s_j = N_j / N_a la proporción de la identidad j y μ_ij(a) el valor efectivo de la tasa de mezcla del par. Para cada regla (i, j) → k del catálogo:

```math
x_{ijk} = B_i\, \mu_{ij}(a)\, s_j + \rho_{ijk},
\qquad
m_{ijk} = \lfloor x_{ijk} \rfloor,
\qquad
\rho'_{ijk} = x_{ijk} - m_{ijk}
```

con el resto ρ persistente en `restos`. Si para una identidad i la suma de sus m_ijk supera sus nacimientos B_i, se recorta a B_i por el método del mayor resto, igual que en la migración (sección 12): cada m_ijk es la parte entera de su cuota B_i · x_ijk / Σ x_ijk, las unidades sobrantes van a las de mayor parte fraccionaria y los empates se rompen por (j, k) en orden estable. Los m_ijk pasan de los nacimientos del pop de identidad i al pop de identidad k del mismo asentamiento. Como los nacimientos se atribuyen al pop de la madre, la condición del hijo "según la madre" sale directamente de la condición del pop de origen; las demás reglas de condición son datos de la regla. μ_ij(a) es una magnitud del asentamiento por par (`asentamiento.tasa_mezcla.<i>.<j>`, declarada en el catálogo a partir de la lista de pares), con sus factores como modificadores porcentuales.

**Aparición y desaparición de facciones.** Cada facción declarada tiene un estado `Potencial | Activa | Eliminada`, que es persistente. En el paso 13, al empezar la veintena:

```haskell
data Transferencia = Transferencia { trTitulos :: Destino, trTesoro :: Destino, trPops :: Destino, trPersonajes :: Destino }
data Destino = AlHeredero FaccionId | AlSoberano | SePierde | AlAbsorbente FaccionId
-- potencial → activa  si  desde ≤ t  ∨  condAparicion(S)
-- activa → eliminada  si  hasta ≤ t  ∨  condDesaparicion(S)
```

Las condiciones son las de la sección 11b, más `Ocurrio hecho`: verdadera si el hecho aparece en la crónica. Para cada desaparición:

```math
\sum_{\text{destinos}} \text{lo transferido} \;=\; \text{lo que tenía la facción} \;-\; \text{lo declarado } \texttt{SePierde}
```

Todo lo demás llega a un destino. Un título cuyo destino no puede recibirlo, porque el destino no es soberano ni titular sobre esa entidad, se pierde y lo anota el hecho. Los ids de facción no se reutilizan.

**Condición del altépetl (V5, *Condición del altépetl*).** Entra con las rebeliones del hito 4:

```haskell
data Condicion = Sujeto | Senorio | Cabecera FaccionId    -- campo altCondicion
-- por defecto, para los guardados anteriores: Sujeto si altSujetoA = Just _, Cabecera 1 si no
-- independiente = Cabecera f con f de tipo senorio_independiente
```

Una rebelión triunfante activa una facción nueva desde la plantilla del tipo `senorio_independiente` (un id nuevo, nunca reutilizado), emite `faccion_aparece` y deja al altépetl como `Cabecera f`; el sometimiento la elimina con `AlAbsorbente` y deja al altépetl como `Senorio` o `Sujeto`. Sujeto y señorío difieren en quién gobierna (gobernador nombrado o señor propio), no en la bolsa: por eso ninguno de los dos es facción.

**Sin un tipo "entidad política".** La interfaz común a facción, señorío y asentamiento ya existe: son las magnitudes, pares (entidad, nombre). El tesoro de un señorío es `altepetl:2 / tesoro`, con el mismo código que el de la facción; los grupos son datos. No se introduce una clase de tipos `Polity` ni un registro con todos los campos opcionales.

## 14c. Vínculos, concesiones y propuestas (juego completo)

V5 (*Vínculos y concesiones*) modela la diplomacia como obligaciones entre facciones y permisos sobre entidades. Todo vive en `reglas` y en datos; la interfaz `Juego` no cambia.

```haskell
newtype TipoVinculo = TipoVinculo Text            -- dato: tregua, alianza, tributo, regalos, dinastica…

data Vinculo = Vinculo
  { vinculoId    :: VinculoId
  , tipo         :: TipoVinculo
  , partes       :: [FaccionId]                   -- el tipo dice qué rol tiene cada posición
  , obligaciones :: [Obligacion]                  -- qué debe hacer cada parte; datos
  , desde        :: Tick, hasta :: Maybe Tick
  , condiciones  :: [Condicion]
  , fuente       :: FuenteRef }

-- en el estado del juego, vacío en el prototipo salvo treguas y alianzas, que se leen como vínculos
-- data Purepecha = Purepecha { …, vinculos :: Map VinculoId Vinculo }
```

**Concesiones.** Una concesión es un `Titulo` con `otorgante = Just g`. Está vigente si se cumplen las cuatro cosas a la vez:

```math
\text{vigente}(\tau, t) \iff \text{desde}(\tau) \le t < \text{hasta}(\tau)\ \wedge\ \text{soberano}(\text{entidad}(\tau)) = \text{otorgante}(\tau)\ \wedge\ \textstyle\bigwedge_{c \in \text{cond}(\tau)} c(S)
```

donde las condiciones se evalúan en el paso 16 contra el derivado, como las de los modificadores (sección 6), y valen toda la veintena. La segunda conjunción se lee al consultar, así que una concesión deja de contar el mismo tick en que el otorgante pierde la soberanía. `titulares` (sección 14b) solo cuenta títulos vigentes. Un sistema de veintena emite `concesion_terminada` con la razón (vencida, soberanía perdida, condición, revocada).

**Validación al cargar y al otorgar.**

- Una concesión tiene `hasta` o al menos una condición; si no, se rechaza: una concesión sin fin sería una cesión de soberanía.
- Solo el soberano de la entidad puede ser otorgante.
- A lo sumo una concesión por (tipo, entidad, beneficiario) y `MAX_CONCESIONES_ENTIDAD` por entidad.

**Costo de romper.** Revocar una concesión y romper un vínculo usan la misma fórmula con nombre, `costo_ruptura :: TipoVinculo -> Int -> Costo`, en función del tipo y de las veintenas transcurridas. Al cargar se comprueba que es no decreciente en la duración y que, para duración 0, ya es mayor o igual que el costo de otorgar.

**Propuestas.** Un vínculo o una concesión entre facciones nace de una propuesta. La propuesta es una decisión pendiente con identificador nuevo y plazo, como las de la sección 10:

- Si el receptor es el jugador, el cliente la recibe como `decision`.
- Si es una IA, la ve en su proyección y responde en un tick posterior con el comando `ResponderPropuesta`. No hace falta `Avance` (sección 14): la respuesta llega por la cola como cualquier comando.
- Si vence el plazo, la propuesta se rechaza y se emite `plazo_vencido`.

**Visibilidad.** Una embajada abre una ventana de visibilidad sobre la facción visitada: `visibilidad :: Map (FaccionId, FaccionId) Tick` en el estado del juego, con el tick en que vence. `proyectar` la consulta. Lo propio siempre es visible: la visibilidad solo filtra a otras facciones.

## 14d. Grupos de poder y reformas (paso 12)

```haskell
newtype Grupo = Grupo Text deriving (Eq, Ord, Show)     -- dato, en datos/grupos.json

data DefGrupo = DefGrupo
  { grupoId :: Grupo, ejeGrupo :: Eje, peso :: Fijo }    -- cuánto del eje depende del grupo
-- magnitudes por facción: faccion.grupo.<id>.lealtad y faccion.grupo.<id>.poder, en [0, 100]

data Reforma = Reforma
  { reformaId   :: Text
  , requisitos  :: [Condicion]                            -- umbrales de ejes, educación…
  , costoInicial :: Costo
  , efectos     :: Programa                               -- efectos compilados (sección 11)
  , impulsa     :: Grupo, seOpone :: Grupo
  , bloqueo     :: (Fijo, Fijo) }                         -- poder mínimo y lealtad máxima del opositor
```

**Contribución de un grupo a su eje.** Es un modificador sobre la magnitud del eje, con el grupo como fuente:

```math
a_g = -\,\text{peso}_g \cdot \frac{100 - L_g}{100}
```

Con lealtad 100 no resta nada; con lealtad 0 resta todo su peso. Así la base del eje sigue siendo la del tipo de facción y el desglose nombra al grupo que lo baja.

**Tope de lealtad por legitimidad.** El rango de una magnitud es fijo (sección 15), así que el tope dinámico se aplica como un modificador que calcula el paso 16 con los valores de ese momento:

```math
a^{\text{tope}}_g = \min\big(0,\ (\text{Leg} + M) - L^{\text{sin tope}}_g\big)
```

donde L sin tope es el valor efectivo sin este modificador y M es `MARGEN_LEALTAD_GRUPO`. Durante la veintena la lealtad puede superar el tope hasta el siguiente paso 16, igual que cualquier condición de veintena.

**`AprobarReforma`.** En `aplicarCmd`:

1. Si la reforma ya se aprobó o no se cumplen sus requisitos, se rechaza sin cambiar el estado.
2. Si el grupo que se opone cumple la condición de bloqueo (poder ≥ mínimo y lealtad ≤ máxima), no se rechaza: se cobra el costo inicial y se abre una crisis suspendida con sus tres opciones (sección 10), con el hecho `reforma_bloqueada`. Los efectos de la reforma no se aplican hasta que la respuesta lo decida.
3. Si no, se cobra el costo, se aplican los efectos y se emite `reforma_aprobada`.

**Nombramientos.** Un personaje p tiene un grupo opcional g_p. Un cargo k (gobernador de un altépetl, capitán, consejero) declara sus pretendientes Π_k ⊆ grupos. Nombrar a p en k, en `aplicarCmd`:

```math
\text{mods}(p, k) = \big\{\, (\text{poder}_{g_p}, +\pi),\ (\text{lealtad}_{g_p}, +\lambda) \,\big\} \;\cup\; \big\{\, (\text{lealtad}_{g}, -\lambda') \mid g \in \Pi_k,\ g \ne g_p \,\big\}
```

con π = `PODER_POR_CARGO`, λ y λ' constantes y fuente `nombramiento:<p>:<k>`. Son modificadores sin fin. Destituir o reemplazar a p los cancela todos, con `modificador_terminado` y razón "su fuente desapareció". Como el aporte es constante mientras dura el cargo y cero después, mantener un cargo no acumula poder. Si g_p = ∅ no hay modificadores de grupo. Después de 1530, si p tiene facción f_p ≠ soberano, el nombramiento añade además el título (f_p, entidad de k, eje de k, fuente: el nombramiento), que termina con el cargo.

`costo_destitucion` (al destituir a un consejero) es una fórmula con nombre que crece con el poder del consejero; se prueba con su tabla de casos, no como ley.

## 14e. Difusión tecnológica (paso 15)

Para cada tecnología τ y facción f hay dos magnitudes, codificado C y tácito T, en [0, 100]; su base la escribe solo el sistema de difusión. La intensidad de cada canal c sale del estado que ya existe y crece con lo que sabe quien está al otro lado del contacto:

```math
I_c(f, \tau, t) = \sum_{g \ne f} w_c(f, g, t)\ \frac{\text{dominio}_g(\tau, t)}{100}
```

con w_c el peso del contacto por ese canal: concesiones de comercio y rutas; combates y ocupaciones de la última veintena; concesiones de doctrina; vínculos dinásticos; flujos de migración entre las dos facciones. Cada canal reparte su aporte entre codificado y tácito según datos de la tecnología (κ y 1 − κ). Cada veintena:

```math
C_{t+1} = \text{clamp}\Big(C_t + \textstyle\sum_c \kappa_c(\tau)\, r_c(\tau)\, I_c \cdot \big(1 + p^{\text{edu}} + p^{\text{res}}\big),\ 0,\ 100\Big)
```

```math
T_{t+1} = \text{clamp}\Big(T_t + \textstyle\sum_c (1 - \kappa_c(\tau))\, r_c(\tau)\, I_c \cdot \big(1 + p^{\text{res}}\big) - \delta\, m_f(t),\ 0,\ 100\Big)
```

- r_c(τ) es la tasa base del canal para esa tecnología (datos).
- p^edu es el porcentaje que aporta la educación de f y solo acelera lo codificado.
- p^res es la suma de los porcentajes de resistencia (negativos), con su fuente.
- m_f(t) es la mortalidad de la veintena (epidemia, guerra) y la emigración de la facción, y δ la tasa de pérdida del conocimiento tácito (`PERDIDA_TACITO`).

`dominio_tecnologia` es una fórmula con nombre de C y T, no decreciente en ambas (provisional: el mínimo). Los efectos de la tecnología se aplican como modificadores proporcionales al dominio. La invención propia es un evento con condiciones, no parte de esta ecuación.

**La tecnología como receta alternativa.** Un insumo i de una receta (sección 14h) tiene sustitutos s, cada uno con (bien, cantidad q_s, tecnología τ_s o ninguna, calidad κ_s ∈ [0, 1.5]). Para la facción f, la calidad efectiva del sustituto es

```math
\kappa^{\text{ef}}_s = \kappa_s \cdot \frac{\text{dominio}_f(\tau_s)}{100} \quad (\kappa^{\text{ef}}_s = \kappa_s \text{ si no requiere tecnología})
```

Se usa el insumo principal si hay existencias suficientes; si no, el sustituto disponible de mayor κ^ef > 0, con empate por id. El resultado de la actividad se multiplica por κ^ef. Como el dominio baja con el conocimiento tácito (mortalidad, emigración), la pérdida de expertos bloquea sustitutos sin código especial. El grafo receta → insumo → sustituto → tecnología no puede tener ciclos; `cargarDatos` lo comprueba.

## 14f. Religión: pluralismo, templos y sincretismo

V5 (*Religión: política religiosa, templos y sincretismo*) añade tres mecanismos. Ninguno cambia la interfaz `Juego`.

**Pluralismo.** Sea F la facción soberana de un asentamiento, P su política religiosa en [0, 100] y otra(p) verdadero si la tradición del pop p (la de su identidad) no es el culto de estado de F. La fracción de su población de otra tradición es

```math
\phi_F = \frac{\sum_{p \in F,\ \text{otra}(p)} N_p}{\sum_{p \in F} N_p}
```

y los dos aportes, con fuente "política religiosa", son

```math
a^{\text{agravio}}_p = \frac{P}{100}\, \texttt{AGRAVIO\_PLURALISMO}\ \ \text{si otra}(p),
\qquad
a^{\text{leg}}_F = \frac{P}{100}\, \phi_F\, \texttt{LEGITIMIDAD\_PLURALISMO}
```

calculados en el paso 16 como modificadores condicionales. Con φ = 0 la política no tiene efecto.

**Cambio de política.** `PromulgarPolitica` fija un objetivo P*. El sistema de religión (paso 15) lo sigue por relajación, como la lealtad (sección 12):

```math
P_{t+1} = P_t + \big\lfloor \alpha_P\,(P^* - P_t) \big\rceil, \qquad 0 < \alpha_P \le 1
```

con α_P = `RITMO_POLITICA_RELIGIOSA`. P es una magnitud cuya base escribe solo ese sistema; no sobrepasa su objetivo.

**Sincretismo.** El sistema de religión es el único escritor de `gradiente_catolicismo`. Con r_p el valor efectivo de `pop.tasa_sincretismo` (base 0; modificadores de doctrina, escuela, política religiosa, nobleza local, sacerdocio y eventos):

```math
g_{p,t+1} = \text{clamp}\big(g_{p,t} + r_p,\ 0,\ 1\big)
```

El efecto `desplazar_gradiente` deja de escribir g: aporta un modificador temporal a r_p. Como la base es 0 y los aportes positivos solo vienen de fuentes de contacto y de eventos, un pop sin ellos no cambia.

**Templos.** Un nivel de templo es un edificio con `reemplaza` y `mantenimiento`. El mantenimiento de todos los templos de la facción se suma a lo que exige la partida de culto (V5, *Legitimidad y culto*). Si la partida no lo cubre durante `VEINTENAS_SIN_MANTENIMIENTO` veintenas seguidas, el sistema de construcción (paso 10) reemplaza el templo por su nivel anterior y emite `templo_degradado`. La profanación es un efecto (`profanar_templo`) que disparan los hechos de saqueo o de cambio de control de un asentamiento con templo; quita niveles y aporta a la legitimidad un modificador temporal con fuente.

**Ritual con componentes.** Los componentes son datos de cada tradición (`Componente` es texto: `sacrificio`, `consumo`), con pesos de legitimidad λ_c, rechazo ρ_c y omisión ω_c:

```haskell
newtype Componente = Componente Text
data DestinoPrisioneros = Ritual (Set Componente) | Trabajo | Rescate | Integracion
-- Ritual cs exige cs ⊆ componentes de la tradición ∩ práctica vigente de la facción;
-- si no, se rechaza sin cambiar el estado
```

Con n prisioneros, R ⊆ K los componentes realizados de los K de la tradición del culto de estado, g_p el gradiente del pop p y τ(p) verdadero si p es de la tradición del culto de estado, `DarDestinoPrisioneros` aporta modificadores temporales:

```math
a^{\text{leg}} = \min\Big(\texttt{TOPE\_RITUAL},\ \frac{n}{100}\sum_{c \in R} \lambda_c\Big),
\qquad
a^{\text{rechazo}}_p = \frac{n}{100}\, g_p \sum_{c \in R} \rho_c,
\qquad
a^{\text{omisión}}_p = [\tau(p)]\ \frac{n}{100}\,(1 - g_p) \sum_{c \in K \setminus R} \omega_c
```

Un destino distinto del ritual es el caso R = ∅. El término existente para los pops de otra tradición se suma aparte. Los pesos de grupos de poder son datos por componente.

**Casus belli de justificación religiosa.** Cada culto declara los componentes que condena. Al realizar el ritual con R, toda facción g con contacto y cuyo culto de estado condena algún c ∈ R recibe o renueva el casus belli hasta t + `VEINTENAS_JUSTIFICACION_RELIGIOSA`.

**Crisis del sacrificio.** El rechazo agregado de la facción es

```math
\bar g_F = \frac{\sum_{p \in F} N_p\, g_p}{\sum_{p \in F} N_p}
```

En el paso 14, si cruza hacia arriba un umbral de la lista de datos que aún no se usó, se abre la crisis (decisión suspendida, sección 10) y el umbral se marca como usado en el estado persistente. La respuesta fija la práctica vigente, un conjunto de componentes guardado en la facción.

## 14g. Moneda designada e inflación

`Motor.Moneda`. Las unidades de valor son el numerario fijo: el tesoro y los costos se cuentan en ellas. La economía es un dato del entorno, como el mapa y el guion:

```haskell
data Entorno  = Entorno { entMapa :: Mapa, entGuion :: Guion, entEconomia :: Economia }
data Economia = Economia { ecoBienes :: Map Text Bien, ecoParams :: ParamsMoneda }
data Bien     = Bien { bnId :: Text, bnValor, bnCalidad, bnReferencia, bnElasticidad :: Fijo, bnDesignable :: Bool }
cargarEconomia :: Text -> Value -> Validacion Economia     -- aplicativo: acumula todos los errores
```

**Precio.** Para la entidad e y el bien g, con x_g y y_g los valores efectivos de las magnitudes `bien.<g>.existencias` y `bien.<g>.produccion` de e (las escribe el juego) y H el horizonte en periodos:

```math
D_g = \max\big(1,\ x_g^{+} + H\,y_g^{+}\big), \qquad
p_g = \max\Big(p_{\min},\ v_g \cdot q_g \cdot \big(R_g / D_g\big)^{\varepsilon_g}\Big)
```

con v_g el valor, q_g ∈ [0,1] la calidad monetaria, R_g > 0 la referencia y ε_g ∈ [0,1] la elasticidad. La potencia se calcula como exp(ε · ln(R/D)) con `lnFijo` y `expFijo`, deterministas. Propiedades: p_g no crece con x_g ni con y_g; con ε_g = 0, p_g = v_g q_g; p_g ≥ p_min > 0.

**Moneda y nivel de precios.** Si e designó la moneda m, el nivel de precios es P = 1 / p_m y algo que vale C cuesta C · P unidades de m (`costoEnMoneda`). El estado monetario es persistente:

```haskell
data EstadoMonetario = EstadoMonetario { emMoneda :: Text, emDesde :: Tick, emHistorial :: [(Tick, Fijo)] }
comunMonedas :: Map EntRef EstadoMonetario
designarMoneda :: Economia -> EntRef -> Maybe Text -> Tick -> Estado s -> Either Text (Estado s, [Hecho])
```

**Paso.** Al empezar cada periodo, para cada entidad con moneda, se anota (t, p_m) en el historial, acotado a n + 1 entradas, con n los periodos por año. Corre después de los sistemas, que mueven existencias y producción, y antes del derivado:

```
fases → expirar → agentes → cola + respuestas → sistemas → moneda → derivar → director
```

**Inflación anual.** Con h el historial (el más reciente primero):

```math
\pi = \frac{P(t)}{P(t - 1\ \text{año})} - 1 = \frac{p_m(h_n)}{p_m(h_0)} - 1
```

definida solo si |h| > n. El paso escribe `moneda.precio` = p_m, `moneda.nivel_precios` = P y `moneda.inflacion` = π como bases de magnitudes de e. Las escribe solo este módulo: son su único escritor.

**Magnitudes nominales.** El escenario declara qué magnitudes de la entidad se cuentan en su moneda (`pmNominales`; en la práctica, el tesoro). Al pasar de una cuenta con precio p_de a otra con precio p_a (el valor tiene precio 1), su base n se convierte a

```math
n' = n \cdot \frac{p_{\text{de}}}{p_a}
```

así que designar, cambiar y retirar la moneda conservan el valor real n · p, salvo el redondeo. Después, sin flujos, el valor real n · p_m(t) cae cuando p_m cae: la inflación erosiona lo guardado. Los flujos se calculan en valor y se pasan a la cuenta al tipo del día con `enCuenta c = c · P` (y `aValor n = n · p_m` en sentido contrario). Por eso la inflación no los toca.

**Designar.** `designarMoneda` rechaza un bien inexistente, uno no designable o la moneda vigente, y retirar sin moneda. Al aceptar, reinicia el historial (h = [], de modo que π no mezcla dos monedas), escribe p_m y P en el acto y emite `moneda_designada` o `moneda_retirada`. Lo llama el `aplicarCmd` de cada juego.

Dos diferencias con la propuesta que dio origen a esta sección. La conservación en el pago resta los bienes entregados y no además el tesoro. Y la inflación no puede "calcularse al leer" sin datos del pasado: se lee del historial persistente, que es lo mínimo necesario para que una partida cargada vea la misma inflación.

## 14h. Costo en valor e insumos

V5 (*El costo de las cosas*). El costo de una actividad gana insumos, con valor por defecto vacío:

```haskell
data Costo   = Costo { coValor :: Fijo, coVeintenas :: Int, coInsumos :: [Insumo] }   -- coInsumos = [] por defecto
data Insumo  = Insumo { inBien :: BienId, inCantidad :: Fijo, inSustitutos :: [Sustituto], inPenalizacion :: Fijo }
data Sustituto = Sustituto { suBien :: BienId, suCantidad :: Fijo, suTecnologia :: Maybe TecnologiaId, suCalidad :: Fijo }
```

Para cada insumo, con x las existencias del bien:

- si x ≥ cantidad, se consumen `cantidad` unidades;
- si no, se usa el mejor sustituto disponible (sección 14e);
- si no hay sustituto y x > 0, se consume x y el costo en valor sube en

```math
\Delta = \text{penalización} \cdot \frac{\text{cantidad} - x}{\text{cantidad}}
```

- si x = 0 y no hay sustituto, el comando se rechaza con el motivo, sin cambiar el estado.

Los insumos no se pueden pagar con valor ni con moneda, y la consulta muestra qué se consumiría.

Esta regla vale para los insumos que son bienes con existencias (juego completo). Los **materiales de una obra** no tienen existencias: se extraen o se reciben para esa obra y se acopian en ella (sección 14i). Por eso una obra sin material a mano no se rechaza al empezar: se detiene hasta que el material llegue, y la consulta dice cuánto tardará.

## 14i. Obras: cuadrilla, acopio, oficio y beneficio

V5 (*Las obras*). Todo vive en `reglas`; la interfaz `Juego` no cambia. El costo de un edificio crece con campos que tienen valor por defecto, de modo que el edificio del primer corte (solo valor y veintenas) es el caso con T = 0, sin materiales y sin oficio:

```haskell
data CostoObra = CostoObra
  { coValor      :: Fijo                  -- tesoro, al empezar
  , coVeintenas  :: Int                   -- duración mínima, D
  , coTrabajo    :: Fijo                  -- T, en trabajador·veintena; 0 por defecto
  , coMateriales :: Map Material Fijo     -- M_g; vacío por defecto
  , coOficio     :: Maybe (Conocimiento, Fijo) }   -- conocimiento y dominio mínimo; Nothing por defecto

data Obra = Obra                          -- en el altépetl (o en la celda, etapa 4); persistente
  { obEdificio  :: Text
  , obAvance    :: Int                    -- v: veintenas de obra transcurridas
  , obTotal     :: Int                    -- D
  , obCuadrilla :: Int                    -- C, la que eligió el jugador, ≤ cuadrilla máxima; 0 sin cuadrilla
  , obTrabajo   :: Fijo                   -- w: trabajo hecho, ≤ T
  , obAcopio    :: Map Material Fijo }    -- A_g ∈ [0, M_g]
-- etapa 2: obEnCamino :: [Entrega], con
-- data Entrega = Entrega { enDe :: AltId, enMaterial :: Material, enCantidad :: Fijo, enLlega :: Tick, enCosto :: Fijo }
```

`Material` es texto, como los bienes: un dato de la tabla de terrenos (`materiales`, con su rendimiento y sus trabajadores por celda, igual que `rendimiento` en la sección 12, pero sin existencias en la facción).

**Cuadrilla.** Al empezar, la cuadrilla se retira con `retirar_trabajadores` (motivo `obra`): R_a sube en C y W_a de la sección 12 baja en lo mismo, con su `max` para que nunca sea negativo. Al terminar, R_a vuelve. Cada veintena trabaja la parte sostenida por la partida de obras:

```math
C^{\text{ef}} = \min\Big(C,\ \Big\lfloor \frac{\text{partida de obras disponible}}{s} \Big\rfloor\Big)
```

con s = `SUSTENTO_CUADRILLA` por trabajador y veintena, en valor. Si hay varias obras, la partida se reparte en orden de altépetl, y el desglose dice cuántos trabajan de cuántos.

**Un paso de obra** (paso 10, cada veintena). La obra no guarda su avance P sino lo hecho (v, w y A); P se lee como

```math
P = \min\Big(\frac{v}{D},\ \frac{w}{T},\ \min_g \frac{A_g}{M_g}\Big)
```

y la obra termina cuando las tres razones llegan a 1. Es la misma regla que la de abajo, sin acumular el redondeo de P. Con η = dominio(oficio) / 100 (1 sin oficio; la fórmula `dominio_tecnologia` de la sección 14e) y F_g = M_g − A_g − (lo que viene en camino) lo que falta de cada material:

1. **Extracción.** La cuadrilla va primero a los materiales que faltan, en orden de material. Para cada g, sobre las celdas del altépetl que rinden g, ordenadas como en la sección 12, se calcula con la misma fórmula del factor escaso cuántos trabajadores E_g sacan F_g, sin pasar de los que quedan libres. Lo extraído, x_g = η · produccionCeldas(E_g, celdas_g), se acopia: A_g ← min(M_g, A_g + x_g).
2. **Entregas.** Las entregas con `enLlega` ≤ t se suman al acopio si el tesoro paga su costo; si no, esperan a la veintena siguiente.
3. **Obra en el sitio.** Con L = C^ef − Σ_g E_g, el trabajo crece w ← min(T · min_g A_g/M_g, w + η L) y v ← v + 1 (solo en las veintenas en que trabaja alguien de la cuadrilla). En términos de P:

```math
P_{t+1} = \min\Big(1,\ P_t + \frac{1}{D},\ P_t + \frac{\eta\, L}{T},\ \min_g \frac{A_g}{M_g}\Big)
```

donde cada término falta si no aplica: sin T, no hay tope por trabajo; sin materiales, no hay tope por acopio. Con T = 0 y sin materiales no hay cuadrilla, y P avanza 1/D en cada veintena en que la partida de obras llega a `cObrasPresupuestoMinimo`: es la obra del primer corte.

4. **Fin.** Cuando v ≥ D, w ≥ T y A_g ≥ M_g para todo g, la obra termina: R_a baja en C, se recalcula el beneficio de su tipo (abajo), se aplican los efectos al terminar y se emite `edificio_terminado`.

**Tributo en especie** (etapa 2, implementada). Con la obra empezada, `PedirTributoObra a g s n` pide a otro altépetl s de la facción que envíe el material g con n trabajadores suyos. Se rechazará si s es independiente (`Cabecera f` con f ≠ la facción, sección 14b) cuando exista la condición del altépetl. El altépetl s extrae con sus propios trabajadores (`retirar_trabajadores`, motivo `tributo_obra`) y recibe el agravio del tributo. Ese agravio es un modificador de `tasa_agravio` con fuente `tributo_obra:<a>:<g>` y valor `AGRAVIO_TRIBUTO_OBRA`; se multiplicará por `AGRAVIO_TRIBUTO_SENORIO` si su condición es `Senorio`. Cada veintena, s extrae a lo sumo lo que falta, F_g = M_g − A_g − (lo que viene en camino), y crea una entrega:

```math
\text{llega} = t + 20\cdot\Big\lceil \frac{d_{\text{costo}}(s, a)}{v} \Big\rceil, \qquad \text{costo} = k \cdot q \cdot d_{\text{costo}}(s, a)
```

con v = `VELOCIDAD_TRANSPORTE` (costo del grafo que recorre una carga por veintena), k = `COSTO_TRANSPORTE` y q la cantidad. La distancia d_costo(s, a) sale del derivado: en el paso 16, cada altépetl con obra hace un recorrido persistente acotado por `ALCANCE_TRIBUTO`. Su costo es lo que alcanza, no el tamaño del mapa: con 150 000 celdas, 1,2 ms por obra. Por eso el pedido se hace desde la veintena siguiente al inicio de la obra. El transporte se cobra al tesoro al llegar, en el paso 10, así que el tesoro tiene dos escritores declarados: la hacienda y la construcción. Como d_costo es la distancia del grafo, un camino acorta el retraso y abarata el costo sin regla propia. La consulta suma, por fuente, cantidad, retraso y costo.

**Oficio** (etapa 3). Si el edificio pide (κ, d_min), la obra se rechaza al empezar con dominio(κ) < d_min, sin cambiar el estado. Al terminar una obra con oficio κ, el sistema actualiza en la facción un modificador de `conocimiento.κ.tacito` con fuente "práctica", de instancia estable y valor

```math
a_{\text{práctica}}(n) = \alpha_\kappa \cdot \ln(1 + n)
```

con n las obras terminadas con ese oficio. No escribe la base, que sigue siendo del sistema de difusión (sección 14e), vacío en el prototipo.

**Beneficio por tipo de edificio.** Cada modificador de un edificio declara una fórmula con nombre f. Para un altépetl a, un tipo e y una magnitud m hay **un solo** modificador, con fuente `edificio:<e>:<a>`, cuyo valor recalcula el sistema de construcción cada veintena, con los valores de la anterior:

```math
\text{aporte}_{e,m}(a) = f(n_e(a),\ \text{contexto}(a))
```

| Fórmula | f | Contexto |
| --- | --- | --- |
| `fija` | a, si n ≥ 1 (el primer corte; por defecto) | — |
| `lineal` | a · n | — |
| `logaritmica` | a · ln(1 + n) | — |
| `por_asistentes` | a · ln(1 + S / ref), S = min(F, n · cap, cap · σ / s) | F: fieles que asisten (abajo); σ: sacerdotes de la tradición del templo en el estrato `sacerdote` |
| `por_guarnicion` | a · Σ_i min(1, g_i / g) | g_i: guarnición asignada al edificio i; hasta el hito 4, g_i = g |

**Asistencia.** Cada templo e tiene una tradición τ(e) y un nivel. Un pop p practica la tradición τ con afinidad

```math
\phi_p(\tau) = \begin{cases} g_p & \tau = \text{católica} \\ 1 - g_p & \tau = \text{tradición de la identidad de } p \text{ (o compatible con ella, por datos)} \\ 0 & \text{si no} \end{cases}
```

con g_p el `gradiente_catolicismo`. Para cada tradición τ:

- **Local.** Los templos locales de τ son fuentes de un reparto como `asignarCeldas`, sobre el costo del grafo con tope `ALCANCE_TEMPLO_LOCAL`: cada pop va al de menor (d_costo, id), una sola vez. Los fieles del templo local e son F_e = Σ_{p → e} N_p · φ_p(τ), y el beneficio va al altépetl de e.
- **Centro ceremonial.** Para un centro e de τ, F_e = Σ_p N_p · φ_p(τ) · w(d_costo(p, e)), con w(d) = max(0, 1 − d / `ALCANCE_CENTRO_CEREMONIAL`); el beneficio es de la facción. Se calcula con un recorrido desde los centros, con tope de distancia.

Cada pop suma a lo sumo 1 en los templos locales del conjunto de tradiciones (Σ_τ φ_p(τ) ≤ 1), así que nadie asiste dos veces a lo local. Los recorridos son del paso 16: las tradiciones y los templos se cuentan por decenas, y cada recorrido tiene tope.

El ln se calcula con la tabla de la sección 15. El desglose lleva los argumentos del contexto (n, N_a, sacerdotes), así que explica el número aunque cambie cada veintena.

**Ámbito de celda** (etapa 4). Una obra en celda c guarda sus edificios en un `IntMap [Text]` por celda ocupada. Sus modificadores llevan la condición `controla(dueño, c)`, evaluada en el paso 16 como cualquier condición de modificador (sección 6). Esa condición no existe hoy en el lenguaje cerrado de `Motor.Guion`: entra como un constructor nuevo (`Controla FaccionId CeldaId`), evaluado con `control` de la sección 9. Un edificio puede aportar además a la fuerza F de una fuente de influencia con origen en c (sección 9).

## 15. Punto fijo y aritmética determinista

```haskell
newtype Fijo = Fijo Int64     -- 1,0 = Fijo 10000
```

| Operación | Regla |
| --- | --- |
| Suma, resta, comparación | Exactas |
| Multiplicación | `(a * b) div 10000` con el producto intermedio en 128 bits (`Int128` de `wide-word`, o `Integer` en la versión de referencia), redondeo hacia abajo |
| División | `(a * 10000) div b`, también con intermedio de 128 bits; dividir entre cero es un error de tipo (`Maybe`), nunca una excepción |
| ln | Tabla en punto fijo (por ejemplo, 1 024 entradas) con interpolación lineal; solo para π_s de la influencia y fórmulas que lo pidan |
| exp | Serie truncada o tabla, en un rango acotado; solo para fórmulas del núcleo como la de invasión |
| Exponencial de la influencia | Solo en el cliente, con `float`, porque solo afecta al dibujo |

Las tablas y series están definidas en el código del proyecto, no en la biblioteca matemática de la plataforma. Así el resultado es idéntico en cualquier máquina.

**Por qué la escala es 10 000 y no 2¹⁶.** La decisión queda cerrada en 10 000:

- **Los datos son decimales.** Las constantes del JSON se escriben como 0,02, 0,8 o 0,95. Con escala 10 000 son exactas (200, 8 000, 9 500); con 2¹⁶ ninguna lo es (0,02 · 65 536 = 1 310,72), y cada una se redondea al cargar. El tooltip mostraría 0,0199 donde el diseñador escribió 0,02.
- **La divisibilidad no favorece a 2¹⁶.** Ni 10 000 ni 65 536 se dividen exactamente entre 3 o 7; dividir entre 2 es exacto en las dos para valores pares.
- **El determinismo es el mismo.** Toda aritmética entera es determinista; la escala no lo cambia. Que en 2¹⁶ la división sea un desplazamiento es una ventaja de velocidad irrelevante a esta escala.
- **La resolución basta.** El paso mínimo es 0,0001. Las fracciones de persona que la escala no ve las conservan los restos de crecimiento y migración (sección 12).

La conversión es `desdeDecimal :: Text -> Either ErrorCarga Fijo`, que rechaza al cargar una constante con más de cuatro decimales en lugar de redondearla en silencio.

**Rango y desbordamiento.** Cada magnitud declara su rango [min_m, max_m] en el catálogo, y `valorEfectivo` lo aplica (sección 6). Con el producto intermedio en 128 bits, solo puede desbordar el resultado, y eso se impide en tres capas:

1. **Al cargar,** se comprueba que el rango de cada magnitud, multiplicado por el mayor factor que pueden darle sus modificadores, cabe holgadamente en `Int64`.
2. **En modo de prueba,** cualquier desbordamiento es un fallo inmediato con el sistema y la entidad que lo causaron.
3. **En producción,** la operación satura en el límite de `Int64` y deja una entrada en el registro. Saturar también es determinista, así que una partida no se desincroniza aunque llegue a ocurrir; pero la ley de rango (sección 19) existe para que no ocurra.

## 16. El protocolo como funciones

```haskell
proyeccion :: Juego s c -> Estado s -> Vista            -- sección 1
cambios    :: Vista -> Vista -> Cambios                 -- se calcula sobre las vistas
aplicar    :: Vista -> Cambios -> Vista                 -- en el cliente: reemplazar, no fusionar

data Cambios = Cambios
  { tick         :: Tick
  , actualizadas :: [EntidadVista]   -- nuevas o cambiadas, completas
  , eliminadas   :: [EntRef] }       -- un ejército destruido, un pop que se fusionó
```

`Cambios` necesita la lista de eliminadas. Con solo entidades actualizadas, una entidad que desaparece nunca llegaría al cliente: el espejo seguiría dibujando un ejército destruido, y la ley de conmutación fallaría.

**Implementación de referencia y optimizada.** La versión de referencia de `cambios` es literal: comparar la proyección de cada entidad antes y después del tick. Es lenta pero correcta por construcción. La versión real lleva un registro de entidades tocadas durante el tick. La prueba es que las dos coinciden.

**Dos leyes del espejo:**

```math
\text{aplicar}\big(\text{proyeccion}(s),\ \text{cambios}(s, s')\big) = \text{proyeccion}(s')
\qquad \text{(conmutación)}
```

```math
\forall e.\ \ \text{proy}_e(s) \ne \text{proy}_e(s') \implies e \in \text{actualizadas}(s, s') \cup \text{eliminadas}(s, s')
\qquad \text{(completitud)}
```

con proy_e(s) = ⊥ si la entidad e no existe en s; así, aparecer y desaparecer también cuentan como cambio.

La conmutación dice que el espejo es correcto si recibe los cambios; la completitud, que los recibe todos. Juntas son la definición de que el espejo no miente.

**Versión del protocolo.** El primer mensaje de cada lado es `hola { version :: Int }`. La regla de compatibilidad:

- **Cambio aditivo** (un comando nuevo, un campo opcional nuevo, un tipo de hecho nuevo que el cliente puede ignorar): la versión no sube.
- **Cambio que rompe** (quitar o renombrar un campo, cambiar su tipo o su significado): la versión sube, y versiones distintas se rechazan con un aviso.

Las reglas se fijan antes del hito 4, como dice V5.

## 17. Escenarios

```haskell
data Escenario = Escenario
  { inicio, fin        :: Fecha
  , desfaseCalendario  :: Int
  , estadoInicial      :: Persistente
  , mascara            :: Set CeldaId
  , faccionesJugables  :: Set FaccionId
  , sistemasActivos    :: Set NombreSistema
  }

cargarEscenario :: Mapa -> Escenario -> Either ErrorCarga Estado
```

Un sistema fuera de `sistemasActivos` se sustituye por la identidad. No hay otra forma de recortar: el "sin `if prototipo`" de V5 es este tipo.

## 18. Carga de datos, mods y versiones

Cargar es una función pura de los archivos al estado, que falla con todos los errores juntos en lugar del primero:

```haskell
cargarDatos :: [ArchivoJSON] -> Validacion [ErrorCarga] Catalogo   -- acumula errores
```

- **Mods como pliegue.** Los archivos se pliegan en el orden declarado: una entidad con el mismo id reemplaza entera a la anterior, y `"eliminar": true` la quita. Los modificadores son la excepción: un mod los *añade*. Formalmente, las entidades se combinan con "el último gana" (un monoide no conmutativo, así que el orden de carga importa y se registra) y los modificadores con unión.
- **Versión de esquema.** Cada archivo declara `version_esquema`. Un archivo antiguo pasa por una cadena de migraciones puras, `migrar_n :: JSON_n -> JSON_(n+1)`, hasta la versión actual; un archivo más nuevo que el núcleo se rechaza.
- **Guardados antiguos.** El persistente guardado lleva también su versión y usa la misma cadena de migraciones. Una ley lo protege: cargar un guardado de la versión anterior y volver a guardarlo da un guardado válido de la versión actual.
- **Personalidades validadas.** `validarPersonalidad :: Personalidad -> Validacion [ErrorCarga] Personalidad` rechaza al cargar cualquier peso fuera de su rango, como pide V5.
- **Después de cargar,** el catálogo pasa las validaciones estáticas: el mapa (`validarMapa`), el orden de los sistemas (`lee`/`escribe`), las variables de los eventos y los rangos de las magnitudes.

## 19. Leyes del sistema

Las reglas del diseño, escritas como propiedades. En un lenguaje puro, "la misma expresión da el mismo resultado" es una tautología; las propiedades de determinismo que importan son las que cruzan fronteras: el registro, el disco, la máquina y la versión del compilador.

| Ley | Enunciado |
| --- | --- |
| Repetición | Plegar el registro de comandos sellados desde `s0` reproduce la traza original |
| Estabilidad del azar | `rng σ s t` coincide con valores conocidos, en dos máquinas y dos versiones de GHC |
| Estabilidad del estado | El hash del estado tras N ticks coincide con un valor dorado en todas las plataformas de la integración continua |
| Ida y vuelta del guardado | `decodificar (codificar p) == p` para todo persistente generado |
| Derivado reproducible | Para todo estado s, incluso a mitad de veintena: `derivado <$> cargar j m (guardar s) == Right (derivado s)`, y la partida cargada sigue igual que la original |
| La explicación es el cálculo | Para toda magnitud y entidad, el valor publicado es `valorEfectivo` de su base y sus modificadores activos |
| Conmutatividad | El valor efectivo no cambia al permutar los modificadores |
| Rechazo sin daño | Si `aplicarComando s c` rechaza, el estado no cambia |
| Conservación en la migración | La población total antes y después de la migración es la misma |
| Piso de población | Ningún pop queda bajo `POP_MINIMO` |
| Relajación estable | Con 0 < α ≤ 1, la lealtad nunca sobrepasa su objetivo |
| Simetría del mapa | Toda conexión aparece en ambos sentidos |
| Influencia correcta | El resultado del Dijkstra multifuente coincide con el mínimo por fuerza bruta en mapas pequeños |
| Combate: monotonía y simetría | Las dos leyes de la sección 13, con el azar acoplado |
| Variables bien formadas | Ningún evento cargado lee una variable no escrita antes |
| Espejo: conmutación y completitud | Las dos leyes de la sección 16, y la versión optimizada de `cambios` coincide con la de referencia |
| Rango | Para todo estado generado, toda magnitud queda en su rango y ninguna operación de `Fijo` desborda |
| Trabajadores y presión acotados | W_a ≥ 0 y π_a ∈ [0, π_max] para todo asentamiento |
| Producción monótona | Añadir una celda o un trabajador nunca baja Q_a |
| Agente externo | La partida con el agente y la partida con sus respuestas registradas dan la misma traza |
| Fases monótonas | φ(t+1) ≥ φ(t) para toda traza; un guardado a mitad de fase carga en la misma fase |
| Presión sin saltos | Al apagar una fuente, su aporte no crece y llega a 0 en a lo sumo la duración de sus modificadores |
| Decisiones únicas | Ningún identificador de decisión se repite en una partida; una respuesta a una decisión cerrada se rechaza sin cambiar el estado |
| Director determinista | Dos partidas con la misma semilla, guion y comandos presentan las mismas situaciones el mismo día |
| Variedad | Con el guion definitivo del escenario, el arnés de 30 años cumple parte_max ≤ 0.25 y nuevos(d) ≥ 2 (sección 11b) |
| Precio monótono | p_g no crece con las existencias ni con la producción; con elasticidad 0 no depende de ellas; nunca baja de p_min (sección 14g) |
| Moneda estable | Si las existencias y la producción de la moneda no cambian, la inflación es 0 |
| Moneda persistente | Guardar y cargar a mitad de periodo conserva la moneda y su historial, y la partida sigue igual; un guardado sin monedas carga sin monedas |
| Historial por moneda | Cambiar de moneda vacía el historial: la inflación nunca compara dos monedas |
| Valor conservado al cambiar de cuenta | Designar, cambiar o retirar la moneda no cambia el valor real de las magnitudes nominales, salvo el redondeo (sección 14g) |
| Nombramiento sin trinquete | Mientras dura un cargo, su aporte al poder del grupo es constante; al terminar el cargo, es 0 y sus modificadores emiten `modificador_terminado` (sección 14d) |
| Facciones con rastro | Toda aparición emite `faccion_aparece` y toda desaparición `faccion_desaparece`; lo que tenía la facción llega a un destino declarado o se pierde por declaración; los ids no se reutilizan (sección 14b) |
| Insumos en especie | Un insumo nunca se paga con valor; sin insumo ni sustituto, la actividad se rechaza sin cambiar el estado; la penalización es proporcional a la fracción que falta (sección 14h) |
| Costo del grafo | El costo de toda conexión es positivo y simétrico; parchear las celdas que cambiaron da el mismo grafo que reconstruirlo (sección 8) |
| Obra acotada | 0 ≤ P ≤ 1 y P no decrece; 0 ≤ A_g ≤ M_g; ninguna obra termina antes de D veintenas; con T = 0 y sin materiales, la obra es la del primer corte (sección 14i) |
| Cuadrilla conservada | Mientras dura la obra, R_a la incluye y W_a ≥ 0; al terminar o cancelarse, R_a vuelve a su valor sin la obra |
| Materiales sin trampa | Ningún material se paga con valor: solo con extracción o entrega; una entrega no llega antes de su retraso ni sin pagar su transporte |
| Asistencia sin duplicados | En los templos locales, la suma de los fieles de todos los templos no pasa de Σ_p N_p; un pop con g = 0 no cuenta en templos católicos y uno con g = 1 no cuenta en yácatas |
| Beneficio monótono | Toda fórmula de beneficio es no decreciente en n y en su contexto; `logaritmica` y `por_asistentes` son cóncavas en n: la copia n + 1 nunca aporta más que la n |
| Recetas sin ciclos | Ninguna receta depende, directa o indirectamente, de sí misma; la carga lo rechaza (sección 14e) |
| Migración de guardados | Un guardado de la versión anterior se carga, se vuelve a guardar y es válido en la actual |
| Autoridad neutra en el prototipo | Sin títulos almacenados y con `Requiere` por defecto, ningún comando del soberano se rechaza por autoridad y su eficacia es 1: la traza es la misma que sin la capa de autoridad (sección 14b) |
| Titular exclusivo único | Para toda entidad y eje hay a lo sumo un titular exclusivo, y no depende del orden de la lista de títulos |
| El soberano conserva la exclusividad | Para toda entidad y eje sin títulos vigentes con `fuerzaExclusividad`, si hay soberano, `titularExclusivo` lo devuelve aunque otro titular tenga más autoridad |
| Rechazo sin fuga | Un rechazo por autoridad solo nombra entidades presentes en la proyección de la facción que emitió el comando |
| Conservación en la mezcla | La mezcla no cambia la población total de ningún asentamiento ni transfiere más que los nacimientos de la veintena; con todas las tasas en 0 es la identidad; tras el recorte por mayor resto ningún m_ijk es negativo y la suma de los de cada identidad no supera B_i |
| Concesión ligada al otorgante | Si el otorgante deja de ser soberano de la entidad, la concesión deja de contar como título en ese mismo tick (sección 14c) |
| Concesiones con fin | Ninguna concesión cargada u otorgada carece a la vez de fecha de fin y de condiciones |
| Romper cuesta más que otorgar | `costo_ruptura` es no decreciente en la duración y, desde la duración 0, no es menor que el costo de otorgar |
| Propuestas únicas | Ninguna propuesta se responde dos veces; responder una propuesta cerrada se rechaza sin cambiar el estado |
| Lealtad monótona en el eje | Subir la lealtad de un grupo nunca baja el valor de su eje; con lealtad 100 el grupo no resta nada (sección 14d) |
| Tope de lealtad | Tras cada paso 16, la lealtad efectiva de todo grupo es a lo sumo la legitimidad efectiva más `MARGEN_LEALTAD_GRUPO` |
| Reforma bloqueada sin efectos | Una reforma bloqueada abre una decisión y no aplica ninguno de sus efectos hasta la respuesta |
| Difusión con contacto | Sin contacto por ningún canal y sin modificadores positivos, el conocimiento de una tecnología no crece |
| Lo codificado no muere | La mortalidad y la emigración nunca bajan el conocimiento codificado; el conocimiento queda siempre en [0, 100] |
| Pluralismo monótono | Subir la política religiosa nunca baja el agravio de un pop de otra tradición ni la legitimidad; sin pops de otra tradición, la política no aporta nada (sección 14f) |
| Política sin sobrepaso | Con 0 < α_P ≤ 1, la política religiosa nunca sobrepasa su objetivo |
| Sincretismo con contacto | El gradiente queda en [0, 1]; un pop sin doctrina, escuela ni evento que aporte a su tasa conserva su gradiente; solo el sistema de religión lo escribe |
| Templo con mantenimiento | Un templo cuyo mantenimiento se cubre no pierde niveles salvo por profanación, y la profanación solo ocurre tras saqueo o cambio de control |
| Rechazo según el gradiente | El agravio por rechazo del ritual es no decreciente en el gradiente y en el número de prisioneros, cero con gradiente 0, y no decrece al añadir componentes |
| Omisión según el gradiente | El agravio por omisión es no decreciente en 1 − gradiente, cero con gradiente 1 y cero para pops de otra tradición |
| Ritual dentro de la práctica | Ningún ritual realiza un componente fuera de la tradición o de la práctica vigente; si lo pide, se rechaza sin cambiar el estado |
| Legitimidad por ritual acotada | Un ritual nunca aporta más que `TOPE_RITUAL` de legitimidad |
| Justificación religiosa con contacto | Solo una facción con contacto y cuyo culto condena un componente realizado obtiene el casus belli; vence exactamente `VEINTENAS_JUSTIFICACION_RELIGIOSA` después del último ritual que lo renovó |
| Abasto acotado | Para todo ejército, la reserva de abasto queda en [0, 100] |
| Forrajeo con techo | El forrajeo nunca lleva la reserva por encima de `UMBRAL_FORRAJEO`, y todo día con forrajeo aporta agravio y un modificador negativo de producción al asentamiento afectado |
| Ruta cortada sin aportes | Si una celda de la ruta está bajo control enemigo, ningún aporte que dependa de la ruta suma al flujo |
| Guerreros conservados | Desertar, disolverse o amotinarse nunca cambia la población total; solo el combate y el hambre la reducen. Ningún retiro de trabajadores queda negativo |
| Asedio con costo para ambos | Durante un asedio, el abasto del sitiador sigue sus reglas y las reservas de la plaza no suben sin levantar el sitio |
| Independencia de la vista | La traza es función solo de (s0, σ, registro de comandos): ni la cámara, ni los paneles abiertos, ni los ajustes gráficos del cliente cambian un solo valor del estado |
| Condición del altépetl coherente | `altCondicion a == Cabecera f` si y solo si f está activa y a es su centro; un altépetl `Sujeto` o `Senorio` tiene `altSujetoA` y comparte la bolsa de su facción |
| Crisis del sacrificio única por umbral | Cada umbral dispara la crisis a lo sumo una vez por partida, también tras guardar y cargar |

**Dos leyes que se parecen y no son la misma.** "La explicación es el cálculo" es interna al núcleo: el valor publicado sale de la misma lista que el desglose. La completitud del espejo es entre núcleo y cliente: esa lista llega entera a Godot. Un modificador puede cumplir la primera y fallar la segunda, si el núcleo lo cuenta pero no lo envía. Por eso hacen falta las dos.

Los generadores de QuickCheck se sesgan hacia ticks con eventos, combates, veintenas y sucesiones, y los casos que rompen en producción (reconexión, carga, veintena, expiraciones) se escriben a mano.

## 20. Orden de construcción

Esta tabla es la proyección formal de la tabla de hitos de V5: para cada hito, qué funciones, tipos y leyes se construyen. Lo que no es del núcleo (cliente, pruebas con personas) se indica entre paréntesis.

| Hito | Piezas formales |
| --- | --- |
| 0 | Ninguna en Haskell; corre en paralelo con 1a y 2. El prototipo de mesa valida las fórmulas antes de programarlas: producción con el factor escaso, agravio y lealtad como relajación, legitimidad que vuelve a su base. El arnés de 30 años es el mismo pliegue `partida` con agentes de reglas. Su criterio de variedad es una función sobre la traza, con la medición (`diferencias`) separada del juicio (`evaluar` con umbrales en datos): ninguna clase de decisión supera el 25 % del total y cada década trae al menos dos clases nuevas. Desde la iteración v5 suma los criterios de tensión de `docs/evaluacion_hito0.md`: la estrategia con criterio supera a las reglas fijas según el veredicto del juego; invertir una decisión pesa más que perturbar el azar; ninguna opción sin costo (`validar_opciones.py`); y el modelo de espera, que clasifica cada veintena en decisión, anticipación o vacía. Entrega las fórmulas que pasen como especificaciones con su tabla de casos (sección 1) |
| 1a | Paquete `motor`, polimórfico en el juego: `Fijo`, `desdeDecimal` y sus tablas; `Aporte` y `valorEfectivo`; `Mapa`, proveedor hexagonal y `validarMapa`; `Sistema` con `lee`/`escribe`, `activo`, `correr` con pasos identidad y la guarda de veintena; `rng` con SplitMix64; `Estado` con persistente y derivado; `cargarDatos` con versión de esquema; intérprete de efectos con suspensión; `proyeccion` y `cambios` genéricos; agente nulo; `Escenario`; `Juego` y el juego de juguete con sus seis rutas; bucle de la cáscara; leyes de repetición, estabilidad, ida y vuelta, explicación, conmutatividad, rechazo sin daño, rango, conservación y espejo, todas comprobadas con el juego de juguete. No depende del hito 0; plazo de tres semanas. Mods, migraciones de esquema, mapa irregular y agente aleatorio, cuando algo los pida |
| 1b | Paquete `reglas`: `aplicarComando` para tesoro, tasas y presupuesto; agravio de los pops; fórmulas del hito 0 con sus tablas de casos como pruebas; validación de personalidades; el escenario inicial; el campo `requiere` en el catálogo de comandos con su valor por defecto y `autorizar` como primera línea de `aplicarCmd` (con `Todo`, nunca rechaza) y la ley de autoridad neutra; las leyes de 1a, ahora con el juego real. Empezó con el 0a cumplido (31 de octubre de 2026) |
| 2 | `cambios` optimizado (la versión de referencia ya existe desde el 1a), `consultar`, mensaje `hola` con la versión; leyes del espejo. (Cliente: `aplicar` en GDScript con el corpus dorado, malla con colores planos, barra superior; el reloj real y las cinco velocidades viven en la cáscara) |
| 3 | Asignación de celdas (Voronoi), producción con el factor escaso, capacidad y presión acotada, eficiencia, carga administrativa, `retirar_trabajadores` con W ≥ 0, legitimidad; leyes de trabajadores, presión y producción monótona |
| 3b | Crecimiento con resto, dispersión, migración con mayor resto; leyes de conservación y piso de población |
| 4 | Influencia tropical con dos etiquetas y suma saturada; control; `resolver_combate` provisional y sus leyes; estación; guerra ritual; planificador y ejecutor con personalidad; reglas de compatibilidad del protocolo; abasto con reserva y flujo, ruta cortada, hambre, deserción, motín y asedio que consume al sitiador, con sus leyes (sección 13b; forrajeo, desertores asentados, relevo y salida si el arnés los pide) |
| 5 | Efectos de crisis sobre el intérprete con suspensión del 1a, contexto de variables completo, crisis, frente abstracto, viruela, cadencia `Anual` para personajes y sucesión; benchmarks con `criterion` en la integración continua |
| 5b | Ninguna nueva. (Prueba con personas del escenario de crisis.) Los registros de comandos de cada sesión se guardan para repetir y analizar las partidas con la ley de repetición |
| 6 | Escenario completo; migración entre facciones (la misma matriz de flujos, con los destinos de otras facciones), colonos de frontera y fundación de asentamientos (un asentamiento nuevo cambia el Voronoi en el siguiente paso 16); decisión sobre el lenguaje de expresiones |
| 6a | Erosión como ecuación en diferencias por celda, provisional: g_(t+1) = min(1, g_t + e_c · max(0, π_a − 1) · (1 − θ_c)), con g la degradación, e_c la tasa de erosión y θ_c la protección de terrazas. La capacidad recibe un modificador −g·capacidad. Ley: con θ = 0 y presión sostenida, g crece; con terrazas, crece menos de la mitad |
| 7 | Ninguna nueva. (Prueba con jugadores.) Mismo análisis de registros que en 5b |
| Juego completo | `Avance` como corrutina para agentes externos y su ley; `pasoTactico`; `interpolar` en el cliente; títulos almacenados, ejes como magnitudes con base por tipo de facción, `titularExclusivo`, clases exclusiva y concurrente en el catálogo, sistema de vencimiento de títulos y leyes de titular único y rechazo sin fuga (sección 14b); mezcla como flujo de nacimientos y su ley de conservación; vínculos, concesiones con otorgante, propuestas y visibilidad, con sus leyes (sección 14c); grupos de poder, tope de lealtad y reformas con bloqueo (sección 14d, o antes si ocupa la extensión opcional del hito 4); difusión tecnológica y sus leyes (sección 14e); sistema de religión del paso 15 con sincretismo, y templos con niveles y profanación (sección 14f; la política religiosa y los templos pueden adelantarse a la extensión opcional del hito 4 y al hito 5) |

## 21. Decisiones formales

**Cerradas en este documento:**

- [x] Escala del punto fijo: 10 000, con producto intermedio de 128 bits (sección 15)
- [x] Forma provisional de `resolver_combate`, sujeta a monotonía y simetría (sección 13)
- [x] Producción como tierra y brazos con el factor escaso, no como capacidad (sección 12)
- [x] Autoridad en el paquete `reglas`, sin cambiar la interfaz `Juego`; el soberano tiene título implícito y solo se guardan los títulos de otras facciones (sección 14b)
- [x] Mezcla como flujo de nacimientos dentro del sistema de demografía, con resto y mayor resto (sección 14b)
- [x] El eje es un dato (`newtype Eje = Eje Text`) declarado en `datos/ejes.json`; los ejes activos de un escenario se calculan al cargar, viven en el `Entorno` y no se guardan (sección 14b)
- [x] La eficacia es `capacidad / referencia`, con la referencia como dato de cada eje; la legitimidad conserva su base 50 (sección 14b)
- [x] El soberano conserva la exclusividad salvo que pierda la soberanía o un título declare `fuerzaExclusividad` (sección 14b)

**Abiertas:**

- [ ] Tamaño de la tabla de logaritmos
- [ ] Regla de redondeo de la multiplicación (hacia abajo o al par más cercano)
- [ ] Calibración de `resolver_combate` (ε, τ, multiplicador de persecución)
- [ ] Función de atractivo A y peso w de la migración
- [ ] Función δ* de la proporción objetivo de población dispersa
- [ ] Representación concreta de las colecciones (`IntMap`, vectores sin boxing) según el perfil del hito 3
- [ ] Si `titularExclusivo` se memoiza por veintena en el derivado, cuando el perfil lo pida (sección 14b)
- [ ] Cómo se nombran y declaran las magnitudes por par de identidades (`asentamiento.tasa_mezcla.<i>.<j>`) sin que el catálogo crezca de forma cuadrática con identidades ausentes del escenario
- [ ] Forma de `costo_ruptura` y del tipo `Costo` (tesoro, prestigio, legitimidad, relación) (sección 14c)
- [ ] Representación de `Obligacion` en datos y cómo detecta el motor su incumplimiento (sección 14c)
- [ ] Forma de `dominio_tecnologia` (mínimo u otra combinación no decreciente) y pesos de contacto w_c por canal (sección 14e)
- [ ] Cuántas tecnologías y facciones activas aguanta el paso 15 por veintena; el número de magnitudes crece como facciones × tecnologías × 2 (sección 14e)
- [ ] Si `tasa_sincretismo` es magnitud por pop o por asentamiento, según el número de pops del juego completo (sección 14f)
- [ ] Orden dentro del paso 15 entre difusión tecnológica y religión (la educación de la difusión acelera el sincretismo por las escuelas) (secciones 14e y 14f)
- [ ] Costo de calcular cada día la ruta de cada ejército al troje más cercano; si el perfil lo pide, recalcularla solo cuando el ejército se mueve o cambia el control de una celda de la ruta (sección 13b)
