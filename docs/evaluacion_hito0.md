# Evaluación del prototipo del hito 0 (jugado por una IA)

Herramientas y forma de repetirlo: `hito_0/evaluacion/`. La primera parte es la iteración actual (v5); la segunda, la evaluación original de la v4 que la motivó.

# Parte 1: versión 5 (31 de octubre de 2026)

Prototipo: `hito_0/Hito 0 v5 - Reino purepecha.dc.html`, 1475–1485. Se aplicaron los cinco cambios propuestos al final de la parte 2 y se volvió a medir con el mismo arnés, 60 partidas por estrategia y 1 003 partidas de divergencia.

## Veredicto

**El núcleo ya tiene tensión: el final lo deciden las decisiones, no una tirada.** La estrategia experta logra el triunfo en el 93 % de las partidas. Eligiendo siempre la primera opción se logra en el 62 %, al azar en el 5 % y eligiendo siempre la última en ninguno. La caída de la capital va del 0 % al 58 % según cómo se juegue, en vez de rondar el 50 % para todas. **Lo que sigue débil es el ritmo:** a velocidad normal, todavía hay tramos de unos 5 minutos sin nada que decidir ni esperar (ver *Modelo de espera*).

## Qué cambió

| Cambio | Qué se hizo | Dónde |
| --- | --- | --- |
| 1. Que el final dependa de las decisiones | La guerra con la Triple Alianza es una sola: la invasión. Al entrar, un modal ofrece salir a la frontera, defender Tzintzuntzan o pagar por la paz, con la probabilidad de victoria calculada igual que la batalla. La fuerza depende del capitán, la moral, la fortaleza y la guarnición de la capital, con ±10 % de azar. El asedio ya no es un 25 % de rendición por paso: dura lo que dan las trojes llenas y la fortaleza, y el invasor se desgasta. Perder la capital termina la partida. Declarar la guerra a la Triple Alianza provoca su invasión al año siguiente, en vez de ser una tirada aparte con victoria segura | código, `constantes.invasion`, `crisis.invasion`, `acciones.guerra_alianza` |
| 2. Ninguna opción gratis | Conceder la autonomía reduce a la mitad el tributo del señorío durante 5 años. Nombrar al capitán ambicioso cuesta lealtad en la capital. Bajar una tasa por un evento la bloquea 2 años: el deslizador ya no la sube. Abrir las trojes las vacía 2 años, y entonces no protegen ni alargan un asedio. `validar_opciones.py` comprueba que toda opción tenga un costo, un riesgo diferido declarado (`riesgo`) o sea consecuencia de una decisión anterior (`consecuencia_de`). Las crisis muestran deshabilitadas, con su motivo, las opciones que no se pueden pagar | `eventos`, `crisis`, código |
| 3. Presión que no se apaga sola | La lealtad tiende a un objetivo con techo (92, menos 6 por distancia y 10 por identidad ajena) en vez de saturarse en 100. Hay un desgaste anual del agravio (+4 en los señoríos y +1 en la capital). La rebelión es posible con lealtad ≤ 45 (antes, ≤ 30). El agravio alto recorta lo recaudado (−40 % con agravio 80, −50 % con 100). Las incursiones suben el agravio | código, `constantes.presion`, `rebelion`, `economia`, `incursion` |
| 4. Riesgo en lo militar | La expedición chichimeca manda un destacamento de 4 000. Su victoria va del 28 % (capitán normal, sin casus belli) al 70 % (mejor capitán, con casus belli), y puede perderse. El ultimátum es un modal con tres salidas: pagar (retrasa 3 años y humilla a la nobleza), negociar (1 año) o rechazar | `constantes.guerra.expedicion`, `crisis.ultimatum` |
| 5. Sumideros y metas | Metas explícitas para 1485: conservar la capital, ningún señorío independiente, prestigio ≥ 35 y lealtad media ≥ 60. La pantalla final da un veredicto (triunfo, reinado firme, supervivencia, decadencia o caída). Dos sumideros nuevos: la gran fiesta (una vez al año) y la gran yácata de Curicaueri (1 500 de tesoro y 18 veintenas) | código, `constantes.metas`, `acciones` |
| De tus comentarios | La rebelión matlatzinca de 1475: apoyar debilita al invasor pero adelanta su ataque, acoger refugiados suma gente con agravio, mantenerse al margen lo refuerza. El presagio de sequía avisa con 6 veintenas para prepararse. Las incursiones chichimecas abren una respuesta: perseguir (con riesgo), reforzar la guarnición o dejarlas pasar | `crisis.matlatzinca`, `eventos.presagio_sequia`, `eventos.incursion_respuesta` |

