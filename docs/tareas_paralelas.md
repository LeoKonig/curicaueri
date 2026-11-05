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
| 1 | T5 Guion real de 1475 (hecha en `claude/guion-1475`) | `datos/guion_1475.json` | — | 0 / 3 |
| 1 | T6 Investigación histórica | `docs/fuentes/` (sin código) | — | 0 |
| 2 | T7 Cliente: crónica y pantalla de fin | `cliente/` | T2 | 3 / 6 |
| 2 | T8 Obras: yácata, fortaleza, troje | `reglas`: `Comando`, `Sistemas` | T4 | 3 |
| 2 | T9 Producción de bienes por territorio | `reglas`: `Sistemas`, `Escenario` | T3 | 3 |
| 3 | T10 Moneda en el juego real (hecha en `claude/moneda-reglas`) | `reglas`: `Comando`, `Sistemas` | T9 | 3 |
| 3 | T11 Arnés del 0a sobre el juego real | `app` (`--sin-cliente`), `docs/` | T5 | 0 |

T4 y T8 tocan `Reglas/Comando.hs`: por eso T8 va en la ronda 2. Si dos PR chocan, el segundo se rebasa sobre `main`.

**Estado al 1 de noviembre de 2026.** Hechas: T1, T3, T4, T8 y T9. T2 (núcleo: PR #34) y T7 (cliente: PR #35) están en revisión; el contenido del cierre de 1607 está en `datos/cierre_1607.json`. T10 (moneda en el juego real) está en revisión en `claude/moneda-reglas`, y la merma de los bienes encima, en `claude/merma-bienes`. Pendientes del hito 3: T11, y camino, terrazas, roturación y mercado parcial (sin prompt todavía). T5 queda como el guion del **tutorial** 1475–1530. T6 se reemplaza por el inventario de 1418 (abajo).

**Ronda 4: la campaña 1418–1607** (V5, *Alcance* y la tabla nueva de *Hitos*). T12, T14, T15 y T6 tocan áreas distintas y pueden correr en paralelo; T13 espera a T12.

| Ronda | Tarea | Área (archivos principales) | Depende de | Hito |
| --- | --- | --- | --- | --- |
| 4 | T12 Varias facciones en las reglas (hecha en `claude/varias-facciones`; falta fusionar) | `reglas`: `Estado`, `Juego`, `Sistemas`, `Comando`, `Facciones` | — | 4 |
| 4 | T13 Escenarios como datos y campaña 1418 de juguete (hecha en `claude/escenarios-datos`) | `escenarios/`, `datos/facciones/`, `reglas`: `Escenario`; `app` | T12 | 4 |
| 4 | T14 Condiciones y efectos nuevos (hecha en `claude/condiciones-efectos`) | `motor`: `Magnitudes`, `Guion`, `Efectos`, `Propios`; `reglas`: `Propios` | — | 4 |
| 4 | T15 Herramienta de mapa | `herramientas/mapa/` (Python) | — | 5 |
| 4 | T6 Inventario histórico de 1418 | `docs/fuentes/` (sin código) | — | 10 |

**Ronda 5: la economía de la escasez** (después de T10 y de la merma de los bienes, rama `claude/merma-bienes`). La merma acota las existencias; lo que sigue es que la escasez tenga estación y que la troje sirva para algo. T16 no depende de la ronda 4; T17 espera a T16, a T5 y a T14.

| Ronda | Tarea | Área (archivos principales) | Depende de | Hito |
| --- | --- | --- | --- | --- |
| 5 | T16 Cosecha por estación y merma con troje (hecha en `claude/cosecha-estacion`) | `motor`: `Moneda`; `reglas`: `Produccion`, `Constantes`; `datos/terrenos.json`, `datos/edificios.json` | merma | 3 |
| 5 | T17 Mala cosecha y abrir las trojes (hecha en `claude/mala-cosecha`) | `reglas`: `Produccion`, efectos propios; `datos/guion_1475.json` | T16, T5, T14 | 3 / 10 |

**Ronda 6: coerción, diplomacia e IA sencilla** (hito 7 de V5). Todas esperan a T13 y T14: sin varias facciones con altépetl y sin los efectos de transferir un altépetl y absorber una facción, la guerra no tiene sobre qué correr. Se adelanta al hito 6 (demografía) porque es lo que da decisiones al jugador sin eventos escritos; si se confirma el cambio de orden, se anota en la tabla de *Hitos* de V5. T18 y T21 pueden correr en paralelo; T19 espera a T18; T20 y T22 a T19 y T21; T23 cierra el hito.

| Ronda | Tarea | Área (archivos principales) | Depende de | Hito |
| --- | --- | --- | --- | --- |
| 6 | T18 Ejércitos, leva y movimiento | `reglas`: `Estado`, `Comando`, `Sistemas`, `Produccion` | T13, T14 | 7 |
| 6 | T19 Guerra: casus belli, combate, tregua y paz | `reglas`: `Formulas`, `Comando`, `Sistemas`, `Constantes` | T18 | 7 |
| 6 | T20 Abasto, deserción, motín y asedio | `reglas`: `Sistemas`, `Constantes`; `cliente/` (ruta en rojo) | T19 | 7 |
| 6 | T21 Vínculos entre facciones y propuestas | `reglas`: `Estado`, `Comando`; `motor`: decisiones pendientes | T13, T14 | 7 |
| 6 | T22 IA sencilla: planificador, ejecutor y personalidades | `reglas`: agente; `datos/personalidades/`; `app` | T19, T21 | 7 |
| 6 | T23 Rebeliones, incursiones, saqueo, requisa y guerra ritual | `reglas`: `Sistemas`, `Comando`; `datos/facciones/` | T20, T22 | 7 |

**Ronda 7: comer antes de tributar** (V5, *Comer antes de tributar* y *Medidas reales y cifras de referencia*). Hasta T17 la población no come: el maíz va todo a la facción, el tributo no mira la cosecha y un año malo solo pesa por un agravio fijo. T24 pasa los datos a medidas reales con cifras de fuentes; T25, sobre ellas, hace que la gente coma antes de tributar. T24 no depende de la ronda 6 y puede ir en paralelo con ella; T25 espera a T24 y a T17. La demografía (hito 6) leerá la cobertura de T25.

| Ronda | Tarea | Área (archivos principales) | Depende de | Hito |
| --- | --- | --- | --- | --- |
| 7 | T24 Medidas reales y cifras de referencia (hecha en `claude/medidas-reales`) | `datos/terrenos.json`, `datos/bienes_1475.json`, `datos/facciones/tutorial_1475.json`; `reglas`: `Produccion`, `Constantes`; `motor`: `Moneda` (rangos); `cliente/` (unidades) | T17 | 3 |
| 7 | T25 Subsistencia: cobertura, reserva y tributo en especie (hecha en `claude/subsistencia`) | `reglas`: `Produccion`, `Sistemas`, `Propios`, `Constantes`, sistema nuevo de subsistencia; `datos/guion_1475.json` | T24, T17 | 3 |

**Ronda 8: la dieta, los procesos y los oficios** (V5, *La dieta: alimentos, gustos y lujos*, *Recursos, bienes con usos y procesos* y *Los procesos de una tecnología: bienes y gente*). T25 alimenta solo con maíz; esta ronda da a la gente una dieta con grupos y topes (nadie vive de cacao ni de chile), hace de la milpa, la chinampa y las cadenas (tejido, cobre) procesos de las tecnologías, forma gente de oficio que cambia la sociedad, abastece la capital desde las trojes como en las fuentes, y da a los gustos y lujos un papel en el agravio y la lealtad. Va antes de T26 (influencia), que leerá la lealtad y la población que esta ronda mueve. T27 va primero; T28 y T30 pueden ir en paralelo después de ella; T29 después de T28 (recalibra con los sistemas); T31 después de T28.

| Ronda | Tarea | Área (archivos principales) | Depende de | Hito |
| --- | --- | --- | --- | --- |
| 8 | T27 La dieta: alimentos por grupo con tope, en toneladas de maíz equivalente (hecha en `claude/dieta`) | `reglas`: `Subsistencia`, `Produccion`, `Constantes`; `datos/dieta.json`, `datos/bienes_1475.json` | T25 | 3 |
| 8 | T28 Procesos de bienes en las tecnologías: la milpa y los demás (hecha en `claude/procesos-de-bienes`) | `reglas`: `Produccion`, `Edificios` (conocimientos); `datos/edificios.json`, `datos/terrenos.json` | T27 | 3 |
| 8 | T29 Abasto de la capital desde las trojes | `reglas`: `Subsistencia`, `Comando`, `Propios`; `datos/guion_1475.json`; recalibración de `datos/terrenos.json` | T28 | 3 |
| 8 | T30 Gustos y lujos: necesidades por estrato | `reglas`: `Subsistencia`, `Sistemas`, `Grupos`; `datos/necesidades.json` | T27 | 3 |
| 8 | T31 La chinampa: tecnología y obra en celda | `datos/edificios.json`, `datos/facciones/`; `reglas`: `Edificios` | T28 | 3 / 5 |
| 8 | T32 Cadena textil: algodón, hilo y mantas, con el trabajo de la casa | `reglas`: `Produccion`; `datos/edificios.json`, `datos/bienes_1475.json`, `datos/terrenos.json` | T28 | 3 |
| 8 | T33 Cadena del cobre: mineral, fundición y labrado, con leña y herramientas | `reglas`: `Produccion`, `Edificios`; `datos/edificios.json` | T28 | 3 |
| 8 | T34 Recursos que se agotan y se regeneran: bosque, pesquería, yacimiento | `reglas`: `Produccion`; `motor`: `Terrenos`; `datos/terrenos.json` | T28 | 3 / 6a |
| 8 | T35 Procesos de gente: oficios, formación y desplazamiento | `reglas`: sistema nuevo de traslados (paso 11), `Edificios`, `Grupos`, `Fusion`; `datos/edificios.json`, `datos/facciones/` | T28, T13 | 3 / 6 |
| 8 | T26 Influencia: fuerza por población y lealtad, y afinidad de la gente | `reglas`: derivado del mapa (paso 16), `Estado`, `Formulas`; `datos/identidades.json`; `motor`: `Influencia` (solo la publicación con umbral) | T27 (orden, no dependencia de código); T12, T13 | 4 / 6 |

---

## Contexto común (pegar antes de cada tarea)

```
Trabajas en "Curicaueri: Flor y Canto", un juego de gran estrategia de código abierto
sobre Mesoamérica de 1418 a 1607, jugado desde el reino purépecha: las demás facciones las
juega una IA sencilla y solo la purépecha tiene eventos escritos. Primero se construyen los
sistemas completos con contenido de juguete; la calibración y el contenido histórico vienen
después. Repositorio: https://github.com/LeoKonig/curicaueri

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

## T5. Guion del tutorial 1475–1530 (datos)

```
Tarea: reemplazar el guion ilustrativo datos/guion_1475.json por el guion del tutorial
(escenario 1475–1530, V5 *Alcance*), construido con las decisiones recurrentes del
prototipo del hito 0.

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

## T6. Inventario histórico de 1418 (sin código; asistente con búsqueda web)

```
Contexto: diseño un juego de estrategia sobre Mesoamérica de 1418 a 1607, jugado desde el
reino purépecha. Necesito el estado político de partida, con fuentes verificables. Para cada
afirmación da la fuente (autor, obra, año, página si es posible) y marca el grado de
certeza (alta, media, baja). Si las fuentes discrepan, muestra las posturas. No inventes
citas: si no puedes comprobar una página, dilo.

Preguntas:
1. Michoacán hacia 1418: ¿qué cronologías proponen los autores para Taríacuri y los tres
   señores (Hirípan en Ihuatzio, Tangáxoan en Tzintzuntzan, Hiquíngare en Pátzcuaro), y
   para Tzitzispandáquare? ¿Hay en 1418 un reino, tres señoríos aliados o algo anterior?
   Fuentes: Relación de Michoacán, Pollard, Warren, Roskamp, Martínez Baracs.
2. Altiplano Central en 1418: entidades políticas (Azcapotzalco, Tenochtitlan, Tlatelolco,
   Tetzcoco, Tlacopan, Coyoacan, Chalco, Xochimilco, Tlaxcala, Huexotzinco, Cholula,
   Metztitlán y los señoríos menores que se documenten), quién gobernaba, quién tributaba a
   quién. Fuentes: Carrasco, Santamarina, Gibson, Hassig.
3. Lista de facciones de 1418 en el resto del mapa (Oaxaca, mundo maya, Golfo y Huasteca,
   Occidente, Gran Chichimeca), con tipo de organización (reino, señorío, confederación,
   pueblo nómada) y certeza. Ojo: Mayapán no se había disgregado en 1418 (1441–1461, por
   verificar).
4. Revisión de las listas de eventos purépechas y de la Triple Alianza que el autor reunió
   (pídeselas): por cada evento, si la fecha y la cita se sostienen, y si los términos en
   purépecha son correctos ("tepuztli", por ejemplo, es náhuatl).

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

## T12. Varias facciones en las reglas (reglas, hito 4)

```
Tarea: que el juego de reglas tenga muchas facciones con los mismos sistemas. Hoy hay una
sola: `entFaccion = EntRef "faccion" 1`, con un cazonci, unas tasas y un presupuesto.

Lee: V5 *Alcance: el juego del motor y el tutorial*, *Qué es una facción*, *Tipos de
facción y niveles de detalle*, *Aparición y desaparición de facciones* y la fila del
hito 4 en *Hitos*; documento funcional, secciones 1, 4 y 14b (aparición y desaparición).

Haz:
1. Una entidad Faccion en Reglas.Estado (id, nombre, tipo, estado potencial/activa/
   eliminada, gobernante, tasas, presupuesto, jugable). Tesoro, prestigio y legitimidad
   siguen siendo magnitudes, ahora de `faccion <id>`.
2. Cada altépetl pertenece a una facción y tiene condición (sujeto, señorío, independiente).
3. Los sistemas (hacienda, agravio, obras, producción, nombramientos) recorren todas las
   facciones activas por id. Los comandos actúan sobre la facción que los sella.
4. Un agente nulo por cada facción no jugable (`juegoAgentes`).
5. Aparición por fecha y desaparición por absorción, con la transferencia y su ley de
   conservación.
6. Guardados: sube versionGuardado en un commit propio si no se puede dar valor por defecto.

Pruebas: con agentes nulos, cambiar cuál facción es la jugable no cambia la traza; dos
facciones con los mismos datos evolucionan igual; una facción absorbida transfiere todo
lo que no se declara perdido. Mide con `--escala` (CLAUDE.md, *Pensado para el juego
completo*). Rama: claude/varias-facciones.
```

## T13. Escenarios como datos y campaña 1418 de juguete (después de T12)

```
Tarea: sacar el escenario del código y cargar la campaña 1418–1607 con contenido de
juguete.

Lee: V5 *Alcance*, *La rebanada vertical*, *Tipos de facción y niveles de detalle* (la
lista de facciones por región) y la fila del hito 4; documento funcional, sección 17.

Haz:
1. escenarios/campana_1418.json y escenarios/tutorial_1475.json con fecha inicial y final,
   desfase del calendario, facciones, altépetl, pops, personajes, sistemas activos y ejes.
   El tutorial reproduce el escenario actual de Reglas.Escenario.
2. datos/facciones/ con la lista de juguete de V5 (unas decenas de facciones, uno a tres
   altépetl cada una), marcada con "_provisional": true. No busques fuentes: eso es T6.
3. Cáscara: --escenario ARCHIVO; sin él, el tutorial.
4. Errores de carga acumulados, como el guion.

Criterio: `nucleo --sin-cliente --escenario escenarios/campana_1418.json --ticks 69000`
corre hasta 1607, guarda y carga a mitad y sigue igual; el tutorial da la misma traza que
el escenario de hoy. Rama: claude/escenarios-datos.
```

## T14. Condiciones y efectos nuevos (motor, hito 4)

```
Tarea: ampliar el lenguaje cerrado de condiciones y el conjunto de efectos, para que los
eventos purépechas y la aparición de facciones puedan escribirse en datos.

Lee: documento funcional, secciones 10, 11, 11b y 14b; V5 *Sistema de eventos* y
*Aparición y desaparición de facciones*.

Haz, en el motor y probado con el juego de juguete:
1. Condiciones: `ocurrio` (un tipo de hecho está en la crónica, con ventana opcional) y
   las que necesitan datos del juego como funciones que el juego aporta (soberano de una
   entidad, facción activa, personaje vivo), sin que el motor importe reglas.
2. Efectos: añadir un modificador temporal con fuente (magnitud, valor o porcentaje,
   duración); los que transfieren entidades o activan facciones van como efectos propios
   del juego (`efectosPropios`, documento funcional sección 1).
3. Carga: tipos y referencias comprobados al cargar, con todos los errores acumulados.

No toques reglas salvo para registrar los efectos propios si T12 ya se fusionó.
Rama: claude/condiciones-efectos.
```

## T15. Herramienta de mapa (Python, hito 5)

```
Tarea: la herramienta que genera el paquete del mapa completo.

Lee: V5 *El mapa como grafo*, *El mapa completo: celdas iguales e ids globales* y
*Escala de la simulación*; documento funcional, sección 8 (ids globales y ley de
ampliación); Motor.Mapa y Motor.Terrenos para el formato que lee el núcleo.

Haz: herramientas/mapa/ en Python con versiones fijas (GDAL, rasterio, shapely), que lea
elevación (Copernicus), ríos (HydroSHEDS) y ecorregiones, trace hexágonos de 5 km sobre
una proyección de área igual, asigne terreno por celda y escriba el paquete compacto
(tramos por fila, vecinos deducidos, excepciones en listas). Sumas de verificación de
cada fuente; misma entrada, misma salida. Un mapa de prueba pequeño (Michoacán) va en el
repositorio; el mapa entero se genera.

Criterio: el núcleo carga el mapa de prueba con validarMapa sin errores, y la misma celda
tiene el mismo id en el mapa de prueba y en el entero. Rama: claude/herramienta-mapa.
```

## T16. Cosecha por estación y merma con troje (motor y reglas, después de la merma)

```
Tarea: que el maíz se coseche en su estación y no parejo todo el año, y que la troje baje
la merma del maíz guardado. Con la merma ya hecha, esto da la escasez antes de la cosecha:
el precio del maíz sube cuando el almacén se vacía y cae cuando entra la cosecha.

Lee: V5 *Temporada de guerra y guerra ritual* (la estación sale del día del año SOLAR de la
fecha visible, no de la veintena: el año interno de 365 días se desfasa), *La moneda
designada y la inflación* (la merma), *La tierra y la gente* y *Las obras* (la troje);
documento funcional, secciones 12 y 14g y la tabla de leyes de la sección 19.

Haz:
1. La estación como derivado de la fecha visible, con las dos ventanas de V5 en
   constantes (INICIO_TEMPORADA_AGRICOLA, INICIO_TEMPORADA_GUERRA), marcadas como
   provisionales. Es la primera pieza que la usa; la guerra la leerá después.
2. En datos/terrenos.json, un campo opcional por bien del rendimiento con la ventana de
   cosecha en días del año solar. Por omisión, todo el año (lo de hoy no cambia). La
   producción de la ventana reparte el rendimiento anual entre las veintenas que caen en
   ella: lo cosechado en un año es lo mismo que hoy.
3. La merma pasa de dato fijo a magnitud de la facción, `bien.<id>.merma`: su base es la
   del archivo de bienes (la escribe la producción) y la troje le aporta un porcentaje
   negativo con su fórmula de rendimiento decreciente, con fuente, para que el desglose
   la explique. El motor lee la merma efectiva si la magnitud existe y bnMerma si no
   (pasoMoneda la usa para el tesoro): una función en Motor.Moneda, sin importar reglas.
4. Decide y documenta qué cuenta como «producción» en el precio (disponible =
   existencias + producción · horizonte): con cosecha por estación, la producción fuera
   de la ventana es 0. Mide en una partida de 10 años cuánto oscila el precio del maíz
   con cada opción y elige la que dé una subida antes de la cosecha sin dispararse.

Pruebas: ley de conservación anual (la cosecha por estación suma lo mismo en el año que
la producción pareja); sin ventana, la partida es idéntica; el precio del maíz es más alto
la veintena antes de la cosecha que la siguiente; una troje baja la merma efectiva y el
desglose nombra la troje; guardar a mitad de la estación y cargar sigue igual. Mide con
--escala 7500x20. Rama: claude/cosecha-estacion. Las fechas de la cosecha en Michoacán
llevan «por verificar».
```

## T17. Mala cosecha y abrir las trojes (después de T16, T5 y T14)

```
Tarea: la decisión recurrente «Mala cosecha» de V5 sobre el juego real, y el primer
consumo de bienes: abrir las trojes resta maíz de las existencias.

Lee: V5 *Decisiones recurrentes* (Mala cosecha: abrir las trojes, comprar a un vecino o
no hacer nada) y *Actos modulares*; documento funcional, secciones 11, 11b y 12;
el guion del tutorial de T5.

Haz:
1. La cosecha de cada año lleva un factor del azar determinista, rng σ "cosecha" año,
   por facción, con su rango en constantes (provisional). Un año malo baja la cosecha y
   el desglose lo dice.
2. Un efecto propio del juego (efectosPropios, T14) que consume un bien de las
   existencias de la facción, con rechazo sin daño si no alcanza. Es el primer consumo
   de bienes: actualiza el pendiente (1) de V5, *La moneda designada y la inflación*.
3. La situación «Mala cosecha» en datos/guion_1475.json, con su condición sobre
   bien.maiz.produccion y sus tres opciones: abrir las trojes (consume maíz y baja el
   agravio), comprar a un vecino (tesoro, al tipo del día con enCuenta) o no hacer nada
   (agravio). Si una opción necesita algo que no existe (la mortalidad es del hito 6),
   no lo inventes: anótalo en el PR.

Pruebas: con la misma semilla, los mismos años malos; abrir las trojes baja las
existencias exactamente lo consumido; con las trojes vacías, la opción se rechaza sin
daño; el arnés del 0a (T11) cuenta la decisión. Rama: claude/mala-cosecha.
```

## T18. Ejércitos, leva y movimiento (reglas, hito 7; después de T13 y T14)

```
Tarea: que los ejércitos existan. Hoy `ReclutarEjercito` se rechaza con "no_implementado"
y la partida de ejército del presupuesto (`pbEjercito`) se gasta sin comprar nada.

Lee: V5 *Incursiones, saqueo, requisa y leva* (una sola mecánica para retirar gente:
`retirar_trabajadores`), *Combate estratégico* (movimiento con el costo del grafo) y
*Temporada de guerra y guerra ritual*; documento funcional, secciones 8, 12 y 13b
(el ejército guarda cuántos guerreros vienen de cada asentamiento de origen).
Reglas.Produccion ya implementa el retiro para la cuadrilla de obra.

Haz:
1. Entidad Ejercito en Reglas.Estado: id, facción, celda, tropas por origen, moral,
   calidad, general (personaje opcional). Magnitudes `ejercito.<id>.moral` y
   `ejercito.<id>.calidad` con su escritor declarado. Es estado almacenado.
2. `reclutar_ejercito {altepetl, tropas}` usa `retirar_trabajadores` con motivo leva:
   baja la producción del altépetl (más en temporada agrícola, con la estación de T16) y
   da agravio si la leva es alta. La leva se acota por la fracción de hombres adultos de
   cada pop (dato, por verificar): con el reino entero, 40 000 guerreros en Taximaroa son
   posibles; con la cuenca sola, no (V5, *Medidas reales y cifras de referencia*).
   Si el formato del comando cambia, actualiza el dorado
   y explica la compatibilidad. `licenciar_ejercito` no está en el catálogo: si hace
   falta para devolver a la gente, pregunta antes de añadirlo.
3. `mover_ejercito {ejercito, destino}`: ruta de menor costo por el grafo (Motor.Mapa),
   avance diario en el paso 2 según el costo de cada conexión. Ruta y llegada en días
   de marcha, nunca en celdas.
4. El mantenimiento sale de la partida de ejército del paso 5; la consulta de predicción
   muestra cuánto cuesta y cuánto baja la producción antes de confirmar.
5. Campaña fuera de temporada: los modificadores de V5 (producción, agravio, +25 % del
   costo de mantenimiento), con fuente "campaña en temporada de siembra".

Pruebas: la población se conserva al reclutar (lo retirado vuelve al licenciar); un
ejército llega al destino en los días que da el grafo (ley contra Dijkstra por fuerza
bruta en mapas pequeños); guardar a mitad de una marcha y cargar sigue igual. Mide con
--escala 7500x20 y cientos de ejércitos. Rama: claude/ejercitos.
```

## T19. Guerra: casus belli, combate, tregua y paz (reglas, después de T18)

```
Tarea: declarar la guerra, combatir de forma automática y hacer la paz.

Lee: V5 *Combate estratégico*, *Temporada de guerra y guerra ritual* y la fila de
«Guerra con casus belli y treguas» en las palancas; documento funcional, sección 13
(la fórmula `resolver_combate` y sus dos leyes) y 14b (transferir un altépetl, T14).

Haz:
1. `resolver_combate` como fórmula con nombre en Reglas.Formulas, exactamente con la
   forma del documento funcional (fuerza efectiva, q, ruido con u de
   `rng σ "combate" tick`, bajas con TASA_BAJAS y persecución). Constantes provisionales.
2. Casus belli válidos como derivado de la veintena (no se guardan): tributo impagado,
   alianza rota, guerra ritual. La guerra ritual queda para T23; aquí solo el tipo.
3. `declarar_guerra {faccion, casus_belli | null}`: sin casus belli cuesta prestigio y
   relación con todas las facciones (modificadores con fuente). Rechazo sin daño con
   tregua vigente.
4. Dos ejércitos enemigos en la misma celda combaten en el paso 2. Las muertes bajan el
   pop de origen por los ajustes pendientes (un solo escritor de `pop.tamano`).
5. `asaltar {ejercito, altepetl}`: combate contra la guarnición con la fortificación
   como porcentaje del defensor; al ganar, la ocupación. La transferencia del altépetl
   ocurre al firmar la paz con el efecto de T14, no al ocuparlo.
6. `proponer_paz` crea la tregua de 10 veintenas (V5). La propuesta y la respuesta son
   de T21: si T21 no está, la paz se acepta sola y lo anotas en el PR.
7. Hechos `guerra_declarada`, `batalla`, `paz_firmada` en la tabla de la crónica.

Pruebas: las dos leyes de la sección 13 (monotonía y simetría con el mismo u) con
QuickCheck; una guerra sin casus belli baja el prestigio y el desglose lo dice; con
tregua, declarar se rechaza sin cambiar el estado. Rama: claude/guerra.
```

## T20. Abasto, deserción, motín y asedio (reglas, después de T19)

```
Tarea: que un ejército se deshaga sin comida, sin paga o sin moral, y que las plazas se
tomen por hambre.

Lee: V5 *La coerción como cadena* completa; documento funcional, sección 13b completa.

Haz:
1. `ejercito.<id>.abasto` (reserva, escritor único: el sistema de abasto, cada día en
   el paso 2 tras el movimiento) y `ejercito.<id>.flujo_abasto` (magnitud con aportes
   con fuente: troje, fortaleza, camino, distancia en días, tamaño, temporada).
2. Ruta al troje propio más cercano y su condición «abierta» por el control de cada
   celda, evaluada cada día. Estado derivado (abastecido, forrajeo, hambre, disuelto),
   nunca guardado.
3. Forrajeo, hambre, deserción y disolución con la regla de los desertores: cerca de
   casa vuelven (lealtad «campaña fallida»), lejos se asientan (misma operación que
   `reubicar_pops`; si no existe todavía, se detiene y pregunta).
4. Motín tras VEINTENAS_PARA_MOTIN sin paga; hecho `motin`.
5. `asediar {ejercito, altepetl}`: corta el abasto de la plaza; la guarnición pierde moral
   y `reservas_asedio`; rendición en 0. Hambre en la plaza, `asedio_levantado` si el
   sitiador se disuelve. El relevo y `HacerSalida` siguen reservados.
6. Cliente: la ruta de abasto en rojo cuando está cortada (sin lógica de juego).

Pruebas: la población total se conserva salvo los muertos en combate y por hambre (ley);
el forrajeo nunca sube la reserva por encima de UMBRAL_FORRAJEO; una fortaleza alarga
un asedio y el desglose lo explica. Mide con --escala. Rama: claude/abasto-asedio.
```

## T21. Vínculos entre facciones y propuestas (reglas, hito 7; después de T13 y T14)

```
Tarea: tregua, alianza y tributo entre facciones como vínculos, y la respuesta a una
propuesta como decisión pendiente.

Lee: V5 *Vínculos y concesiones* (los tres planos y la tabla de vínculos);
documento funcional, secciones 10 (decisiones pendientes) y 14c. En el catálogo,
`ResponderPropuesta` puede adelantarse al hito 4 para paz y alianza.

Haz:
1. Vínculo como dato almacenado: partes, tipo (tregua, alianza, tributo), desde, hasta
   opcional y fuente. Tipos declarados en datos, con exclusiones.
2. `proponer_alianza`, `romper_alianza`, `exigir_tributo` y `responder_propuesta`. Para
   el jugador, una propuesta recibida es una decisión pendiente con plazo; la IA
   responde con el comando.
3. `costo_ruptura` como fórmula con nombre, creciente con la antigüedad del vínculo.
   Romper una alianza o no pagar un tributo da el casus belli correspondiente (T19).
4. El tributo entre facciones mueve tesoro o bienes en su periodicidad, reutilizando el
   tributo en especie entre altépetl con retraso y costo de transporte.
5. Cada vínculo activo suma a `faccion.carga_administrativa` si la magnitud existe; si
   no, anótalo como pendiente.
`EnviarRegalos`, `EnviarEmbajada` y las concesiones quedan fuera: no inventes su forma.

Pruebas: romper un vínculo viejo cuesta más que uno nuevo; una propuesta pendiente
sobrevive a guardar y cargar; un tributo pactado se paga en su fecha y el desglose del
tesoro lo nombra; un rechazo no cambia el estado. Rama: claude/vinculos.
```

## T22. IA sencilla: planificador, ejecutor y personalidades (después de T19 y T21)

```
Tarea: reemplazar el agente nulo de cada facción no jugable por las cuatro reglas de V5.

Lee: V5 *La IA mínima* completa (dos niveles, el cerebro como módulo, la personalidad
es un dato, la excepción de la Triple Alianza contra el reino) y *Temporada de guerra*
(IA_FACTOR_TEMPORADA); documento funcional, sección 14 (planificar, ejecutar, la forma
simple de la corrutina).

Haz:
1. `agenteIA :: Personalidad -> Agente ...` en reglas, con las cuatro reglas en el
   planificador (cada veintena, `rng` "plan" facción veintena) y el ejecutor (cada
   tick, `rng` "ejec" facción tick). Nunca muta el estado: devuelve plan y comandos,
   que se validan igual que los del jugador.
2. datos/personalidades/ con el esquema de V5 validado al cargar (un valor fuera de rango
   falla con todos los errores acumulados); una personalidad por tipo de facción de
   juguete, marcada "_provisional": true. Cada facción declara la suya.
3. El plan vigente es estado almacenado y visible en modo de depuración con su motivo
   legible («ataca a X porque su poder relativo es 1,4»); los cambios de plan pueden
   ir a la crónica según la tabla de T2.
4. La Triple Alianza contra el reino usa la fórmula de invasión de la sección 13
   (revisada solo en temporada de guerra), no la regla 1.
5. El arnés (T11 si existe; si no, `--sin-cliente --metricas`) informa por década:
   guerras, alianzas, tributos, facciones activas y la mayor proporción del mapa en
   manos de una facción.

Criterio del hito 7 a medir aquí: en una campaña de 1418 a 1607 sin jugador hay guerras,
alianzas y tributos en cada región, ninguna facción se queda con todo el mapa, y cada
ataque se explica por poder relativo u oportunismo. Si no se cumple, el informe lo dice:
no ajustes las reglas para que pase sin decirlo. Rama: claude/ia-sencilla.
```

## T23. Rebeliones, incursiones, saqueo, requisa y guerra ritual (cierra el hito 7)

```
Tarea: las formas de coerción que no son la guerra abierta entre facciones sedentarias.

Lee: V5 *Incursiones, saqueo, requisa y leva*, *Temporada de guerra y guerra ritual*,
*La coerción como cadena* (ocupación y la frontera chichimeca) y *Condición del
altépetl*; documento funcional, sección 13 (probabilidad de rebelión, guerra ritual como
restricción del combate) y la parte de condición del altépetl (rebelión triunfante y
sometimiento).

Haz:
1. Rebelión: probabilidad por veintena con la fórmula de la sección 13; una rebelión
   triunfante activa una facción desde la plantilla `senorio_independiente` (id nuevo,
   nunca reutilizado) y el sometimiento la absorbe (efectos de T14).
2. `saquear` y `requisar` sobre un altépetl ocupado, con los costos de la tabla de V5;
   la requisa usa `retirar_trabajadores` con motivo requisa.
3. Incursiones de las facciones de tipo bandas nómadas: sin abasto ni trojes, golpean
   primero a la población dispersa; las fortalezas reducen su éxito en su radio.
4. Guerra ritual: casus belli solo en temporada de guerra entre las parejas de
   `guerra_ritual_entre` (dato), combate con bajas reducidas y prisioneros, sin cambio
   de territorio, enfriamiento de 36 veintenas por pareja.
5. Los prisioneros se cuentan; su destino ritual es del hito 8 (`DarDestinoPrisioneros`):
   no lo adelantes.

Pruebas: con legitimidad baja hay más rebeliones (misma semilla, ley de monotonía); una
rebelión triunfante y su sometimiento conservan lo transferido (ley de T12); la guerra
ritual nunca cambia de dueño un altépetl. Al terminar, repite la medición de T22 y
actualiza la fila del hito 7 en V5. Rama: claude/coercion-menor.
```

## T24. Medidas reales y cifras de referencia (datos y reglas, hito 3; después de T17)

```
Tarea: que los números del juego sean medidas reales del sistema internacional, con
cifras de partida tomadas de fuentes, en vez de unidades abstractas.

Lee: V5 *Medidas reales y cifras de referencia* (las tablas de ración, rendimiento y
demografía, con sus fuentes y lo que está por verificar) y *Comer antes de tributar*;
documento funcional, secciones 12 (Unidades), 15 (rango y desbordamiento de Fijo) y 19.

Haz:
1. Bienes a granel en toneladas (maíz, pescado seco, sal, obsidiana, cobre; el kg se redondearía
   a cero con cuatro decimales), mantas en piezas,
   madera y piedra en m³ o t (elige y anótalo). datos/bienes_1475.json: valor por kg,
   referencia y merma en esas unidades. Sube el rango de los bienes (hoy 10⁹) y comprueba
   al cargar que nada satura Fijo a la escala del juego completo.
2. datos/terrenos.json: por terreno, superficie cultivable por celda en ha (con el área
   de la celda del mapa: di cómo la calculas desde radio_km), rendimiento en kg/ha por
   año y ha que trabaja un campesino. La fórmula de producción no cambia: y(c) y ℓ(c)
   salen de esos datos (documento funcional, sección 12). Carga con todos los errores
   acumulados; los datos viejos con la clave de antes se rechazan con un mensaje claro.
3. La ración diaria por persona (0,45 kg de maíz, relleno con fuente) como constante
   con nombre. Todavía no se consume: la usa T25. Anota cada cifra con su fuente o con
   «por verificar» en el «_nota» del archivo de datos que la lleva.
4. datos/facciones/tutorial_1475.json: comprueba los pops contra las estimaciones de V5
   (Tzintzuntzan 25 000–35 000; la cuenca, hasta unas 80 000) y anota la fuente. No
   inventes el resto del reino: deja escrito en el PR qué haría falta para que la leva de
   Taximaroa sea posible (pops agregados del resto del reino o el inventario de T6).
5. El cliente muestra las unidades: kg, y t a partir de 1 000 kg (textos de las
   magnitudes, sin lógica de simulación en el cliente).

Pruebas: en un año medio, sin azar, el tutorial cosecha entre 1,1 y 1,6 veces lo que
necesita su gente (la prueba de coherencia de V5; si no, se corrigen los datos); la ley
de cosecha conservada de T16 y la de T17 siguen pasando; la ley de rango de los bienes;
el precio del maíz sigue estable con la merma (ajusta la referencia en kg). Repite las
métricas del director y anota las cifras. Mide con --escala 7500x20.
Rama: claude/medidas-reales.
```

## T25. Subsistencia: cobertura, reserva y tributo en especie (reglas, hito 3; después de T24 y T17) — hecha

```
Tarea: que la gente coma antes de tributar. La cosecha de cada altépetl alimenta primero
a su gente; el tributo en especie va a las trojes de la facción; un año malo da hambre,
y el hambre da agravio y baja el tributo.

Lee: V5 *Comer antes de tributar* (orden, efectos por hito, por qué el hambre no baja la
producción) y la fila de «Mala cosecha» en *Decisiones recurrentes*; documento funcional,
sección 12 (Subsistencia y cobertura, con las fórmulas) y las leyes de la sección 19
(masa conservada, cobertura neutra, cobertura monótona).

Haz:
1. Al cosechar, la producción reparte el maíz de cada altépetl: la cuota τ de su facción
   a `bien.maiz.existencias` y el resto a lo cosechado del año del altépetl (magnitud
   nueva, valor por defecto 0). τ sale de la tasa de tributo (relleno: 5 % por punto,
   como constante). `bien.maiz.produccion` sigue siendo el total, para el precio.
2. Sistema de subsistencia (paso 7): al cerrarse la ventana de cosecha, la cobertura del
   año de cada altépetl (`altepetl.cobertura`, base 1 por defecto), la reserva local con
   su tope de un año y la merma del maíz, y el hecho `hambre` bajo el umbral. Un solo
   escritor por magnitud; declara lo que lee y escribe.
3. El aporte «hambre» al agravio de cada pop del altépetl, proporcional a 1 − c, con su
   fuente en el desglose; la hacienda multiplica el ingreso de cada pop por c.
4. Efecto propio `repartir_bien` (facción, altépetl, bien, cantidad), con rechazo sin
   daño. «Mala cosecha» en el guion: «abrir las trojes» reparte maíz a los altépetl con
   hambre en vez de consumirlo; «no hacer nada» ya no lleva agravio fijo, porque el hambre
   lo da la cobertura. Revisa los textos y que cada opción tenga costo visible.
5. Sin datos de producción, cobertura 1 y la partida idéntica a la de antes.

Pruebas: las tres leyes de la sección 19; con la misma semilla, el mismo hambre; dos años
malos seguidos dan más hambre que uno (la reserva se agota); repartir sube la cobertura
exactamente lo que dice la fórmula; guardar a mitad del año agrícola y cargar sigue
igual; el arnés del 0a (T11), si existe, cuenta la decisión. Juega el tutorial por el
protocolo con varias políticas y anota cuántos años de hambre salen. Mide con
--escala 7500x20: un cálculo por altépetl y año. La mortalidad y la migración por hambre
son del hito 6: no las adelantes. Rama: claude/subsistencia.
```

## T27. La dieta: alimentos por grupo con tope (reglas, hito 3; después de T25) — hecha

Hecha con una diferencia: la clase de un bien no va en el catálogo de bienes (lo carga el motor, que no sabe de dietas) sino en `datos/dieta.json` (alimentos) y, con T30, en `datos/necesidades.json` (gustos y lujos).

```
Tarea: que la gente coma más que maíz. Los alimentos cuentan por su energía, en toneladas
de maíz equivalente (t ME), y cada grupo de la dieta tiene un tope de la energía que puede
cubrir, para que una población no viva de un solo alimento.

Lee: V5 *La dieta: alimentos, gustos y lujos* (clases, grupos, topes, la tabla de energía);
documento funcional, sección 12 (*La dieta por grupos*) y las leyes de la sección 19 (tope
de la dieta, equivalencia de la dieta, masa conservada, cobertura monótona).

Haz:
1. `clase` en el catálogo de bienes (alimento, gusto, lujo; sin clase, como hoy) y, para
   los alimentos, `kcal_por_kg` y `grupo`. Valida al cargar, con todos los errores.
2. `datos/dieta.json`: los grupos con su tope de energía, su tope de reserva y su merma.
   Sin el archivo, un solo grupo sin tope: la partida es la de T25.
3. Subsistencia por grupo: `cosechado` y `reserva` por grupo y en t ME; la necesidad en
   energía (`NECESIDAD_ENERGIA`, 0,2 t ME por persona y año). Lo que no se guarda (verduras)
   cuenta el año en que se cosecha y no pasa a la reserva.
4. El aporte «dieta pobre» al agravio sale solo de la cobertura: no hay otro.
5. En el tutorial, los alimentos que ya existen (maíz, pescado) con su clase y su energía;
   los demás entran con T28, que es quien los produce. Un guardado de T25 carga: su maíz
   va al grupo de los granos.

Pruebas: las leyes de la sección 19; un altépetl con solo maíz llega a 0,85 y no más; con
maíz y frijol, más; la tabla de energía de V5 en los datos (una prueba por alimento);
guardar y cargar. Mide con --escala 7500x20: cinco grupos por altépetl. Rama:
claude/dieta.
```

## T28. Procesos de bienes en las tecnologías: la milpa y los demás (reglas, hito 3; después de T27) — hecha

Hecha con un cambio: el orden de las celdas tiene dos pasos, primero la comida y después el valor (V5, *Qué cambia en la producción*). Por valor solo, el tutorial dejaba la milpa por la obsidiana. La pesca, el monte, el solar de frutas y animales, la huerta de tierra caliente, el magueyal y las salinas quedan como datos para cuando haya terrenos y bienes que los pidan; el lago y la sierra siguen rindiendo por su terreno.

```
Tarea: que la celda no rinda por su terreno sino por el proceso de una tecnología que se usa
en ella: la milpa (maíz, frijol, calabaza, chile, quelites), la pesca, el monte, el solar,
la huerta de tierra caliente, el magueyal y las salinas. No hay archivo de recetas: cada
proceso es parte de una tecnología.

Lee: V5 *Recursos, bienes con usos y procesos* y *Los procesos de una tecnología*;
documento funcional, sección 12 (*Recursos, bienes y procesos* y *Producción: tierra y
brazos*), secciones 14e y 14h (insumos con sustitutos), y las leyes «proceso neutro»,
«masa de las cadenas» y «recetas sin ciclos».

Haz:
1. Los procesos de bienes dentro de cada conocimiento de `datos/edificios.json` (lugar,
   terrenos, obra, estrato cuyo trabajo usa, trabajadores, insumos como los `Insumo` de la
   sección 14h, productos por trabajador y año, ventana). Valida al cargar, con todos los
   errores; un terreno con `rendimiento_por_trabajador` sigue igual.
2. Cada celda se trabaja con el proceso posible que más valor da por trabajador; el orden de
   las celdas compara valor por trabajador, no toneladas. El desglose dice qué proceso y por
   qué. Con dominio a medias, rinde a medias; bajo el umbral, no existe.
3. El solar: rendimiento por persona del altépetl, sin celdas.
4. Los bienes nuevos del tutorial en el catálogo y en `datos/dieta.json` (con su grupo y su
   energía), con valor y merma de relleno «por verificar», y su ventana de cosecha.
5. La milpa como tecnología con dominio pleno en las facciones mesoamericanas del escenario.
   Con la milpa, `--dieta` entra a las opciones del juego completo.

Pruebas: las leyes; la milpa da sus cinco bienes en sus ventanas; con más valor, la celda
cambia de proceso; perder dominio baja el rendimiento; el solar crece con la gente; guardar
y cargar. Juega el tutorial con la dieta y anota la cobertura media y los años de hambre.
Mide con --escala 7500x20. Rama: claude/procesos-de-bienes.
```

## T29. Abasto de la capital desde las trojes (reglas, hito 3; después de T28)

```
Tarea: que la capital coma del tributo, como en las fuentes (Gorenstein y Pollard, 1983:
Tzintzuntzan importaba un 44 % de su maíz y un 9 % de su frijol).

Lee: V5 *La dieta*, párrafo «El abasto de la capital»; T25 (`repartir_bien`).

Haz:
1. Una orden permanente de la facción: qué parte del déficit de la capital (y, si se quiere,
   de otros altépetl) cubren las trojes cada año al cerrarse la cosecha. Comando nuevo o
   campo de la facción, con su valor por defecto en 0 para que lo existente no cambie; el
   cliente lo muestra junto a las trojes.
2. Devuelve el llano a 2 500 trabajadores (o a lo que digan las fuentes) y calibra para que
   la capital dependa del tributo en una proporción del orden de la histórica.
3. Una situación del guion cuando las trojes no alcanzan para el abasto.

Pruebas: con la orden en 0, la partida es la de antes; con la orden en 1 y trojes de sobra,
la capital no pasa hambre en un año medio; la masa se conserva. Rama: claude/abasto-capital.
```

## T30. Gustos y lujos: necesidades por estrato (reglas, hito 3; después de T27)

```
Tarea: que la sal y el chile importen a los macehuales, y el cacao a los señores, sin que
alimenten a nadie.

Lee: V5 *La dieta*, la tabla de clases y el párrafo de necesidades por estrato; documento
funcional, sección 12 (*Necesidades de gustos y lujos*); V5 *Política interna: grupos, consejo y reformas* (lealtad de los grupos).

Haz:
1. `datos/necesidades.json`: por estrato, bienes, cantidad por persona y año y peso.
2. Al cerrar el año, la satisfacción de cada estrato; el aporte «gustos» al agravio y,
   para la nobleza y el sacerdocio, un modificador de la lealtad de su grupo con fuente
   «lujos». Sin el archivo, nada cambia.
3. Lo que se entrega sale de las existencias de la facción (efecto o comando de reparto de
   lujos; reutiliza lo de T25 si encaja).

Pruebas: sin el archivo, la partida es la de antes; un gusto no cambia la cobertura de
energía; repartir cacao sube la lealtad de la nobleza con su fuente en el desglose. Rama:
claude/gustos-y-lujos.
```

## T31. La chinampa: tecnología y obra en celda (datos y reglas, hito 3; después de T28)

```
Tarea: la chinampa como obra en celda de lago somero o ciénega, con su oficio, que habilita
el proceso «chinampa» de la tecnología del mismo nombre.

Lee: V5 *Recursos, bienes con usos y procesos*, *Tecnología y educación* y
*Las obras* (obras en celda, oficio).

Haz:
1. El edificio «chinampas» en `datos/edificios.json` (ámbito de celda, materiales, trabajo,
   oficio `chinampa`) y el proceso «chinampa» de esa tecnología, que pide esa obra.
2. Bases del conocimiento por facción en los escenarios: alta entre mexicas, xochimilcas y
   chalcas; baja o nula entre los purépechas (por verificar: la ciénega de Zacapu y la
   ribera de Pátzcuaro).
3. Nada de difusión todavía: eso es el paso 15.

Pruebas: sin el oficio no se empieza; con la obra, la celda pasa a la chinampa y rinde más
por hectárea; bajo control enemigo no rinde. Rama: claude/chinampa.
```

## T32. Cadena textil: algodón, hilo y mantas (reglas, hito 3; después de T28)

```
Tarea: que las mantas salgan del algodón hilado y tejido en las casas, no del llano.

Lee: V5 *Recursos, bienes con usos y procesos* (las cadenas y el trabajo de la casa);
documento funcional, sección 12 (*Procesos de transformación*) y la ley «masa de las
cadenas».

Haz:
1. El trabajo de la casa: una fracción de cada pop (`FRACCION_TRABAJO_CASA`, relleno, por
   verificar) que no le quita gente a la milpa.
2. La tecnología `tejido` con sus procesos de hilado y tejido (lugar: la casa); el algodón
   de la huerta de tierra caliente y el ixtle del magueyal como insumos, el segundo como
   sustituto del primero con su calidad.
3. Los procesos de transformación por facción y periodo, en orden de valor agregado por
   trabajador, hasta donde alcancen el trabajo y los insumos.
4. Quita las mantas del rendimiento del llano en `datos/terrenos.json` y recalibra.

Pruebas: la ley; sin algodón ni ixtle no hay mantas; con ixtle hay menos (su calidad); el
tributo en mantas de un altépetl sin algodón depende del algodón que le llega. Mide con
--escala 7500x20. Rama: claude/cadena-textil.
```

## T33. Cadena del cobre: mineral, fundición y labrado (reglas, hito 3; después de T28)

```
Tarea: el cobre purépecha como cadena: mineral de la sierra, fundición con leña y oficio,
labrado en hachas, cascabeles y adornos; las hachas como herramienta.

Lee: V5 *Recursos, bienes con usos y procesos* (las cadenas y las herramientas); *Las
obras* (oficio); documento funcional, sección 12 (herramientas).

Haz:
1. La tecnología `metalurgia` con sus procesos: minería (en la sierra con yacimiento),
   fundición (obra «fundición», mineral y leña, carbón como sustituto) y labrado (obra
   «taller»).
2. Las hachas como herramienta de la tala y del monte: suben su rendimiento y se gastan.
3. Base del conocimiento por facción en el escenario (alta entre los purépechas; por
   verificar con Hosler, 1994, y Pollard).

Pruebas: sin leña no hay fundición; sin oficio no se empieza; con hachas, el monte rinde
más, con su fuente en el desglose; la herramienta se gasta. Rama: claude/cadena-cobre.
```

## T34. Recursos que se agotan y se regeneran (reglas, hitos 3 y 6a; después de T28)

```
Tarea: que el bosque vuelva a crecer, que la mina se acabe y que el lago se sobrepesque.

Lee: V5 *Recursos, bienes con usos y procesos* (recursos de la celda) y *Erosión*;
documento funcional, sección 12 (*Recursos que se agotan*) y la ley «recurso acotado».

Haz:
1. El recurso de la celda como magnitud, con su capacidad, su regeneración logística y lo
   extraído por los procesos de la celda; la celda rinde en proporción a lo que queda.
2. Datos por terreno (regeneración, capacidad, recurso pleno), relleno «por verificar».
3. Solo se escriben las celdas trabajadas; las demás quedan en su capacidad.
4. Un hecho cuando un recurso baja de un umbral, para la crónica y el guion.

Pruebas: la ley; sin extracción vuelve a su capacidad; con extracción alta se agota y la
producción baja; guardar y cargar. Mide con --escala 7500x20. Rama: claude/recursos.
```

## T35. Procesos de gente: oficios, formación y desplazamiento (reglas, hitos 3 y 6; después de T28)

```
Tarea: que una tecnología forme gente (arqueros, canteros, mineros, fundidores, escribanos,
mercaderes) y que esa gente cambie la sociedad: unos estratos crecen, otros se vacían, y el
poder de los grupos se mueve con ellos.

Lee: V5 *Los procesos de una tecnología: bienes y gente*, *Los grupos* y el párrafo de
demografía con un solo escritor de `pop.tamano`; documento funcional, sección 12
(*Procesos de gente*), sección 14d y las leyes «gente conservada» y «formación acotada».

Haz:
1. Los oficios como estratos (`datos/` del escenario): para qué sirve cada uno (trabajo de
   un proceso, leva, aporte por persona con tope) y su demanda.
2. Los procesos de gente dentro de las tecnologías: candidatos de un estrato de origen,
   plazas de un edificio, maestros del oficio, sustento y años de formación.
3. El sistema que aplica los traslados pendientes entre pops en el paso 11: es la semilla
   del sistema de demografía y el único escritor de `pop.tamano`; `ajustar_poblacion`
   entra por él cuando llegue.
4. El desplazamiento: lo que pasa de la demanda vuelve a la gente común con el aporte
   «oficio perdido» al agravio.
5. Cada tecnología declara sus ejes; el tamaño de los estratos de un eje es una fuente del
   poder de su grupo, con su modificador en el desglose.
6. `OFICIO_MINIMO`: debajo de él, un oficio no forma pop propio.

Pruebas: las leyes; sin plazas o sin maestros nadie se forma; formar arqueros achica a la
gente común y sube la leva; un oficio sin demanda se vacía poco a poco; el poder del grupo
sigue a sus estratos; guardar y cargar. Mide con --escala 7500x20 cuántos pops nuevos hay.
Rama: claude/oficios.
```

## T26. Influencia: fuerza por población y lealtad, y afinidad de la gente (reglas, hitos 4 y 6; después de la ronda 8)

```
Tarea: conectar el recorrido de influencia del motor con el juego. La fuerza de cada fuente
sale de su población y su lealtad, y la afinidad de la gente con cada facción inclina las
zonas disputadas y el costo de gobernar.

Lee: V5 *Mapa: influencia, dueño y control* y *Qué mueve la fuerza de una fuente*;
documento funcional, sección 9 (*La fuerza de una fuente*) y las leyes «influencia
neutra» y «lealtad monótona en la influencia».

Haz:
1. `asentamiento.fuerza_influencia` como magnitud: base (N/N_ref)^β, modificador «lealtad»
   y los de obras y personajes. Un solo escritor de la base.
2. El dueño de cada celda en el derivado (paso 16) con `Motor.Influencia`, y la producción
   y el control leyéndolo (V5, *La influencia cuesta recursos*). Sin mapa, nada cambia.
3. `datos/identidades.json`: identidades, familias de afinidad y su valor; la identidad
   dominante de cada facción en su archivo. La afinidad por altépetl y su uso en el
   desempate de las zonas disputadas y en el costo de gobernar (hoy «identidad ajena»).
4. Publicar al recorrido solo los cambios de fuerza mayores que el umbral, con la ley que
   compara con el cálculo completo.
5. Una situación del guion: un señorío desleal dentro de la influencia de una facción afín
   pide pasarse a ella.

Pruebas: las dos leyes; con afinidad 0 en todo, el costo de gobernar es el de hoy; el
desglose de la fuerza nombra la lealtad. Mide con --escala 7500x20 cuántas fuentes se
publican por veintena y cuánto cuesta. Rama: claude/influencia.
```
