# Evaluación automática del prototipo del hito 0

Juega el prototipo HTML (`../Hito 0 v4 - Reino purepecha.dc.html`) desde dentro de la página, sin interfaz, para medir si sus decisiones importan. El resultado y el diagnóstico están en `docs/evaluacion_hito0.md`.

| Archivo | Qué hace |
| --- | --- |
| `arnes.js` | Se inyecta en la página. Crea partidas nuevas con una semilla, define estrategias (cómo elegir en eventos y qué hacer cada veintena) y juega partidas completas registrando decisiones, huecos sin decisión y métricas finales |
| `correr.js` | Ocho estrategias × 60 partidas, y el experimento de divergencia: invierte una sola decisión de un evento y la compara con perturbar solo el azar |
| `ablacion.js` | La estrategia experta cambiando una sola cosa cada vez (sin expedición, sin interceptar, rechazando el ultimátum, sin guarnición) |
| `voz.js`, `ver.sh` | Partida "en voz alta": avanza hasta la siguiente situación sin postura fijada y la muestra como la ve el jugador. Las posturas de los tres perfiles están en `posturas_*.json` |

```sh
./preparar.sh                       # React local y servidor en el puerto 8765
node correr.js                      # escribe estrategias.json, divergencia.json, cronicas.json
node ablacion.js
./ver.sh 777 prudente "$(cat posturas_prudente.json)"
```

Necesita `playwright` de Node con Chromium. Los JSON de salida no se versionan.
