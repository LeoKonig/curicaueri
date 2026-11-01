# Curicaueri: Flor y Canto — núcleo del juego (motor y reglas)

Núcleo en Haskell de *Curicaueri: Flor y Canto*, juego de gran estrategia sobre Mesoamérica (la campaña 1418–1607 jugada desde el reino purépecha; el escenario actual es todavía el provisional de 1475). El núcleo decide todo el estado del juego; el cliente en Godot solo dibuja y captura la entrada.

Este código implementa dos documentos de diseño, que conviene leer antes de tocarlo:

| Documento | Qué dice |
| --- | --- |
| `arquitectura-prototipoV5.md` | **Qué** es el juego: mecánicas, palancas, hitos y criterios |
| `arquitectura-funcional.md` | **Cómo** se modela: tipos, ecuaciones y leyes. Las secciones citadas en el código ("sección 12") son de este documento |

## Estado

**Hito 1a (motor): criterio mínimo cumplido.** El motor corre con un juego de juguete que pasa por las seis rutas difíciles, y las leyes del criterio se comprueban con pruebas automáticas (202 pruebas en el motor, incluidas las de los archivos dorados, las del guion y las de la moneda; 18 en las reglas).

**Actos modulares: en el motor.** Guion con fases, situaciones con vocabulario de tipos cerrado y director (`Motor.Guion`, `Motor.Director`), conectados al paso, al guardado y al protocolo, y probados con el juego de juguete y su guion (`test/guion_juguete.json`), incluida la prueba de métricas del hito 0. El guion del escenario es ilustrativo hasta el hito 0.

**Moneda designada e inflación: en el motor.** Precio de cada bien según su escasez, designación de moneda por entidad, nivel de precios, inflación anual e historial persistente (`Motor.Moneda`), conectados al paso y al guardado, y probados con el juego de juguete y sus bienes (`test/bienes_juguete.json`). Las magnitudes nominales (el tesoro) se convierten al designar la moneda sin perder valor, y `enCuenta` pasa costos e ingresos al tipo del día. El juego real todavía no lo usa: falta el comando `DesignarMoneda` en `reglas` y la producción de bienes del hito 3 (ver V5, *La moneda designada y la inflación*).

**Hito 2 (protocolo y atlas): cerrado, salvo calibrar las velocidades jugando.** Protocolo con nombres JSON explícitos y archivos dorados; cáscara con socket, reloj y velocidades configurables; consulta (predicción hasta la siguiente veintena); guardar y cargar; cliente en Godot con mapa, paneles genéricos, informe de veintena y medidor de tiempo en pausa. El criterio de 2 700 hexágonos a 60 FPS se cumple con margen en una NVIDIA MX150 (percentil 99 de 7,2 ms). Falta calibrar las velocidades jugando (ver `../docs/calibrar.md`).

**Agentes externos: verificados en Python y Mercury.** Los dos responden igual a los casos compartidos y la partida con cualquiera de ellos es idéntica.

**Hito 1b (reglas): la parte del 0a que da las fórmulas está hecha.** Tesoro (ingreso por población, factor de tasas, eficiencia, gasto del presupuesto), tributo entre altépetl y agravio por tributo, impuesto, gobernador, identidad y distancia salen del prototipo HTML. Sus fórmulas viven en `Reglas.Formulas` con los nombres del prototipo, y `hito_0/tablas/generar.mjs` las convierte en `test/tablas_hito0.json`, que las pruebas de Haskell comparan. El 0a se dio por cumplido el 31 de octubre de 2026 (V5, *El criterio del hito 0*): no queda parte manual pendiente. La prueba con otra persona (0b) está diferida. Ver *Pendiente*.

## Estructura

Tres paquetes de cabal. `motor` no sabe nada del juego purépecha y no puede importar `reglas`: cabal lo impide al compilar. Así el motor no depende de reglas que el hito 0 aún no fija. `app` es la cáscara: el ejecutable que junta los dos y habla con el cliente.

