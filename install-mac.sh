#!/bin/sh
# Instala o reinstala context-ledger en este Mac desde el repo público de versiones.
# Se descarga con curl a propósito: lo bajado así no queda en cuarentena y la app
# (con firma local gratuita) abre sin avisos de Gatekeeper.
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/lmarciales/context-ledger-releases/main/install-mac.sh | sh
#   curl -fsSL …/install-mac.sh | sh -s -- 0.1.0    # una versión puntual, por ejemplo para probar el actualizador
set -eu

RELEASES="https://github.com/lmarciales/context-ledger-releases/releases"
if [ $# -gt 0 ]; then
  MANIFEST="$RELEASES/download/v${1#v}/latest.json"
else
  MANIFEST="$RELEASES/latest/download/latest.json"
fi
DEST="/Applications/context-ledger.app"

URL=$(curl -fsSL "$MANIFEST" | tr ',' '\n' | grep -o 'https://[^"]*\.app\.tar\.gz' | head -1)
if [ -z "$URL" ]; then
  echo "No encontré una versión para macOS en $MANIFEST"
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Descargando $URL"
curl -fsSL "$URL" -o "$TMP/app.tar.gz"
tar -xzf "$TMP/app.tar.gz" -C "$TMP"
APP=$(find "$TMP" -maxdepth 1 -name '*.app' | head -1)
if [ -z "$APP" ]; then
  echo "El paquete descargado no trae una .app"
  exit 1
fi

# cierra la versión anterior si está abierta, y la reemplaza
pkill -f "$DEST/Contents/MacOS/" 2>/dev/null || true
rm -rf "$DEST"
mv "$APP" "$DEST"
echo "Instalada en $DEST"
open "$DEST"
