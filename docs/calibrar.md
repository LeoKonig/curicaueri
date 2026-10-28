# Calibrar y medir (hito 2)

El hito 2 tiene dos criterios que no puede cerrar una prueba automática: que el mapa grande vaya a 60 FPS en una máquina de verdad y que las velocidades se sientan bien. Esta guía dice cómo medir los dos.

## Rendimiento: 2 700 hexágonos a 60 FPS

```sh
cd nucleo && cabal run nucleo -- --puerto 4791 --mapa 60x45 &
godot --path cliente --script res://pruebas/prueba_rendimiento.gd -- --puerto 4791
```

La prueba es el peor caso: redibuja todo el mapa en cada fotograma, con la partida a la velocidad máxima y sin vsync. Pasa si el percentil 99 del fotograma es menor de 16,7 ms.

**Lo que se midió aquí, sin tarjeta gráfica** (rasterizado por software, `llvmpipe`, en un servidor):

| Medida | Resultado |
| --- | --- |
| Construir la malla de 2 700 hexágonos | 15 ms, una vez |
| Fotograma con mapa e interfaz | 26 ms de media, 47 ms en el percentil 99 |
| Fotograma solo con la interfaz | 15 ms de media |
| Ritmo del reloj (velocidades 5 y 4) | 3,00 s y 10,00 s por veintena, exactos |

Con rasterizado por software el costo es rellenar píxeles en la CPU, así que estas cifras no dicen nada de una tarjeta gráfica: la malla entera son unos 32 000 triángulos en una sola llamada de dibujo.

**Lo que se midió con tarjeta gráfica** (28 de octubre de 2026; portátil con NVIDIA GeForce MX150, Vulkan Forward+, Godot 4.7.2, Wayland):

| Medida | Resultado |
| --- | --- |
| Construir la malla de 2 700 hexágonos | 38 ms, una vez |
| Fotograma medio | 3,50 ms (285 FPS) |
| Percentil 99 | 7,16 ms |
| Fotogramas medidos | 2 293 en 8 s, hasta el tick 52 |

**Criterio cumplido** con margen de más del doble, en una GPU de portátil de gama baja y en el peor caso. Las dos palancas de reserva (dibujar el mapa estático en una textura una sola vez, refrescar los paneles solo en veintena) no hacen falta por ahora; conviene repetir la medición cuando el mapa tenga caminos, ejércitos y modos de mapa.

## Velocidades: que no se sienta por turnos

Las cifras de V5 son el punto de partida: una veintena dura 60 s a la velocidad 1, 30 s a la 2, 20 s a la 3 (normal), 10 s a la 4 y 3 s a la 5. Se cambian sin recompilar:

```sh
cabal run nucleo -- --velocidades 3000,1500,1000,500,150
```

**Protocolo de una sesión.** Juega 15 minutos seguidos, como jugarías de verdad, sin mirar estas notas. Al terminar:

1. **Tiempo en pausa.** El informe de cada veintena muestra el porcentaje de la sesión en pausa. Si pasa del 60 %, el juego se está jugando por turnos: o hay demasiado que leer entre veintenas, o la velocidad normal es demasiado rápida.
2. **Velocidad usada.** ¿En cuál te quedaste la mayor parte del tiempo? Si casi siempre en la 5, la normal es lenta; si casi siempre en la 1 o la 2, es rápida.
3. **Días vacíos.** ¿Hubo tramos en los que solo mirabas la barra avanzar? Con las reglas actuales casi todo cambia en veintena, así que es esperable; es el riesgo que V5 pide vigilar, y se corrige con mecánicas diarias (ejércitos, obras, incursiones), no con el reloj.
4. **Apunta** las cinco cifras finales y el porcentaje en pausa, y pásalas a `velocidadesPorOmision` en `nucleo/app/Main.hs` cuando te convenzan.

Las reglas del paquete `reglas` todavía son provisionales (hasta el hito 0a), así que esta calibración es preliminar: conviene repetirla cuando las reglas salgan del prototipo de mesa.
