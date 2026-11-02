#!/usr/bin/env bash
# Pruebas del cliente Godot: corpus dorado del espejo, archivos dorados del
# protocolo y prueba de punta a punta con el núcleo real.
#
#   GODOT=/ruta/a/godot NUCLEO=/ruta/al/ejecutable/nucleo ./probar_cliente.sh
#
# Sin NUCLEO se saltan la prueba de integración.
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path cliente --import >/dev/null 2>&1 || true
echo "== espejo";    "$GODOT" --headless --path cliente --script res://pruebas/prueba_espejo.gd 2>&1 | grep -v "^Godot Engine"
echo "== protocolo"; "$GODOT" --headless --path cliente --script res://pruebas/prueba_protocolo.gd 2>&1 | grep -v "^Godot Engine"
if [ -n "${NUCLEO:-}" ]; then
  echo "== integración"
  PARTIDAS="$(mktemp -d)"
  "$NUCLEO" --puerto 4790 --partidas "$PARTIDAS" 2>/dev/null &
  PID=$!
  trap 'kill $PID 2>/dev/null || true' EXIT
  sleep 1
  "$GODOT" --headless --path cliente --script res://pruebas/prueba_integracion.gd -- --puerto 4790 2>&1 | grep -v "^Godot Engine"
  echo "== decisiones"
  "$NUCLEO" --puerto 4791 --partidas "$PARTIDAS" --guion pruebas_compartidas/guion_integracion.json 2>/dev/null &
  PID2=$!
  trap 'kill $PID $PID2 2>/dev/null || true' EXIT
  sleep 1
  "$GODOT" --headless --path cliente --script res://pruebas/prueba_decisiones.gd -- --puerto 4791 2>&1 | grep -v "^Godot Engine"
  echo "== fin de partida"
  "$NUCLEO" --puerto 4792 --partidas "$PARTIDAS" --guion pruebas_compartidas/guion_fin.json 2>/dev/null &
  PID3=$!
  trap 'kill $PID $PID2 $PID3 2>/dev/null || true' EXIT
  sleep 1
  "$GODOT" --headless --path cliente --script res://pruebas/prueba_fin.gd -- --puerto 4792 2>&1 | grep -v "^Godot Engine"
fi
