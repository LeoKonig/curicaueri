# Tareas para paralelizar el desarrollo

Prompts listos para pegar en distintas IA (Claude Code, otros asistentes con acceso al repositorio, o un asistente con búsqueda web para las tareas de investigación). Cada uno es autosuficiente: dice qué leer, qué archivos puede tocar, qué entregar y cuándo está terminado.

## Cómo usarlos

1. **Pega primero el contexto común** y después el prompt de la tarea.
2. **Una IA por fila de la tabla a la vez.** Las tareas de una misma fila del orden tocan archivos distintos y pueden correr en paralelo. Las que dependen de otra esperan a que esa se fusione en `main`.
3. **Cada tarea termina en un pull request** contra `main`, desde la rama que indica, con la integración continua en verde. Revisa el PR (o pídele a otra IA que lo revise contra `CLAUDE.md`) antes de fusionarlo.
4. **Si una IA no tiene acceso al repositorio,** pídele el código como archivos completos con su ruta y aplícalos tú en una rama. La integración continua hará la verificación.

## Orden y dependencias

| Ronda | Tarea | Área (archivos principales) | Depende de | Hito |
| --- | --- | --- | --- | --- |
| 1 | T1 Condiciones de modificadores | `motor`: `Magnitudes`, `Juego`, `Guion` | — | 3 |
| 1 | T2 Crónica y fin de partida | `motor`: `Estado`, `Protocolo`; `app` | — | 3 / 6 |
| 1 | T3 Asignación de celdas y terrenos | `motor`: `Mapa`; `datos/terrenos.json` | — | 3 |
| 1 | T4 Nombramientos con grupos | `reglas`: `Comando`, `Estado`, `Escenario` | — | 3 |
| 1 | T5 Guion real de 1475 | `datos/guion_1475.json` | — | 0 / 3 |
| 1 | T6 Investigación histórica | `docs/fuentes/` (sin código) | — | 0 |
| 2 | T7 Cliente: crónica y pantalla de fin | `cliente/` | T2 | 3 / 6 |
| 2 | T8 Obras: yácata, fortaleza, troje | `reglas`: `Comando`, `Sistemas` | T4 | 3 |
| 2 | T9 Producción de bienes por territorio | `reglas`: `Sistemas`, `Escenario` | T3 | 3 |
| 3 | T10 Moneda en el juego real | `reglas`: `Comando`, `Sistemas` | T9 | 3 |
| 3 | T11 Arnés del 0a sobre el juego real | `app` (`--sin-cliente`), `docs/` | T5 | 0 |

T4 y T8 tocan `Reglas/Comando.hs`: por eso T8 va en la ronda 2. Si dos PR chocan, el segundo se rebasa sobre `main`.

---

## Contexto común (pegar antes de cada tarea)

```
Trabajas en "Curicaueri: Flor y Canto", un juego de gran estrategia de código abierto
sobre el reino purépecha (1475–1530). Repositorio: https://github.com/LeoKonig/curicaueri

Antes de escribir código, lee completos:
- CLAUDE.md (reglas del repositorio: invariantes, vocabulario, cómo se trabaja)
- docs/arquitectura-prototipoV5.md, las secciones que cite la tarea (qué es el juego)
- docs/arquitectura-funcional.md, las secciones que cite la tarea (cómo se modela)
- nucleo/README.md (módulos, convenciones, cómo añadir algo)

Reglas que no se negocian:
- Todo en español: identificadores, comentarios, commits, documentos.
- El paquete `motor` no importa `reglas`; lo nuevo del motor se prueba con el juego de
  juguete de nucleo/test/Spec.hs.
- Determinismo: Fijo (punto fijo, escala 10 000) o enteros, nunca Double en el estado;
  azar solo con `rng σ nombre tick`.
- Los sistemas escriben la base de una magnitud o crean y terminan modificadores con
  fuente; nunca el valor efectivo. Un escritor por magnitud.
- Todo campo nuevo tiene valor por defecto y los guardados anteriores siguen cargando.
- Nada "por si acaso": cada pieza entra con lo que la usa y con su prueba o su ley.
- Un comando rechazado no cambia el estado y devuelve un motivo legible.
- No inventes nombres: usa los que ya existen en el código y en V5. Si V5 y el código no
  dicen algo que necesitas, detente y pregunta en vez de suponer.

Entrega: una rama `claude/<tema>` desde `main` actualizado, commits pequeños (un commit,
una idea) y un pull request contra `main` que explique qué hace, cómo se probó y qué
quedó pendiente. Compila y prueba con:
  cd nucleo && cabal build all --enable-tests && cabal test all
  (y ./probar_agentes.sh o ./probar_cliente.sh si tocas la cáscara o el cliente)
La tarea no está terminada hasta que la integración continua pasa en verde.
Si cambias una decisión de diseño, actualiza V5 y el documento funcional en el mismo PR.
```