Además se corrigió el texto de las crisis que ocultaba opciones. Se comprobó que todos los textos nuevos resuelven sus marcadores (`i18n.js`) y que la interfaz real muestra el modal de invasión y la pantalla final (`captura.js`).

## Resultados contra los criterios de tensión

| Criterio | v4 | v5 | |
| --- | --- | --- | --- |
| (a) La experta claramente mejor que una regla fija | 0,15 desviaciones de diferencia en puntos | Triunfo: 93 % experta, 62 % primera opción, 5 % azar, 0 % última opción | ✓ |
| (b) Invertir la decisión pesa más que el azar | En ningún tipo con más de una muestra (en la mediana, 44 puntos) | En 10 de 14 tipos | ✓ |
| (c) Ninguna opción sin costo | Varias gratis o explotables (tabla de la parte 2) | Ninguna (validador) | ✓ |
| (d) Ningún año sin decisión | 2,5 años vacíos por partida; 58 de 60 partidas con alguno | 0,9 por partida; 36 de 60 con alguno | Mejor, no cumple |
| (e) La caída de la capital varía con la estrategia | Del 48 al 93 % | Del 0 al 58 % | ✓ |

**Por qué el criterio (a) se mide ahora con el veredicto.** La puntuación provisional premia el tesoro acumulado, y el juego ya tiene metas propias. Con la puntuación, subir los impuestos al máximo empata con la experta: acumula 7 800 de tesoro, pero con lealtad 38 y agravio 80 no logra el triunfo en ninguna partida. Las metas del juego son el criterio honesto.

**"Elegir siempre la primera opción" no es no jugar.** En la v5 esa regla junta tres decisiones prudentes: apoyar a los matlatzincas, pagar el ultimátum y salir a la frontera. Por eso le va bien. Es una línea razonable que cuesta tesoro, prestigio y lealtad, no una opción gratis.

## Modelo de espera: ¿serán aburridas las esperas?

Una IA no siente aburrimiento, pero se puede estimar dónde es probable que una persona se aburra con lo que se sabe de la atención y la espera.

**Lo que dice la investigación, y cómo se traduce al juego:**

- **El aburrimiento es falta de compromiso de la atención:** querer ocuparse en algo y no poder (Eastwood y otros, 2012). Según el modelo MAC (Westgate y Wilson, 2018), aparece cuando falta algo en qué poner la atención o cuando lo que se hace no tiene sentido. *En el juego: un tramo sin decisiones y sin nada pendiente es el caso típico.*
- **El tiempo desocupado se siente más largo que el ocupado, y una espera incierta, sin explicación o cargada de ansiedad, más larga que una conocida** (Maister, 1985). *En el juego: una barra que avanza hacia algo (una obra, un plazo, un enemigo que se acerca) acorta la espera; una amenaza contra la que no se puede hacer nada la alarga.*
- **Acercarse a una recompensa visible sostiene el interés:** la dopamina estriatal sube a medida que se aproxima una recompensa (Howe y otros, 2013), y el esfuerzo crece cerca de la meta (Kivetz, Urminsky y Zheng, 2006). *En el juego: es el componente de "anticipación".*
- **La curiosidad nace de una brecha de información** (Loewenstein, 1994). Lo inesperado mueve la atención por el error de predicción de recompensa (Schultz, Dayan y Montague, 1997), y la repetición produce habituación. *En el juego: el mismo evento con la misma respuesta obvia deja de interesar; un presagio abre una pregunta.*
- **La mente divaga alrededor de la mitad del tiempo cuando la tarea no la reclama** (Killingsworth y Gilbert, 2010), y la vigilancia sin estímulos decae en minutos (Mackworth, 1948). **Quien se aburre sobreestima cuánto duró la espera** (Danckert y Allman, 2005).

**Cómo se mide.** Cada veintena se clasifica en una de tres clases, y los tramos se pasan a tiempo real con las velocidades del cliente de Godot (velocidad 3: 20 s por veintena; velocidad 5: 3 s):