```
.
├── cabal.project          # junta los tres paquetes
├── motor.cabal
├── src/Motor/             # paquete motor
├── test/Spec.hs           # pruebas del motor, con el juego de juguete
├── reglas/                # paquete reglas (el juego)
│   ├── reglas.cabal
│   ├── src/Reglas/
│   └── test/Spec.hs
└── app/                   # paquete nucleo: el ejecutable (la cáscara)
    ├── nucleo.cabal
    ├── Main.hs            # socket, reloj, guardado, modo sin cliente
    └── Agente.hs          # agentes externos: proceso, tiempo límite, registro y reproducción
```

Los archivos dorados del protocolo y del espejo viven fuera, en `../pruebas_compartidas/`, porque los leen las pruebas de los dos lados.

### Módulos del motor

| Módulo | Contenido |
| --- | --- |
| `Motor.Base` | Punto fijo (`Fijo`, escala 10 000), `desdeDecimal`, `ln`/`exp` deterministas, ids |
| `Motor.Azar` | SplitMix64 y hash FNV-1a propios; `rng σ sistema tick` sin estado |
| `Motor.Magnitudes` | Monoide `Aporte`, `valorEfectivo`, modificadores con ventana (`activoEn`) y condición (`Condicion`, `cuentaEn`, `valorEn` con los vigentes del derivado, `evaluarCondicion`), alta (`agregarModificador`) y vencimiento (`expirar`) |
| `Motor.Hechos` | El tipo `Hecho` |
| `Motor.Mapa` | Mapa como grafo, proveedor hexagonal (cada conexión mide la escala del mapa en km, tanto de longitud como de costo) y `validarMapa` (también rechaza costos negativos) |
| `Motor.Recorrido` | Recorridos multifuente: el grafo compacto (`grafoDe`), Dijkstra con etiquetas lexicográficas y cola por cubetas en `ST` (`propagarGrafo`), la misma propagación sobre mapas persistentes para reparar (`propagar`), y `asignarCeldas` (a qué asentamiento trabaja cada celda, empate por id, dentro de `R_prod`) |
| `Motor.Influencia` | La influencia en el semianillo tropical: potencial π = −λ ln F, las dos mejores facciones por celda, umbral de tierra de nadie, `duenoDe`, y `actualizarInfluencia`, que repara si cambiaron pocas fuentes y recalcula si cambiaron muchas |
| `Motor.Estado` | `Estado s`, `Persistente s`, `Comun s`, `Derivado s`, `Origen s`; contexto, preguntas y decisiones pendientes |
| `Motor.Sistema` | `Sistema s` con `lee`/`escribe`, cadencias y `correr` |
| `Motor.Juego` | El registro `Juego s c`, `paso` y `pasoDetallado`, la cola de comandos, los agentes, el vencimiento de modificadores, `derivar` y `consultar` |
| `Motor.Vista` | Tipos genéricos del espejo: `Vista`, `EntidadVista`, `Cambios`; `EntidadJuego` con su dueño y sus campos perezosos, e `Interes` (qué detalle pidió el cliente) |
| `Motor.Proyeccion` | `proyeccion` (con todo el detalle) y `proyeccionCon` (con el que pide el cliente), `proyeccionIncremental` (la vista de un estado hecha sobre la del anterior, proyectando solo las entidades sucias y sus dueños), `cambiarInteres`, `cambios` y su referencia `cambiosRef`, `aplicar` y `diferencias` (lo que muestra una predicción) |
| `Motor.Compartido` | `clavesCambiadas`: las claves que difieren entre dos mapas persistentes, saltando los subárboles que comparten |
| `Motor.Carga` | Carga de datos con errores acumulados, versión de esquema, compilación de eventos, `validarOrdenSistemas` |
| `Motor.Efectos` | Efectos compilados (`Programa`) y su intérprete con suspensión y reanudación |
| `Motor.Agentes` | Agente nulo y agente aleatorio |
| `Motor.Guardado` | `guardar` y `cargar` con el origen del derivado. El guardado lleva `versionGuardado` (hoy 2): `cargar` rechaza otra versión con `ErrorVersion` y un aviso que dice qué pasó, porque no hay migraciones (V5, *Guardado*) |
| `Motor.Poblacion` | Crecer con resto y migrar con resto, repartiendo por mayor resto |
| `Motor.Calendario` | Calendario interno como dato del escenario (periodos y días fuera de periodo: veintenas y nemontemi en el prototipo, meses o semanas en otra época) y calendario visible (juliano, gregoriano o el cambio entre los dos) |
| `Motor.Guion` | El guion del escenario como dato: condiciones, fases (actos), situaciones con su tipo, parámetros del director, `Entorno` y `cargarGuion` con errores acumulados |
| `Motor.Director` | Avance de fases, fuentes de presión (`intensidad`), el director (espaciado, tensión, variedad, novedad, plazos), `responderDecision` y las métricas del hito 0 (`metricas`, `cumpleVariedad`) |
| `Motor.Terrenos` | La tabla de terrenos como dato (`datos/terrenos.json`): capacidad, recursos, erosión base, rendimiento y trabajadores, materiales de obra y costo de movimiento de cada terreno; `cargarTerrenos` acumula errores, `validarTerrenosDelMapa` rechaza un mapa con un terreno sin declarar y `conCostoDeTerreno` pone a cada conexión su costo, longitud × (μ(a) + μ(b)) / 2. Valores de relleno hasta el hito 0 |
| `Motor.Moneda` | Bienes como dato (`cargarEconomia`), precio por escasez (`precioBien`), `designarMoneda`, nivel de precios, `costoEnMoneda` e inflación anual (`inflacionDe`); `pasoMoneda` anota el precio de cada moneda al empezar el periodo. Lee `bien.<id>.existencias` y `bien.<id>.produccion`; escribe `moneda.precio`, `moneda.nivel_precios` y `moneda.inflacion` |
| `Motor.Autoridad` | Ejes de poder como dato (`cargarEjes`, `ejesActivos`) y el requisito de autoridad de cada comando (`Requisito`, por omisión `{eje: todo, clase: exclusivo}`). En el prototipo no rechaza nada |
| `Motor.Protocolo` | Mensajes entre núcleo y cliente con nombres JSON explícitos, versión y reglas de compatibilidad |