---

## T1. Condiciones de modificadores (motor, hito 3)

```
Tarea: que los modificadores con condición se evalúen. Hoy `Modificador` tiene
`modCondicion :: Maybe Text` (marcado TODO) y `vigentesEn` en Motor.Juego devuelve siempre
el conjunto vacío.

Lee: V5 *Arquitectura de extensión* (modificadores condicionales) y la fila del hito 3 en
*Hitos*; documento funcional, sección 6 (magnitudes), sección 7 (el tick, paso 16) y
sección 11b (el lenguaje de condiciones de Motor.Guion).

Haz:
1. Cambia `modCondicion` a `Maybe Condicion`, reutilizando el tipo `Condicion` de
   Motor.Guion (mueve el tipo a un módulo que ambos puedan importar si hace falta, sin
   ciclos). Nada de un segundo lenguaje de condiciones.
2. `vigentesEn` evalúa las condiciones al derivar (paso 16, al empezar la veintena) y
   devuelve los ids de los modificadores condicionales vigentes. `valorEn`/`valorEfectivo`
   solo cuentan un modificador condicional si está en `derivadoVigentes`.
3. Cuando un condicional deja de cumplirse, emite `modificador_terminado` con razón
   "dejó de cumplirse su condición" sin borrarlo (puede volver a cumplirse; documenta
   la decisión).
4. Guardado: el JSON del modificador acepta la condición y los guardados sin ella cargan.

Pruebas en nucleo/test/Spec.hs con el juego de juguete: un modificador "+10 descontento si
población > 150" cuenta solo cuando se cumple; la ley del derivado a mitad de veintena
sigue pasando; un modificador sin condición se comporta igual que antes.
Rama: claude/condiciones-modificadores. No toques nucleo/reglas.
```

## T2. Crónica y fin de partida (motor, protocolo y cáscara)

```
Tarea: la crónica del reino y un fin de partida mínimo, del lado del núcleo.

Lee: V5 *La crónica del reino*, *Interfaz, IA y fin de partida* y la fila del hito 6;
documento funcional, sección 16 (protocolo) y sección 11b (guion y condiciones).
`Comun` ya tiene `comunCronica :: Seq EntradaCronica`, pero nadie escribe en ella.

Haz:
1. Motor: una función pura que convierta hechos en entradas de crónica según una tabla de
   datos (qué tipos de hecho van a la crónica y con qué clave de texto), llamada en
   `pasoCompleto` después del director. La crónica es de solo añadir.
2. Fin de partida declarado en el guion: un campo opcional `fin` con una fecha y una lista
   de condiciones de derrota en el lenguaje de Motor.Guion. Al cumplirse, hecho
   `fin_partida` con la razón; el estado queda marcado como terminado y `paso` ya no lo
   avanza. Valor por defecto: sin fin (todo lo existente sigue igual).
3. Protocolo (versión 3 si rompe la compatibilidad; si solo añade mensajes, explica por qué
   no hace falta): `cronica` (entradas nuevas, también en el saludo) y `fin` (razón y
   crónica completa). Archivos dorados en pruebas_compartidas/protocolo/.
4. Cáscara (nucleo/app/Main.hs): envía los mensajes nuevos y deja de correr el reloj al
   terminar.

Pruebas: con el juego de juguete y un guion de prueba, la crónica recibe las entradas
esperadas, sobrevive a guardar y cargar, y la partida termina en la fecha o por la
condición. Rama: claude/cronica-fin. El cliente lo hace otra tarea (T7): no toques cliente/.
```