- **D:** el jugador toma alguna decisión.
- **A, anticipación:** hay algo visible por resolverse (obra en curso, ejército mexica en marcha o asedio, ultimátum pendiente, invasión anunciada para menos de un año, sequía anunciada, hambre, ejército marchando).
- **V, vacía:** ni una cosa ni la otra.

| Riesgo | Tramo vacío continuo | Razón |
| --- | --- | --- |
| Bajo | Menos de 30 s | Lo que tarda revisar el mapa o un panel |
| Medio | De 30 a 90 s | La atención empieza a irse a otra cosa |
| Alto | Más de 90 s | Tiempo desocupado sin meta a la vista |

Los umbrales son una heurística de diseño inspirada en esa investigación, no constantes medidas para este juego. Se calibran en la prueba 0b: se le pregunta a la persona cuánto le pareció que duró un tramo y se compara con lo que duró de verdad. Si lo sobreestima, se aburrió.

**Resultados (estrategia experta, v5):**

- La partida es un 13 % de decisión, un 54 % de anticipación y un 33 % vacía: unos **20 s vacíos por cada minuto de juego**.
- El tramo vacío más largo dura en promedio 14,6 veintenas: **≈ 5 min a velocidad 3 (riesgo alto)** y ≈ 45 s a velocidad 5 (riesgo medio).
- Los años más vacíos son 1479 y 1483–1484, después de que se resuelve la primera invasión.
- Frente a la v4: el hueco más largo sin ninguna decisión bajó de 40 a 28 veintenas, y las decisiones de evento subieron de 14,5 a 22,8 por partida.

**Un sesgo de la medición.** En la v4, el ejército mexica podía quedarse años sitiando la capital sin que el jugador pudiera hacer nada, y el clasificador lo contaba como anticipación. Según Maister, una amenaza sin respuesta es ansiedad, que alarga la espera, no anticipación. Por eso la comparación entre versiones usa solo la densidad de decisiones y los huecos, no la clase A.

**Qué falta para que las esperas no aburran:**

1. **En el cliente:** acelerar solo los tramos vacíos y volver a la velocidad elegida al aparecer una decisión o una anticipación, más un botón de "avanzar hasta el próximo suceso" (el prototipo HTML ya lo tiene). Con eso, el tramo vacío más largo bajaría a unos 45 s. Es aplicar a Maister lo más barato: acortar el tiempo desocupado.
2. **En el núcleo de Haskell:** el director del guion ya hace subir la probabilidad de una situación con cada día de espera (el parámetro de tensión). Al portar el prototipo, la meta debe ser ningún tramo vacío mayor de 6 veintenas.
3. **En el diseño:** más fuentes de anticipación con plazo visible (presagios, embajadas que anuncian su llegada, campañas que tardan en volver) y variar los eventos que se repiten, porque la repetición produce habituación.

## Niveles de dificultad

Tres niveles (fácil, normal y difícil), elegibles en la barra superior, en la pantalla final o con `?dificultad=dificil` en la dirección. Al empezar la partida, el cambio se aplica en el acto; después, en la próxima partida. Cada nivel es un bloque de `constantes.json` que sobrescribe valores por ruta, así que se ajusta sin tocar el código.

**El principio: más presión o menos margen, nunca ventajas ocultas al enemigo.** Todo lo que cambia se ve en el desglose y en las probabilidades:

| | Fácil | Normal (por omisión) | Difícil |
| --- | --- | --- | --- |
| Tesoro inicial | 900 | 700 | 600 |
| Ejército mexica (primera oleada) | 30 000 | 34 000 | 38 000 |
| Vuelve tras una derrota | 4 años | 3 años | 3 años |
| Segunda oleada respecto de tu ejército | 0,62 | 0,70 | 0,75 |
| Desgaste anual del agravio | +4 | +6 | +7 |
| Rebelión posible desde lealtad | 45 | 50 | 52 |
| Sequías e incursiones | base | más frecuentes | aún más frecuentes |
| Enemigo en las expediciones | 4 500 | 4 800 | 5 000 |
| Metas: prestigio / lealtad | 35 / 60 | 42 / 62 | 45 / 65 |

**Calibración** (`calibrar_dificultad.js`, 60 partidas por estrategia y nivel; porcentaje de partidas con veredicto de triunfo):