### Módulos de las reglas

| Módulo | Contenido |
| --- | --- |
| `Reglas.Estado` | `Purepecha`: altépetl, pops, personajes, facción, tasas, presupuesto |
| `Reglas.Constantes` | Constantes de balance y fórmulas de agravio (provisionales) |
| `Reglas.Comando` | Comandos del juego, su forma JSON y su declaración para el catálogo del cliente |
| `Reglas.Sistemas` | Recaudación, pago del presupuesto y evolución del agravio |
| `Reglas.Fusion` | Fusión de pops pequeños (sección 12): cada veintena, un pop de menos de `FUSION_TAMANO` se funde con el mayor compatible de su clave, con media ponderada de gradiente, lealtad y magnitudes |
| `Reglas.Escenario` | Estado inicial de 1475, mapa provisional de 14 × 10 y fecha de inicio (provisionales) |
| `Reglas.Edificios` | Edificios como dato (`datos/edificios.json`, `cargarEdificios` con errores acumulados): costo en valor, duración mínima, trabajo, materiales y cuadrilla máxima; culto (tradición, nivel, capacidad, sacerdotes) y fórmula de beneficio de cada modificador. `iniciarObra` (`construir_edificio`) cobra el valor, retira la cuadrilla y rechaza sin daño. El sistema `construccion` sostiene la cuadrilla con la partida de obras, extrae los materiales de las celdas del altépetl, trabaja, termina la obra y recalcula cada veintena un modificador por tipo de edificio, altépetl y magnitud con fuente `edificio`. `derivarFieles` (paso 16) reparte a los pops entre los templos locales de su tradición y suma los fieles de cada centro ceremonial con peso por distancia |
| `Reglas.Produccion` | Producción de bienes por territorio (sección 12): el derivado del paso 16 dice qué celdas trabaja cada altépetl (`asignarCeldas` dentro de `RADIO_PRODUCCION_KM`), ordenadas por rendimiento por trabajador; la fórmula `produccionCeldas` llena primero las mejores con los trabajadores del altépetl (el factor escaso) y la magnitud `produccion` del altépetl aplica las obras. El sistema `produccion` (paso 6) escribe `bien.<id>.produccion` de la facción y lo suma a `bien.<id>.existencias`. Los bienes son los del rendimiento de `datos/terrenos.json` |
| `Reglas.Grupos` | Grupos de poder como dato (`datos/grupos.json`, `cargarGrupos` con errores acumulados), sus magnitudes `faccion.grupo.<id>.poder` y `.lealtad`, y los nombramientos: nombrar añade modificadores sin fin con fuente `nombramiento`, y destituir o reemplazar los quita con `modificador_terminado` (razón `fuente`). `conGrupos` escribe las bases del tipo de facción y los nombramientos con que empieza el escenario |
| `Reglas.Juego` | El `Juego Purepecha Comando` que conecta todo con el motor (`juegoCon` con los grupos; `juego` sin ellos) |

