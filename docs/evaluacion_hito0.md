# Evaluación del prototipo del hito 0 (jugado por una IA)

31 de octubre de 2026. Prototipo: `hito_0/Hito 0 v4 - Reino purepecha.dc.html`, 1475–1485. Herramientas y forma de repetirlo: `hito_0/evaluacion/`.

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