## T3. Asignación de celdas y tabla de terrenos (motor, hito 3)

```
Tarea: asignar cada celda del mapa a un asentamiento (Voronoi sobre el grafo) y cargar la
tabla de terrenos con sus rendimientos, como base de la producción del hito 3.

Lee: V5 *El mapa como grafo*, *La tierra y la gente* (capacidad por terreno) y *Población,
asentamientos y territorio*; documento funcional, secciones 8 (mapa como grafo), 9
(influencia) y 12 (economía y población).

Haz:
1. En Motor.Mapa: `asignarCeldas :: Mapa -> [(IdAsentamiento, Celda)] -> Map Celda IdAsentamiento`
   con Dijkstra multifuente sobre el costo de las conexiones; empates por id del
   asentamiento. Es derivado: no se guarda.
2. datos/terrenos.json: capacidad base, recursos y erosión base por terreno (valores de
   relleno marcados como tales), con su carga validada y errores acumulados.
3. Ley con QuickCheck: el resultado del Dijkstra coincide con el mínimo por fuerza bruta en
   mapas pequeños (ya es una ley del documento funcional, sección 19).

No escribas la producción (eso es T9, en reglas). Rama: claude/celdas-terrenos.
```

## T4. Nombramientos con grupos (reglas, hito 3)

```
Tarea: los comandos NombrarGobernador y DestituirGobernador, con el efecto sobre los grupos
de poder.

Lee: V5 *Los nombramientos mueven poder*, *Política interna: grupos, consejo y reformas*,
*Catálogo de comandos* y *Una veintena en la vida del cazonci*; documento funcional,
sección 14d (fórmula de nombramientos). En reglas ya existen el gobernador por altépetl
(`altGobernador`) y la eficiencia que depende de él (Reglas.Formulas.eficienciaDe).

Haz:
1. `Personaje` gana `perGrupo :: Maybe Text` (valor por defecto Nothing; los ids de grupo
   son nobleza_guerrera, administradores, sacerdocio, mercaderes).
2. Comandos `nombrar_gobernador {altepetl, personaje}` y `destituir_gobernador {altepetl}`
   en Reglas.Comando, con nombres JSON escritos a mano y su archivo dorado. Rechazos
   legibles: personaje muerto, ya gobierna otro altépetl, altépetl inexistente.
3. Efecto: modificadores constantes de poder y lealtad del grupo del nombrado, y de
   lealtad negativa para los grupos que pretenden el cargo (declarados en datos), con
   fuente `nombramiento:<personaje>:<altepetl>`; al destituir o reemplazar se cancelan con
   `modificador_terminado`. Las magnitudes de grupo son `faccion.grupo.<id>.poder` y
   `faccion.grupo.<id>.lealtad`; si aún no existen, créalas en el escenario con la base
   de V5 para "reino centralizado".
4. El escenario de 1475 asigna grupos a sus personajes.

Pruebas en nucleo/reglas/test: nombrar sube el poder del grupo y lo mantiene constante
(sin trinquete); destituir lo devuelve a la base; un mal gobernador sigue bajando la
recaudación. Rama: claude/nombramientos.
```

## T5. Guion real de 1475 (datos)

```
Tarea: reemplazar el guion ilustrativo datos/guion_1475.json por uno construido con las
decisiones recurrentes del prototipo del hito 0.

Lee: V5 *Decisiones recurrentes*, *Actos modulares* y *Una veintena en la vida del cazonci*;
documento funcional, sección 11b; hito_0/datos/eventos.json (rebaja, autonomía, excedente,
capitán, cosecha, refugiados, moroso, heredero) y hito_0/datos/crisis.json.

Haz:
1. Una situación por evento del hito 0, con su tipo del vocabulario cerrado, sus fases,
   su condición en el lenguaje de Motor.Guion sobre magnitudes que existen hoy en reglas
   (agravio de pops, tesoro, legitimidad, prestigio…) y opciones cuyos efectos usen los
   efectos que ya existen en Motor.Efectos.
2. Si un evento necesita una magnitud o un efecto que no existe, no lo inventes: anótalo
   en la descripción del PR como pendiente.
3. Comprueba el criterio del hito 0 con el arnés:
     nucleo --sin-cliente --ticks 18250 --guion datos/guion_1475.json --metricas
   y escalona los tipos dentro de cada acto hasta que `cumple_criterio` sea true.

Rama: claude/guion-1475. Solo toca datos/guion_1475.json y, si hace falta, docs/.
```

