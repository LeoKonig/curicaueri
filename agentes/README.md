# Agentes externos

Un agente externo es otro programa que decide por una facción. Puede estar escrito en cualquier lenguaje: habla con el núcleo por su entrada y su salida estándar, una línea de JSON por mensaje.

| Carpeta | Qué es |
| --- | --- |
| `python/` | Agente de prueba en Python. Se verifica en cada corrida de `probar_agentes.sh` |
| `mercury/` | El mismo agente en Mercury, con su propio lector de JSON. **Escrito pero no compilado todavía**: ver abajo |
| `casos/` | Cuatro turnos con la respuesta esperada. Todos los agentes deben responder lo mismo |

## El contrato

Al empezar cada periodo (cada veintena, en el prototipo), el núcleo escribe un turno:

```json
{"tipo": "agente_turno", "version": 1, "faccion": 1, "tick": 20, "semilla": 1033286,
 "reloj": {...}, "entidades": [...]}
```

Las entidades tienen la misma forma que en la instantánea del cliente: campos y magnitudes con su desglose. El agente responde con un plan:

```json
{"tipo": "agente_plan", "tick": 20, "comandos": [{"tipo": "fijar_impuesto_interno", "valor": 3}], "nota": "equilibrio"}
```

Los ejemplos completos son `pruebas_compartidas/protocolo/agente_turno.json` y `agente_plan.json`.

**Reglas que aplica el núcleo:**

- Los comandos del plan entran por la misma cola que los del jugador y se validan igual: uno inválido se rechaza sin tocar el estado.
- Si el agente tarda más que el límite (`--agente-espera`, 500 ms por omisión), queda fuera de la partida y su facción sigue sin agente. No se le vuelve a preguntar, porque una respuesta tardía llegaría desfasada.
- Una respuesta que no es un plan, o que es de otro tick, se descarta y se anota; el agente sigue en la partida.
- Todo se anota con `--registro-agente`. Con `--reproducir-agente`, la partida se repite exactamente sin el programa: es la ley del agente externo del documento funcional.
- El agente debe ser determinista. Si usa azar, debe sacarlo de `semilla`, que cambia en cada turno y se repite al repetir la partida.
- Lo que el agente escriba en su salida de errores aparece en la consola del núcleo.

## Usarlo

```sh
nucleo --agente "python3 agentes/python/agente.py"                    # con cliente
nucleo --sin-cliente --ticks 730 --agente "agentes/mercury/agente" \
       --registro-agente registro.jsonl --volcar final.json           # sin cliente
nucleo --sin-cliente --ticks 730 --reproducir-agente registro.jsonl   # repetir sin el programa
```

En el prototipo hay una sola facción, así que el agente gobierna el reino del jugador (`--agente-faccion 1`). Sin cliente, sirve también como arnés: muchas partidas simuladas con una regla, que es lo que pide el hito 0.

## El agente en Mercury

`mercury/agente.m` implementa la misma regla que el de Python. La decisión es un predicado `det`: el compilador garantiza que siempre da exactamente un plan. Leer el JSON es `semidet`: si una línea no es un turno válido, el agente no responde.

**No se compiló al escribirlo:** el entorno donde se escribió no tenía el compilador de Mercury. Para compilarlo:

1. Instala Mercury desde su sitio oficial (`mercurylang.org`), que ofrece paquetes y código fuente.
2. Compila:
   ```sh
   cd agentes/mercury
   mmc --make agente
   ```
3. Corre `NUCLEO=… ./probar_agentes.sh` desde la raíz. Al encontrar `agentes/mercury/agente`, comprueba que responde lo mismo que Python en los cuatro casos y que una partida de dos años con Mercury es idéntica byte a byte a la de Python.

Si el compilador se queja, lo más probable es un detalle de sintaxis o de la biblioteca estándar según la versión de Mercury. El diseño (lector, regla, bucle) no cambia.

## Escribir un agente nuevo

1. Lee líneas de la entrada estándar; ignora las que no sean `agente_turno`.
2. Por cada turno, escribe una línea con un `agente_plan` del mismo `tick` y vacía el búfer de salida.
3. Pruébalo con los turnos de `casos/` y luego con `--sin-cliente`.

Los comandos válidos y sus rangos están en el catálogo (`pruebas_compartidas/protocolo/catalogo.json` muestra la forma; los del juego purépecha están en `nucleo/reglas/src/Reglas/Comando.hs`).
