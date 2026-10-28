#!/usr/bin/env bash
# Pruebas de los agentes externos.
#
#   NUCLEO=/ruta/al/ejecutable/nucleo ./probar_agentes.sh
#
# Si el agente de Mercury está compilado (agentes/mercury/agente) o hay un
# compilador de Mercury (mmc) para compilarlo, también se prueba; si no, esa
# parte se salta y lo dice.
set -uo pipefail
cd "$(dirname "$0")"
NUCLEO="${NUCLEO:?define NUCLEO con la ruta al ejecutable del núcleo}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FALLOS=0
ok()    { echo "  ✔ $1"; }
falla() { echo "  ✘ $1"; FALLOS=$((FALLOS + 1)); }

# Compara dos archivos JSON Lines por contenido (no por bytes ni orden de claves).
iguales_json() {
  python3 -I - "$1" "$2" <<'PY'
import json, sys
a = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
b = [json.loads(l) for l in open(sys.argv[2]) if l.strip()]
sys.exit(0 if a == b else 1)
PY
}

responder_casos() {   # $1: comando del agente; salida: una respuesta por caso
  for f in agentes/casos/0*.json; do $1 < "$f"; done
}

echo "== casos compartidos (misma regla en todos los agentes)"
responder_casos "python3 agentes/python/agente.py" > "$TMP/python.jsonl"
if iguales_json "$TMP/python.jsonl" agentes/casos/esperado.jsonl; then ok "Python responde lo esperado en los 4 casos"; else falla "Python no responde lo esperado"; fi

MERCURY=""
if [ -x agentes/mercury/agente ]; then
  MERCURY="agentes/mercury/agente"
elif command -v mmc >/dev/null 2>&1; then
  (cd agentes/mercury && mmc --make agente >/dev/null 2>&1) && MERCURY="agentes/mercury/agente"
  [ -z "$MERCURY" ] && falla "mmc está instalado pero el agente de Mercury no compila (cd agentes/mercury && mmc --make agente)"
fi
if [ -n "$MERCURY" ]; then
  responder_casos "$MERCURY" > "$TMP/mercury.jsonl"
  if iguales_json "$TMP/mercury.jsonl" agentes/casos/esperado.jsonl; then ok "Mercury responde lo mismo que Python en los 4 casos"; else falla "Mercury no responde lo esperado"; diff "$TMP/mercury.jsonl" agentes/casos/esperado.jsonl; fi
else
  echo "  – agente de Mercury: sin compilar y sin mmc; se salta"
fi

echo "== repetición con el registro"
"$NUCLEO" --sin-cliente --ticks 730 --agente "python3 agentes/python/agente.py" --registro-agente "$TMP/reg.jsonl" --volcar "$TMP/real.json" 2>/dev/null
"$NUCLEO" --sin-cliente --ticks 730 --reproducir-agente "$TMP/reg.jsonl" --volcar "$TMP/repetida.json" 2>/dev/null
"$NUCLEO" --sin-cliente --ticks 730 --volcar "$TMP/sin_agente.json" 2>/dev/null
if cmp -s "$TMP/real.json" "$TMP/repetida.json"; then ok "la partida repetida con el registro es idéntica a la real"; else falla "la partida repetida difiere de la real"; fi
if ! cmp -s "$TMP/real.json" "$TMP/sin_agente.json"; then ok "el agente cambia la partida (difiere de jugar sin agente)"; else falla "el agente no cambió nada"; fi
N=$(grep -c . "$TMP/reg.jsonl")
if [ "$N" -eq 36 ]; then ok "36 turnos anotados en dos años (18 veintenas por año)"; else falla "se esperaban 36 turnos y hay $N"; fi

if [ -n "$MERCURY" ]; then
  "$NUCLEO" --sin-cliente --ticks 730 --agente "$MERCURY" --registro-agente "$TMP/reg_m.jsonl" --volcar "$TMP/real_m.json" 2>/dev/null
  if cmp -s "$TMP/real.json" "$TMP/real_m.json"; then ok "la partida con el agente de Mercury es idéntica a la de Python"; else falla "la partida con Mercury difiere de la de Python"; fi
fi

echo "== agentes que fallan"
"$NUCLEO" --sin-cliente --ticks 100 --agente "python3 agentes/python/agente.py --lento" --agente-espera 300 --registro-agente "$TMP/lento.jsonl" --volcar "$TMP/lento.json" 2>/dev/null
"$NUCLEO" --sin-cliente --ticks 100 --volcar "$TMP/nulo.json" 2>/dev/null
if head -1 "$TMP/lento.jsonl" | grep -q "tiempo agotado" && sed -n 2p "$TMP/lento.jsonl" | grep -q "fuera de la partida"; then ok "un agente lento queda fuera tras el tiempo límite, y se anota"; else falla "el agente lento no se trató como se esperaba"; fi
if cmp -s "$TMP/lento.json" "$TMP/nulo.json"; then ok "sin respuestas, la facción sigue como con el agente nulo"; else falla "el agente lento alteró la partida"; fi
"$NUCLEO" --sin-cliente --ticks 100 --agente "python3 agentes/python/agente.py --basura" --registro-agente "$TMP/basura.jsonl" --volcar "$TMP/basura.json" 2>/dev/null
if [ "$(grep -c 'respuesta inválida' "$TMP/basura.jsonl")" -eq 5 ]; then ok "las respuestas que no son un plan se descartan y se anotan (5 de 5)"; else falla "las respuestas basura no se anotaron como inválidas"; fi
if cmp -s "$TMP/basura.json" "$TMP/nulo.json"; then ok "la basura no alteró la partida"; else falla "la basura alteró la partida"; fi

echo "agentes: $FALLOS fallos"
exit $((FALLOS > 0))