## T6. Investigación histórica (sin código; asistente con búsqueda web)

```
Contexto: diseño un juego de estrategia sobre el reino purépecha (Michoacán) entre 1475 y
1530. Necesito datos con fuentes verificables para fijar parámetros del juego. Para cada
afirmación da la fuente (autor, obra, año, página si es posible) y marca el grado de
certeza. Si las fuentes discrepan, muestra las posturas. No inventes citas.

Preguntas:
1. Sucesos documentados de 1485 a 1519 en Michoacán y su frontera (guerras con la Triple
   Alianza, campañas en la frontera chichimeca y otomí, sucesiones, epidemias, sequías,
   rebeliones), con fecha o ventana de años y fuente. Fuente principal esperada: la
   *Relación de Michoacán*; contrasta con Pollard (*Taríacuri's Legacy*), Warren, Roskamp.
2. Medios de pago en el reino purépecha: ¿circulaban mantas, cacao, hachas de cobre (las
   "hachas-moneda" del Occidente de México, Hosler) u otros como moneda o medio de cambio?
   ¿Qué se tributaba y en qué especie?
3. Estimaciones de población hacia 1520 de Tzintzuntzan, Pátzcuaro, Ihuatzio, Zacapu,
   Uruapan y Taximaroa, y del reino entero, con su rango.
4. Organización política: ¿cómo nombraba el cazonci a los señores locales y gobernadores?
   ¿Qué grupos (nobleza guerrera, sacerdotes, mercaderes, administradores) tenían poder y
   cómo se manifestaba?
5. Cronología de la llegada de los franciscanos a Michoacán (1525–1530) y del vasallaje del
   cazonci Tangáxoan II.

Entrega: un documento en Markdown por pregunta, listo para guardar en docs/fuentes/.
```

## T7. Cliente: crónica y pantalla de fin (Godot, después de T2)

```
Tarea: mostrar en el cliente Godot la crónica y el fin de partida que envía el núcleo
(mensajes `cronica` y `fin`, ya con archivos dorados en pruebas_compartidas/protocolo/).

Lee: V5 *Cliente: el mapa como atlas*, *La crónica del reino* e *Interfaz, IA y fin de
partida*; cliente/principal.gd, cliente/red/espejo.gd, cliente/ui/panel_decisiones.gd
(como modelo de panel genérico) y cliente/pruebas/.

Haz:
1. El espejo guarda la crónica; una pestaña "Crónica" la muestra con fecha y texto, la más
   reciente arriba, y se marca con un punto al recibir entradas nuevas (sin pausar).
2. Al recibir `fin`, una pantalla final con la razón y la crónica completa, y un botón para
   volver a cargar una partida.
3. Pruebas sin interfaz: prueba_protocolo.gd lee los dorados nuevos; una prueba de
   integración con el núcleo lanzado con un guion de fin cercano llega a la pantalla final.
   Actualiza probar_cliente.sh.

Tiene que funcionar con Godot 4.3 y 4.7.2. Rama: claude/cliente-cronica-fin.
```

## T8. Obras: yácata, fortaleza y troje (reglas, después de T4)