| Estrategia | Fácil | Normal | Difícil |
| --- | --- | --- | --- |
| Experta | 97 % | 93 % | 32 % |
| Constructor | 100 % | 55 % | 43 % |
| Militar | 78 % | 50 % | 27 % |
| Siempre la primera opción | 52 % | 23 % | 8 % |
| Azar | 5 % | 3 % | 0 % |

**Los niveles se definen por cuánta habilidad exigen, no por un porcentaje fijo de la experta.** La estrategia experta del arnés se adapta: guarda reserva para la embajada, paga a tiempo y elige la defensa con mejores probabilidades. Por eso en normal sigue triunfando casi siempre, mientras que las estrategias sensatas pero menos informadas bajan a la mitad. La lectura es:

- **Fácil:** cualquier estrategia sensata triunfa. Equivale a la v5 anterior, con algo más de tesoro.
- **Normal:** hay que jugar bien.
- **Difícil:** incluso jugando bien se pierde a menudo, y una regla fija casi nunca triunfa.

**En normal se mantienen los criterios de tensión:** caída de la capital del 0 al 75 % según la estrategia, decisiones que pesan más que el azar en 11 de 16 tipos y casi ningún año sin decisiones. El tramo vacío más largo baja a ≈ 4,5 min a velocidad 3, porque hay más incursiones y sequías que responder.

## Lo que sigue débil

- **Hay repetición:** conceder la autonomía o perseguir a los chichimecas tiene casi siempre la misma mejor respuesta. Hace falta que los eventos escalen o cambien según lo ocurrido.
- **En cuatro tipos de decisión el azar todavía pesa más que la decisión:** heredero, rebaja, refugiados y excedente.
- **Un dato histórico por verificar:** el prototipo empieza con Zuangua como cazonci en 1475, y Zuangua muere en la partida hacia 1480. Según tus comentarios y la *Relación de Michoacán*, el cazonci de la guerra de 1476–1479 fue Tzitzipandácuare, y Zuangua gobernó después, hasta su muerte por viruela hacia 1520. Si se confirma, conviene cambiar el soberano inicial y la sucesión.

## Sobre la propuesta de 6 altépetl y 10 puntos de interés

Coincido con su diagnóstico central: más hexágonos no dan más tensión, y más señoríos con papeles distintos sí. Pero no lo apliqué en esta iteración, por tres razones:

1. **Depende de seis verificaciones históricas que la propia propuesta enumera,** sobre todo si Pátzcuaro e Ihuatzio eran señoríos aparte y si Taximaroa era purépecha en 1475. Están en la tarea T6 de `docs/tareas_paralelas.md`.
2. **Es mucho trabajo de mapa y datos,** y el núcleo tenía que corregirse primero: con el núcleo de la v4, seis señoríos habrían sido seis veces las mismas decisiones obvias.
3. **Su cifra de "2 a 3 decisiones de cada 10 veintenas" no está medida.** Con el arnés se puede medir en cuanto exista.

Propuesta: hacerlo como la siguiente iteración del prototipo, después de las verificaciones, y medir si sube la densidad de decisiones sin que vuelva la repetición.

### Fuentes del modelo de espera

- Danckert, J. A. y Allman, A.-A. A. (2005). Time flies when you're having fun: Temporal estimation and the experience of boredom. *Brain and Cognition*, 59(3), 236–245.
- Eastwood, J. D., Frischen, A., Fenske, M. J. y Smilek, D. (2012). The unengaged mind: Defining boredom in terms of attention. *Perspectives on Psychological Science*, 7(5), 482–495.
- Howe, M. W., Tierney, P. L., Sandberg, S. G., Phillips, P. E. M. y Graybiel, A. M. (2013). Prolonged dopamine signalling in striatum signals proximity and value of distant rewards. *Nature*, 500, 575–579.
- Killingsworth, M. A. y Gilbert, D. T. (2010). A wandering mind is an unhappy mind. *Science*, 330, 932.
- Kivetz, R., Urminsky, O. y Zheng, Y. (2006). The goal-gradient hypothesis resurrected. *Journal of Marketing Research*, 43(1), 39–58.
- Loewenstein, G. (1994). The psychology of curiosity: A review and reinterpretation. *Psychological Bulletin*, 116(1), 75–98.
- Mackworth, N. H. (1948). The breakdown of vigilance during prolonged visual search. *Quarterly Journal of Experimental Psychology*, 1(1), 6–21.
- Maister, D. H. (1985). The psychology of waiting lines. En J. A. Czepiel, M. R. Solomon y C. F. Surprenant (eds.), *The Service Encounter*. Lexington Books.
- Schultz, W., Dayan, P. y Montague, P. R. (1997). A neural substrate of prediction and reward. *Science*, 275, 1593–1599.
- Westgate, E. C. y Wilson, T. D. (2018). Boring thoughts and bored minds: The MAC model of boredom and cognitive engagement. *Psychological Review*, 125(5), 689–713.

