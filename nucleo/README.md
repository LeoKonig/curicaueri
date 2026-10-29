# Curicaueri: Flor y Canto — núcleo del juego (motor y reglas)

Núcleo en Haskell de *Curicaueri: Flor y Canto*, juego de gran estrategia sobre Mesoamérica (prototipo: el reino purépecha, 1475–1530). El núcleo decide todo el estado del juego; el cliente en Godot solo dibuja y captura la entrada.

Este código implementa dos documentos de diseño, que conviene leer antes de tocarlo:

| Documento | Qué dice |
| --- | --- |
| `arquitectura-prototipoV5.md` | **Qué** es el juego: mecánicas, palancas, hitos y criterios |
| `arquitectura-funcional.md` | **Cómo** se modela: tipos, ecuaciones y leyes. Las secciones citadas en el código ("sección 12") son de este documento |

## Estado

**Hito 1a (motor): criterio mínimo cumplido.** El motor corre con un juego de juguete que pasa por las seis rutas difíciles, y las leyes del criterio se comprueban con pruebas automáticas (170 pruebas en el motor, incluidas las de los archivos dorados y las del guion; 7 en las reglas).

**Actos modulares: en el motor.** Guion con fases, situaciones con vocabulario de tipos cerrado y director (`Motor.Guion`, `Motor.Director`), conectados al paso, al guardado y al protocolo, y probados con el juego de juguete y su guion (`test/guion_juguete.json`), incluida la prueba de métricas del hito 0. El guion del escenario es ilustrativo hasta el hito 0.

**Hito 2 (protocolo y atlas): cerrado, salvo calibrar las velocidades jugando.** Protocolo con nombres JSON explícitos y archivos dorados; cáscara con socket, reloj y velocidades configurables; consulta (predicción hasta la siguiente veintena); guardar y cargar; cliente en Godot con mapa, paneles genéricos, informe de veintena y medidor de tiempo en pausa. El criterio de 2 700 hexágonos a 60 FPS se cumple con margen en una NVIDIA MX150 (percentil 99 de 7,2 ms). Falta calibrar las velocidades jugando (ver `../docs/calibrar.md`).

**Agentes externos: verificados en Python y Mercury.** Los dos responden igual a los casos compartidos y la partida con cualquiera de ellos es idéntica.

**Hito 1b (reglas): la parte del 0a que da las fórmulas está hecha.** Tesoro (ingreso por población, factor de tasas, gasto del presupuesto), tributo entre altépetl y agravio por tributo, impuesto, identidad y distancia salen del prototipo HTML. Sus fórmulas viven en `Reglas.Formulas` con los nombres del prototipo, y `hito_0/tablas/generar.mjs` las convierte en `test/tablas_hito0.json`, que las pruebas de Haskell comparan. Lo que sigue pendiente del 0a es la parte que no se automatiza: las partidas con la rúbrica de decisiones y la auditoría de qué decisiones cambian el rumbo. Ver *Pendiente*.

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
| `Motor.Magnitudes` | Monoide `Aporte`, `valorEfectivo`, modificadores con ventana (`activoEn`, `valorEn`), alta (`agregarModificador`) y vencimiento (`expirar`) |
| `Motor.Hechos` | El tipo `Hecho` |
| `Motor.Mapa` | Mapa como grafo, proveedor hexagonal, `validarMapa` |
| `Motor.Estado` | `Estado s`, `Persistente s`, `Comun s`, `Derivado s`, `Origen s`; contexto, preguntas y decisiones pendientes |
| `Motor.Sistema` | `Sistema s` con `lee`/`escribe`, cadencias y `correr` |
| `Motor.Juego` | El registro `Juego s c`, `paso` y `pasoDetallado`, la cola de comandos, los agentes, el vencimiento de modificadores, `derivar` y `consultar` |
| `Motor.Vista` | Tipos genéricos del espejo: `Vista`, `EntidadVista`, `Cambios` |
| `Motor.Proyeccion` | `proyeccion`, `cambiosRef`, `cambiosOpt`, `aplicar` y `diferencias` (lo que muestra una predicción) |
| `Motor.Carga` | Carga de datos con errores acumulados, versión de esquema, compilación de eventos, `validarOrdenSistemas` |
| `Motor.Efectos` | Efectos compilados (`Programa`) y su intérprete con suspensión y reanudación |
| `Motor.Agentes` | Agente nulo y agente aleatorio |
| `Motor.Guardado` | `guardar` y `cargar` con el origen del derivado |
| `Motor.Poblacion` | Crecer con resto y migrar con resto, repartiendo por mayor resto |
| `Motor.Calendario` | Calendario interno como dato del escenario (periodos y días fuera de periodo: veintenas y nemontemi en el prototipo, meses o semanas en otra época) y calendario visible (juliano, gregoriano o el cambio entre los dos) |
| `Motor.Guion` | El guion del escenario como dato: condiciones, fases (actos), situaciones con su tipo, parámetros del director, `Entorno` y `cargarGuion` con errores acumulados |
| `Motor.Director` | Avance de fases, fuentes de presión (`intensidad`), el director (espaciado, tensión, variedad, novedad, plazos), `responderDecision` y las métricas del hito 0 (`metricas`, `cumpleVariedad`) |
| `Motor.Autoridad` | Ejes de poder como dato (`cargarEjes`, `ejesActivos`) y el requisito de autoridad de cada comando (`Requisito`, por omisión `{eje: todo, clase: exclusivo}`). En el prototipo no rechaza nada |
| `Motor.Protocolo` | Mensajes entre núcleo y cliente con nombres JSON explícitos, versión y reglas de compatibilidad |