## Compilar y probar

Requisitos: GHC 9.4 (probado con 9.4.7) y cabal. Dependencias: `aeson`, `scientific`, `containers`, `text`, `bytestring`, `network`; para las pruebas, `hspec`, `QuickCheck` y `aeson-pretty`.

```sh
cabal build all
cabal test all
cabal run nucleo -- --puerto 4646
```

Las pruebas del motor leen los archivos dorados de `../pruebas_compartidas/`. Si un cambio del protocolo es deliberado, se regeneran con `REGENERAR_DORADOS=1 cabal test motor` y se revisa el diff antes de confirmarlo: ese diff es exactamente lo que verá el cliente.

Sin acceso a Hackage, con los paquetes ya instalados en GHC, se puede compilar con `Setup.hs`:

```sh
runghc Setup.hs configure --user --enable-tests
runghc Setup.hs build && runghc Setup.hs test
runghc Setup.hs register --inplace
cd reglas
runghc Setup.hs configure --user --enable-tests --package-db=../dist/package.conf.inplace
runghc Setup.hs build && runghc Setup.hs test
runghc Setup.hs register --inplace
cd ../app
runghc Setup.hs configure --user --package-db=../dist/package.conf.inplace --package-db=../reglas/dist/package.conf.inplace
runghc Setup.hs build      # el ejecutable queda en app/dist/build/nucleo/nucleo
```

La biblioteca del motor se compila con `-Wall -Werror`: un aviso es un error.

## El juego de juguete

Vive en `test/Spec.hs`. Son aldeas con población y descontento, tres sistemas (cosecha, impuesto, migración) y cuatro comandos. Existe para probar el motor con un juego que no es el nuestro, pasando por las rutas que más fallan:

| Ruta | Pruebas |
| --- | --- |
| Veintenas, nemontemi y comandos | `calendario en el ciclo`, `comandos del juguete`, `rechazo de comando invalido` |
| Efecto suspendido | `suspensión y reanudación`, `efectos compilados al cargar` |
| Guardar con una decisión pendiente, a mitad de veintena | `guardar y cargar`, `ley del derivado a mitad de veintena` |
| Restos | `ruta: población con restos` |
| Modificador que expira | `ruta: modificador que expira` |
| Fases, director y plazos | `guion: fases`, `guion: director`, `guion: responder`, `guion: métricas del hito 0 como prueba permanente` |
| Cambio de proyección | `espejo`, `cambios ≡ cambiosRef; proyección incremental ≡ completa`, `clavesCambiadas` |

## Convenciones