# Parte 2: versión 4 (evaluación original)

Prototipo: la versión 4 del mismo archivo, 1475–1485.

## Veredicto

**El núcleo todavía no tiene tensión, y el resultado lo decide sobre todo el azar de una batalla.** Faltan cosas, pero eso no es lo principal: las decisiones que hay son casi siempre obvias, gratis o irrelevantes, y la presión interna se apaga sola. Añadir más sistemas encima de este núcleo no lo haría más interesante. Primero hay que dar costo real a las opciones y quitarle al azar el control del final. Coincide con lo que notó el autor al jugarlo: "no es aburrido, pero no es muy interesante".

## Cómo se midió

1. **Estrategias fijas contra un jugador con criterio.** Ocho estrategias, 60 partidas cada una, con las mismas semillas: no hacer nada (eligiendo siempre la primera o la última opción), elegir al azar, impuestos al máximo, constructor, militar, una estrategia "experta" y la experta eligiendo los eventos al azar. A diferencia del arnés incluido en el prototipo, estas también construyen, reclutan, mueven el ejército, cambian impuestos y responden al ultimátum.
2. **Divergencia.** En 30 partidas de la estrategia experta se invirtió, una por una, cada decisión de evento: 787 partidas alternativas. Cada una se comparó con otra en la que la decisión no cambia pero se perturba el azar con una sola tirada extra. Si invertir una decisión no mueve el final más que una tirada de dados, la decisión no importa.
3. **Variantes de la experta,** 80 partidas cada una, cambiando una sola cosa: sin expediciones, sin interceptar al invasor, rechazando el ultimátum, sin guarnición.
4. **Tres partidas en voz alta,** decidiendo situación por situación con el texto, las opciones y los costos tal como los ve el jugador. Los perfiles fueron prudente, agresivo y novato; este último elige por el texto y no revisa los paneles. Una vez fijada la respuesta a un evento, se reutilizó cuando el evento volvía.

La puntuación es provisional y solo sirve para comparar: prestigio × 10 + lealtad media × 5 + hexágonos × 20 + tesoro / 10 − 300 por señorío independizado − 2 000 si cae la capital.

## Hallazgos

### 1. El azar pesa más que las decisiones

- **La capital cae en la mayoría de las partidas, se juegue como se juegue:** 55 % con la estrategia experta, 67 % sin hacer nada, 93 % eligiendo siempre la última opción. La mejor variante, sin guarnición en Zacapu, la baja al 33 %. La batalla contra el ejército mexica se decide con un factor aleatorio de 0,85 a 1,15 sobre una proporción de fuerzas cercana a 1. Después, el asedio tiene 25 % de rendición en cada paso.
- **Perturbar solo el azar mueve el resultado más que invertir una decisión:** 1 114 puntos de diferencia media, contra 764. En las inversiones que no cambian si cae la capital, la mediana del efecto es de **44 puntos**, el equivalente a 4 de prestigio. El 65 % de las inversiones cambia el final en menos de 150 puntos.
- La misma semilla, con un solo cambio (el del capitán, abajo), pasó de defender la capital (4 699 puntos) a perderla (1 523).

### 2. No hacer nada funciona casi igual que jugar bien

| Estrategia (60 partidas) | Puntos (desv.) | Cae la capital | Lealtad | Agravio | Tesoro |
| --- | --- | --- | --- | --- | --- |
| Experto | 3 414 (1 535) | 55 % | 97 | 9 | 5 058 |
| Experto, eventos al azar | 3 039 (1 489) | 63 % | 95 | 10 | 4 082 |
| Militar | 2 919 (1 734) | 50 % | 93 | 9 | 383 |
| Constructor | 2 697 (1 723) | 58 % | 97 | 4 | 1 381 |
| No hacer nada, primera opción | 2 339 (1 684) | 67 % | 94 | 8 | 2 778 |
| Impuestos al máximo | 2 212 (1 504) | 80 % | 37 | 81 | 14 761 |
| Azar total | 1 728 (1 742) | 68 % | 88 | 10 | 960 |