```
Tarea: construir obras con costo en tesoro y veintenas de obra, como en el prototipo del
hito 0 (hito_0/datos/acciones.json: construir_yacata, construir_fortaleza, construir_troje).

Lee: V5 *Arquitectura de extensión* (el ejemplo de la yácata), *Las palancas* (Construcción),
*El costo de las cosas* y la fila del hito 3 en *Hitos*; documento funcional, sección 14h.

Haz:
1. Comando `construir {obra, altepetl}`; la obra en curso es estado persistente con su
   veintena de término; al terminar, hecho `edificio_terminado` y modificadores
   permanentes con fuente (yácata: legitimidad y lealtad; fortaleza: defensa; troje:
   reserva), con los valores del prototipo del hito 0.
2. El costo se cobra al empezar; se rechaza sin daño si no alcanza el tesoro; la consulta
   de predicción muestra el costo.
3. El costo ya trae el campo `insumos` vacío por defecto (sección 14h): no lo uses todavía.

Pruebas: una obra cambia la magnitud prevista y el desglose nombra la obra; guardar a mitad
de una obra y cargar sigue igual. Rama: claude/obras.
```

## T9. Producción de bienes por territorio (reglas, después de T3)

```
Tarea: que cada altépetl produzca bienes según las celdas que le asigna T3 y su terreno, y
que la facción lleve sus existencias, según el contrato de V5 *La moneda designada y la
inflación* (decisión 2) y CLAUDE.md (bienes como magnitudes de la facción).

Lee: V5 *La tierra y la gente*, *Población, asentamientos y territorio*, *Modelo de datos*
(Bien); documento funcional, sección 12 (producción con el factor escaso).

Haz:
1. Un sistema de producción en el paso 6 (cadencia de veintena), único escritor de
   `bien.<id>.produccion` de la facción y que suma a `bien.<id>.existencias`, con los seis
   bienes de V5 (maíz, pescado, sal, cobre, mantas, obsidiana).
2. Producción con el factor escaso (trabajadores y capacidad), con fórmulas con nombre y
   constantes en Reglas.Constantes, marcadas como provisionales.
3. El tributo en especie entre altépetl mueve existencias, si el modelo actual de tributo
   lo permite; si no, déjalo anotado.

Pruebas: producción monótona (añadir una celda o un trabajador nunca la baja: ley de la
sección 19); las existencias no bajan de 0. Rama: claude/produccion-bienes.
```

## T10. Moneda en el juego real (reglas, después de T9)

```
Tarea: conectar Motor.Moneda al juego real.

Lee: V5 *La moneda designada y la inflación* (las tres decisiones); documento funcional,
sección 14g; nucleo/src/Motor/Moneda.hs y sus pruebas en nucleo/test/Spec.hs.

Haz:
1. datos/bienes_1475.json con los seis bienes; mantas y cobre designables (parámetros
   marcados como provisionales, por verificar con fuentes); `magnitudes_nominales`:
   ["tesoro"]. La cáscara lo carga en el Entorno con una opción `--bienes`.
2. Comando `designar_moneda {bien | null}` que llama a `designarMoneda`.
3. La hacienda pasa sus ingresos por `enCuenta` y los comandos con costo cobran con
   `enCuenta`, para que el tesoro quede en la moneda.

Pruebas: designar y retirar la moneda conserva el valor del tesoro; con existencias
crecientes de la moneda, la inflación es positiva y el valor real del tesoro guardado baja.
Rama: claude/moneda-reglas.
```

## T11. Arnés del 0a sobre el juego real (después de T5)

```
Tarea: medir automáticamente el criterio 0a del hito 0 sobre el juego real, sin cliente.

Lee: V5, fila del hito 0 en *Hitos* y *El contrato de entrega del hito 0*; documento
funcional, sección 20 (fila del hito 0: medición separada del juicio); la opción
`--sin-cliente --metricas` de nucleo/app/Main.hs.

Haz:
1. Un agente de reglas simple (por ejemplo, en Python en agentes/) que juegue 10 años
   tomando decisiones razonables, y una medición que cuente decisiones con costo y
   consecuencia visible, y decisiones que cambian el rumbo (por las diferencias entre
   estados, con umbrales en datos, no en código).
2. Un informe en JSON y un resumen en docs/ con el resultado contra el criterio:
   ≥ 15 decisiones con costo en 10 años, ≥ 3 que cambian el rumbo.

Rama: claude/arnes-0a. No cambies las reglas para que pase: si no pasa, el informe lo dice.
```
