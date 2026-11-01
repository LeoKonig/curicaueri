#!/usr/bin/env bash
# Prepara el arnés: React local (el prototipo lo pide a unpkg.com) y un servidor
# para la carpeta hito_0. Requiere node, npm, python3 y playwright de Node con Chromium.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p vendor && cd vendor
for p in react react-dom; do
  [ -d "$p-18.3.1" ] && continue
  npm pack "$p@18.3.1" --silent >/dev/null
  mkdir -p "$p-18.3.1" && tar xzf "$p-18.3.1.tgz" -C "$p-18.3.1"
done
cd ..
python3 -m http.server 8765 --directory .. >/dev/null 2>&1 &
echo "servidor en http://127.0.0.1:8765 (pid $!)"