La diferencia entre jugar con criterio y no hacer nada (unos 1 100 puntos) es menor que la dispersión entre partidas de una misma estrategia (unos 1 500). Entre las partidas en que la capital resiste, la experta saca 5 101 y la pasiva 4 703: un 8 % más.

### 3. Opciones gratis, dominantes o explotables

| Situación | Problema |
| --- | --- |
| Señorío pide autonomía → conceder | No tiene costo. El texto dice "reduce el control", pero ningún efecto lo aplica: solo da +15 de lealtad y −10 de agravio |
| Capitán ambicioso → nombrar | No hacía nada (error, ya corregido): el efecto escribía en un campo que el juego no lee. Por eso el evento volvía cada pocos años |
| Excedente → bajar impuesto; Petición de rebaja → rebajar | Bajan una tasa y dan agravio −10 o −20. Como la tasa se vuelve a subir gratis con el deslizador, el alivio de agravio sale gratis |
| Expedición chichimeca | El juego muestra "victoria 100 %". Se puede hacer cada año, y con el rescate de prisioneros da dinero y prestigio seguros: 9 expediciones por partida, ninguna perdida |
| Ultimátum mexica | Pagar 400 retrasa la invasión cuatro años; rechazarlo sube la caída de la capital del 46 % al 76 % |
| Guerra con la Triple Alianza (crisis) | Muestra victoria 96 % y derrota 0 %; luchar es obvio |
| Muerte del cazonci con heredero designado | Una sola opción, sin costo: no es una decisión |
| Interceptar al invasor con el ejército | Los resultados salen idénticos con y sin la orden de marcha |

### 4. La presión interna se apaga sola

La lealtad media termina entre 87 y 97 en todas las estrategias, salvo con impuestos al máximo. Y ni siquiera con impuestos al máximo (agravio 81, lealtad 37, tesoro de 14 761) se independiza ningún señorío en 10 años: la rebelión exige lealtad de 30 o menos, y la lealtad no baja tanto. Como la lealtad se satura cerca de 100, perder 10 o 15 puntos casi nunca importa. Por eso los costos en lealtad de muchas opciones son baratos.

### 5. Tiempo muerto

Solo hay alguna decisión en el 10 % de las veintenas. El hueco más largo sin decidir nada dura en promedio 37 veintenas, unos dos años. En 1477 no hubo ningún evento en 29 a 36 de las 60 partidas, según la estrategia. En las partidas en voz alta, la prudente tuvo un solo evento entre 1476 y 1478. Y hacia 1480 se terminó el plan de obras y el dinero se acumuló sin nada en qué gastarlo.

### 6. Repetición

Cada evento vuelve con las mismas opciones, y la respuesta razonable es siempre la misma. La partida prudente respondió "bajar impuesto" las cuatro veces que salió el excedente. La agresiva repitió seis veces el mismo ciclo: ignorar la rebaja, estalla la rebelión, se suprime.

### 7. Incoherencias

- **Dos guerras con la Triple Alianza que no se conocen.** Hay una crisis abstracta con probabilidades a la vista y un ejército mexica que marcha por el mapa y se resuelve aparte. Se puede "ganar la guerra" en la crisis mientras la capital está sitiada.
- **Perder la capital no termina la partida y casi no se nota.** En la partida agresiva, el prestigio siguió subiendo hasta 62 después de la rendición, gracias a los sacrificios de prisioneros.
- **El ultimátum no aparece como decisión.** Solo se anuncia en la crónica y se responde desde el panel de diplomacia. El novato no lo vio, y la invasión llegó en 1478.
- **"Invertir en una obra" puede no tener dónde construir.** Pasó en varias partidas: "no había dónde levantar una yácata".
- **La crónica se llena de "Frontera: X ganó un hexágono a Y"** entre altépetl propios.
- **La crisis de guerra tronaba al abrirse** por una función inexistente (error, ya corregido).

### 8. Lo que sí funciona

