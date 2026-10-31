# Evaluación automática del prototipo del hito 0

Juega el prototipo HTML (`../Hito 0 v5 - Reino purepecha.dc.html`) desde dentro de la página, sin interfaz, para medir si sus decisiones importan y dónde puede aburrir la espera. Los resultados y el diagnóstico están en `docs/evaluacion_hito0.md`.

| Archivo | Qué hace |
| --- | --- |
| `arnes.js` | Se inyecta en la página. Crea partidas con una semilla, define estrategias (cómo elegir en eventos y crisis, y qué hacer cada veintena) y juega partidas completas. Registra decisiones, veredicto, métricas finales y la clase de cada veintena para el modelo de espera: D (decisión), A (anticipación) o V (vacía) |
| `correr.js` | Ocho estrategias × 60 partidas, y el experimento de divergencia: invierte una sola decisión de un evento y la compara con perturbar solo el azar. Escribe `estrategias.json`, `divergencia.json` y `cronicas.json` |
| `analizar.py` | Resume esos JSON: tabla de estrategias, criterios de tensión (a)–(e) y modelo de espera |
| `validar_opciones.py` | Criterio (c): falla si alguna opción de evento o crisis no tiene costo, riesgo diferido declarado (`riesgo`) ni es consecuencia de una decisión anterior (`consecuencia_de`) |
| `ablacion.js` | La estrategia experta cambiando una sola cosa cada vez |
| `voz.js`, `ver.sh` | Partida "en voz alta": avanza hasta la siguiente situación sin postura fijada y la muestra como la ve el jugador. Las posturas de los perfiles están en `posturas_*.json` |
| `i18n.js` | Comprueba que los textos no tengan marcadores sin resolver |
| `captura.js` | Capturas de la interfaz real (modal de invasión y pantalla final) |
| `sonda.js` | Una partida por estrategia, para detectar errores rápido |

```sh
./preparar.sh                 # React local y servidor en el puerto 8765
node correr.js && python3 analizar.py
python3 validar_opciones.py
./ver.sh 777 prudente "$(cat posturas_prudente.json)"
```

Necesita `playwright` de Node con Chromium. Los JSON de salida y `vendor/` no se versionan.