**Determinismo.** Misma semilla y mismos comandos dan la misma partida, en cualquier máquina.
- Nada de `Double` en el estado: todo número que afecta la partida es `Fijo` o entero.
- El azar sale de `rng σ nombre tick`; nunca de `IO`.
- Los mapas se recorren en orden de clave; los empates se rompen por id.
- Un valor dorado del generador (`azar estable`) detecta si cambia entre compiladores o máquinas.

**Punto fijo.** `Fijo 10000` es 1,0. Los operadores `.+.`, `.-.`, `.*.` y `./.` tienen las precedencias de `+` y `*`. Las constantes se leen con `desdeDecimal`, que rechaza más de cuatro decimales en vez de redondear en silencio. Un entero de unidades completas se convierte con `desdeEntero` (40 es 40,0, no 0,0040).

**Calendario.** El motor no sabe qué es una veintena. El escenario declara su calendario interno (`CalendarioInterno`: nombre y longitud de los periodos, cuántos hay por año, días fuera de periodo) y su calendario visible. Los sistemas de cadencia `Periodo` corren el primer día de cada periodo y nunca fuera de periodo; los de cadencia `Anual`, el día 0 del año interno. El cliente recibe el calendario en el catálogo y nombra los periodos con él.

**Reloj.** `estadoTick` es el último tick procesado: después de `paso … (Tick t) …`, el estado está en el tick `t`. La cáscara lleva aparte el tick que corre a continuación; un comando que llega en pausa durante el tick T se sella para el T+1.

**Protocolo.** Toda la forma del JSON que viaja por el socket vive en `Motor.Protocolo` (y la de los comandos del juego en `Reglas.Comando`), escrita a mano. Nunca se deriva de los nombres de Haskell: renombrar un campo de Haskell no debe cambiar el cable. Un cambio en el cable se nota porque falla una prueba dorada.

**Magnitudes.** Los sistemas escriben la base o crean y terminan modificadores; nunca el valor efectivo, que se calcula al leerlo. Un modificador cuenta si `inicio ≤ t < fin`. Al empezar el tick de su `fin` se quita del almacén y emite el hecho `modificador_terminado`.

**Funciones totales.** Lo que puede fallar devuelve `Maybe` o `Either`; la carga acumula todos los errores en lugar de parar en el primero.

## Cómo añadir algo

| Quiero añadir | Dónde |
| --- | --- |
| Un sistema | Un valor `Sistema s` en `reglas`, con sus `lee`/`escribe`, y una entrada en `juegoSistemas`. `validarOrdenSistemas` avisa si choca con otro |
| Una magnitud | Una entrada en el catálogo (`juegoCatalogoMag`, y más adelante en `magnitudes.json`). Si dos sistemas la escriben a propósito, marcarla con escritores múltiples |
| Un comando | Un constructor en `Reglas.Comando`, su declaración en `catalogoComandos` (con su requisito de autoridad; en el prototipo, `requisitoPorOmision`) y su caso en `aplicarComando`. Si falla, se rechaza con `Left` sin tocar el estado |
| Un eje de poder | Una entrada en `datos/ejes.json`. El escenario dice cuáles están activos (`ejesActivos1475`; `Nothing` es todos) |
| Un efecto de evento | Un constructor en `Motor.Efectos`, su caso en `parsearEfecto` y en `interpretar` |
| Un acto, o cambiar uno | Una fase en el guion del escenario: fecha o condición de inicio, sistemas activos e intensidades. No se toca código |
| Una situación | Una entrada en `situaciones` del guion, con un tipo del vocabulario. Si el tipo es nuevo, añadirlo a `tipos` |
| Un bien que puede ser moneda | Una entrada en el archivo de bienes (`valor`, `calidad_monetaria`, `referencia`, `elasticidad`, `designable`). El juego escribe sus existencias y su producción como magnitudes de la facción |
| Una fuente de presión | Un sistema pequeño que añade un modificador temporal de valor `intensidad "nombre"`; las fases fijan la intensidad |
| Una ley | Una prueba en `test/Spec.hs`. Si vale para cualquier juego, se escribe sobre `Juego s c` |

## Pendiente