- **Las consecuencias se ven:** bajar el impuesto dejó el ingreso neto en −205 al instante.
- **La rebelión es un dilema real:** suprimirla cuesta ejército, tesoro y prestigio, e ignorarla cuesta el señorío. Pero solo aparece si el jugador la provoca.
- **La sucesión es una decisión de verdad cuando no hay heredero,** con costos en dos lados.
- **Designar como heredero al hijo del cazonci tiene un efecto grande y medible:** −1 796 de tesoro al final, en promedio. Es la decisión de evento con más consecuencias.

## Diagnóstico

Es sobre todo el **problema de falta de tensión**: las decisiones no duelen. Encima hay un **problema de delgadez**: tiempos muertos, nada en qué gastar al final y ninguna respuesta posible a las incursiones. Y el final lo decide una batalla casi a cara o cruz. Si se añaden sistemas (guerra, obras, nombramientos) sin corregir esto, el juego será más grande pero igual de plano.

## Cambios propuestos, por prioridad

Casi todos se hacen en datos (`hito_0/datos/*.json`) o en pocas líneas del prototipo, y se comprueban con el arnés en minutos.

1. **Que el final dependa de las decisiones.**
   - Quitar el 25 % de rendición por paso de asedio y el factor aleatorio grande en la batalla. Que la fuerza dependa de lo construido y decidido (fortalezas, guarniciones, moral, capitán) y que el jugador vea la proporción antes de combatir.
   - Unificar la crisis de guerra y el ejército del mapa en un solo conflicto.
   - Que perder la capital termine la partida, o la cambie de forma drástica.
2. **Ninguna opción gratis.** Cada opción debe costar en un eje distinto del que mejora:
   - conceder autonomía, menos tributo de ese señorío;
   - nombrar al capitán ambicioso, lealtad de la nobleza o riesgo de golpe;
   - rebajar el tributo, ingreso perdido durante un plazo, sin poder subirlo enseguida.
   Cambiar una tasa con el deslizador debería tener inercia o costo (enfriamiento, legitimidad), para que las opciones de evento que la tocan no se puedan explotar. Un validador puede rechazar opciones sin ningún efecto negativo.
3. **Presión que no se apague sola.**
   - Que la lealtad tienda a un objetivo calculado con techo, en vez de saturarse cerca de 100.
   - Que los impuestos altos lleven a rebelión e independencia en pocos años.
   - Un desgaste natural que el jugador tenga que contrarrestar: el agravio de la nobleza, la frontera o las sequías.
4. **Riesgo en lo militar.** Expediciones con probabilidades del 55 al 75 % según la fuerza y el casus belli, y que una derrota cueste de verdad. El ultimátum, como decisión modal.
5. **Sumideros y metas.** Algo en qué gastar cuando las obras se terminan (campañas, regalos con efecto duradero, obras grandes) y un objetivo explícito para 1485, con una pantalla final que diga cómo te fue.
6. **Ritmo.** Más situaciones condicionadas al estado, para los años vacíos, y espaciado del director (ya existe en el núcleo de Haskell). Que el mismo evento no vuelva con la misma respuesta obvia: escalarlo o variarlo.

### Criterios de tensión para la siguiente iteración

Se miden con el arnés y conviene añadirlos al criterio 0a:

- **(a)** La estrategia experta supera a "no hacer nada" por más de 1,5 desviaciones típicas.
- **(b)** En la mayoría de los tipos de evento, invertir la decisión mueve el final más que perturbar el azar.
- **(c)** Ninguna opción sin costo: lo comprueba un validador sobre los datos.
- **(d)** Ningún año sin al menos una decisión con costo.
- **(e)** La caída de la capital varía con la estrategia, por ejemplo del 10 % al 70 %, en vez de rondar el 50 % para todas.

## Límites de esta evaluación

- **Una IA no siente aburrimiento ni sorpresa.** Por eso el tiempo muerto se midió y no se opinó.
- **Las estrategias automáticas son simples,** y una persona encontraría otras. Pero si una regla fija rinde casi igual que pensar, el problema es del juego y no de la regla.
- **La puntuación es provisional.** Los hallazgos principales (el azar contra las decisiones, las opciones gratis, la lealtad saturada) no dependen de ella.
- **No sustituye la prueba 0b con una persona.** Sirve para llegar a esa prueba con un núcleo que valga la pena probar.