### Módulos de las reglas

| Módulo | Contenido |
| --- | --- |
| `Reglas.Estado` | `Purepecha`: altépetl, pops, personajes, facción, tasas, presupuesto |
| `Reglas.Constantes` | Constantes de balance y fórmulas de agravio (provisionales) |
| `Reglas.Comando` | Comandos del juego, su forma JSON y su declaración para el catálogo del cliente |
| `Reglas.Sistemas` | Recaudación, pago del presupuesto y evolución del agravio |
| `Reglas.Escenario` | Estado inicial de 1475, mapa provisional de 14 × 10 y fecha de inicio (provisionales) |
| `Reglas.Juego` | El `Juego Purepecha Comando` que conecta todo con el motor |

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
| Cambio de proyección | `espejo`, `cambiosOpt ≡ cambiosRef` |

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
| Una fuente de presión | Un sistema pequeño que añade un modificador temporal de valor `intensidad "nombre"`; las fases fijan la intensidad |
| Una ley | Una prueba en `test/Spec.hs`. Si vale para cualquier juego, se escribe sobre `Juego s c` |

## Pendiente

**Antes de seguir con las reglas:**
- Hacer la parte del 0a que no se automatiza: partidas jugadas con la rúbrica de decisiones y la auditoría de qué decisiones cambian el rumbo. Las fórmulas y sus tablas ya están (`hito_0/tablas/generar.mjs`).
- Territorio y eficiencia: el ingreso por territorio, el gobernador y los edificios necesitan el mapa con rendimientos. Hasta entonces el tesoro solo cuenta la población.
- Convertir tesoro, prestigio y legitimidad en magnitudes. Mientras el tesoro sea un campo, `validarOrdenSistemas` no ve que recaudación y pago lo escriben los dos.
- Mover el escenario y las constantes a `escenarios/` y `constantes.json`.

**Huecos conocidos del motor**, que se cierran cuando una mecánica los pida:
- Las condiciones de los modificadores no se evalúan (`vigentesEn` devuelve vacío hasta el hito 3).
- Los agentes reciben una `Proyeccion` vacía; la proyección por facción llega con la IA del hito 4.
- `cambios` usa el registro "todas las entidades"; el registro real de entidades tocadas es del hito 2.
- `paso` recibe el `Entorno` con el mapa y el guion; faltan el catálogo y el desfase del documento funcional.
- Los programas de eventos aún no se buscan en un registro: quien reanuda pasa el `Programa`.
- Del protocolo faltan los mensajes de batalla (hasta la capa táctica). `decision` ya cubre las situaciones del guion; las crisis la usarán igual.
- La cáscara atiende a un cliente a la vez y a un agente externo a la vez.
- El agente externo ve todo el estado; la vista filtrada por facción llega con la información asimétrica.
- El registro de respuestas del agente no se guarda con la partida: repetir desde una partida cargada exige el registro aparte.
- Guardar y cargar guardan la partida, no el registro de comandos; la repetición desde el registro llega cuando haga falta para depurar.