**Pendiente de las reglas:**
- Prueba 0b con una persona que no sea el autor: diferida, no bloquea. Se hace cuando haya algo representativo del acto II (después del 3b o del 4).
- Hito 3, primer corte hecho: eficiencia por altépetl y gobernador (un mal gobernador baja la recaudación y sube el agravio). Obras, etapa 1 de V5, *Las obras*, hecha: yácata, fortaleza, troje y gran yácata con cuadrilla, materiales extraídos de las celdas (piedra en la sierra, madera en el bosque), sustento de la partida de obras, duración mínima y beneficio por fórmula; las yácatas atienden a los fieles purépechas según los sacerdotes del altépetl, y la gran yácata es un centro ceremonial que da legitimidad. El tributo en especie (etapa 2) también está hecho: `pedir_tributo_obra` pide a otro altépetl que envíe un material con su gente; llega con retraso y se cobra su transporte según el costo del grafo. El oficio (etapa 3) también: cada edificio puede pedir un conocimiento con dominio mínimo (el mínimo del codificado y el tácito de la facción); el dominio escala lo que rinde la gente de la obra y cada obra terminada sube el tácito con el logaritmo de las obras hechas. Faltan las obras en celda con control (etapa 4). De la yácata falta la legitimidad (V5 pide un tope por facción, que llega con el culto) y la lealtad (+2 por año en el prototipo; ningún sistema mueve aún la lealtad); de la troje, la subsistencia; de la fortaleza, la fuerza de guerra (hito 4). Faltan mercado y camino, y terrazas y roturación. Producción de bienes por territorio hecha (`--terrenos datos/terrenos.json`): los seis bienes de V5 salen del rendimiento de cada terreno, con trabajadores y radio provisionales. Los bienes todavía no entran al tesoro (eso es la moneda en el juego real), y el tributo en especie entre altépetl no mueve existencias porque estas son de la facción y todos los altépetl son de la misma. Nombramientos de gobernador con grupos de poder: hechos (`nombrar_gobernador`, `destituir_gobernador`). Falta `NombrarCapitan`, el tope de lealtad por legitimidad (paso 16), el aporte de cada grupo a su eje y la protesta como situación del guion.
- Mover el escenario y las constantes a `escenarios/` y `constantes.json`.
- Reclutar ejército (`ReclutarEjercito`) sigue rechazado con `no_implementado`. El prototipo también lo tiene deshabilitado; no hay regla que copiar, así que queda para el hito 4, con la guerra.
- Los rangos de prestigio y legitimidad son provisionales: el prototipo no los acota.

**Huecos conocidos del motor**, que se cierran cuando una mecánica los pida:
- Los agentes reciben una `Proyeccion` vacía; la proyección por facción llega con la IA del hito 4.
- `cambios` usa el registro "todas las entidades"; el registro real de entidades tocadas es del hito 2.
- `paso` recibe el `Entorno` con el mapa, su grafo compacto (construido una vez), el guion y la economía; faltan el catálogo y el desfase del documento funcional.
- A la escala del mapa completo (`--escala 7500x20`), cada tick cuesta unos 0,7 s y la recolección de basura se lleva cerca del 40 %. Lo que más asigna es la proyección diaria de la vista entera: el registro de entidades tocadas es lo que la baja. Agrandar la zona de asignación (`+RTS -A64m`) no ayuda.
- Los programas de eventos aún no se buscan en un registro: quien reanuda pasa el `Programa`.
- Del protocolo faltan los mensajes de batalla (hasta la capa táctica). `decision` ya cubre las situaciones del guion; las crisis la usarán igual.
- La cáscara atiende a un cliente a la vez y a un agente externo a la vez.
- El agente externo ve todo el estado; la vista filtrada por facción llega con la información asimétrica.
- El registro de respuestas del agente no se guarda con la partida: repetir desde una partida cargada exige el registro aparte.
- Guardar y cargar guardan la partida, no el registro de comandos; la repetición desde el registro llega cuando haga falta para depurar.
