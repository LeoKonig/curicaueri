#!/usr/bin/env python3
"""Agente de prueba: gobierna el impuesto interno de una facción.

Habla con el núcleo por la entrada y la salida estándar, una línea de JSON
por mensaje (contrato en pruebas_compartidas/protocolo/agente_*.json).

Regla, sin estado propio (todo sale de la vista del turno):
  - si el agravio de algún pop llega a 60, bajar el impuesto a 1;
  - si no, y el tesoro baja de 5000, subirlo a 5;
  - si no, dejarlo en 3, la tasa neutra.

Es la misma regla que agentes/mercury/agente.m: la prueba de los agentes
compara sus respuestas línea por línea.

Modos para probar la cáscara (no son agentes de verdad):
  --lento   tarda 2 s en responder (la cáscara debe sacarlo de la partida)
  --basura  responde algo que no es un plan (la cáscara debe descartarlo)
"""
import json
import sys
import time

UMBRAL_AGRAVIO = 60.0
UMBRAL_TESORO = 5000.0


def decidir(turno):
    max_agravio = 0.0
    tesoro = None
    for e in turno["entidades"]:
        mags = e["magnitudes"]
        if "agravio" in mags:
            max_agravio = max(max_agravio, float(mags["agravio"]["efectivo"]))
        campos = e["campos"]
        if e["ref"]["clase"] == "faccion" and "tesoro" in campos:
            tesoro = float(campos["tesoro"]["v"])
    if max_agravio >= UMBRAL_AGRAVIO:
        return 1, "agravio alto (%g)" % max_agravio
    if tesoro is not None and tesoro < UMBRAL_TESORO:
        return 5, "tesoro bajo (%g)" % tesoro
    return 3, "equilibrio"


def main():
    modo = sys.argv[1] if len(sys.argv) > 1 else ""
    for linea in sys.stdin:
        turno = json.loads(linea)
        if turno.get("tipo") != "agente_turno":
            continue
        if modo == "--lento":
            time.sleep(2)
        if modo == "--basura":
            print("esto no es un plan", flush=True)
            continue
        tasa, nota = decidir(turno)
        plan = {
            "tipo": "agente_plan",
            "tick": turno["tick"],
            "comandos": [{"tipo": "fijar_impuesto_interno", "valor": tasa}],
            "nota": nota,
        }
        print(json.dumps(plan, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
