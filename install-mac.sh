#!/bin/sh
# Instala o reinstala Context Ledger en este Mac desde el repo público de versiones.
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
# sin permisos de administrador queda en ~/Applications; el actualizador la reemplaza donde esté
APPS="/Applications"
if [ ! -w "$APPS" ]; then
  APPS="$HOME/Applications"
  mkdir -p "$APPS"
fi
DEST="$APPS/Context Ledger.app"
OLD="$APPS/context-ledger.app"

URL=$(curl -fsSL "$MANIFEST" | tr ',' '\n' | grep -o 'https://[^"]*\.app\.tar\.gz' | head -1)
if [ -z "$URL" ]; then
  echo "No encontré una versión para macOS en $MANIFEST"
  exit 1
fi

TMP=$(mktemp -d)
trap 'if ! rm -rf "$TMP"; then echo "No pude limpiar la descarga en $TMP" >&2; fi' EXIT

echo "Descargando $URL"
curl -fsSL "$URL" -o "$TMP/app.tar.gz"
tar -xzf "$TMP/app.tar.gz" -C "$TMP"
APP=$(find "$TMP" -maxdepth 1 -name '*.app' | head -1)
if [ -z "$APP" ]; then
  echo "El paquete descargado no trae una .app"
  exit 1
fi
if [ ! -d "$APP/Contents" ]; then
  echo "El paquete descargado no trae Contents"
  exit 1
fi

# Valida antes de detener o mover la instalación existente.
PLIST="$APP/Contents/Info.plist"
if [ ! -f "$PLIST" ] || [ ! -r "$PLIST" ]; then
  echo "El paquete descargado no trae un Info.plist legible" >&2
  exit 1
fi
if ! EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST"); then
  echo "El paquete descargado no declara CFBundleExecutable" >&2
  exit 1
fi
case "$EXECUTABLE" in
  ''|.|..|*/*) echo "CFBundleExecutable no es un nombre de archivo válido" >&2; exit 1 ;;
esac
if [ ! -f "$APP/Contents/MacOS/$EXECUTABLE" ] || [ ! -x "$APP/Contents/MacOS/$EXECUTABLE" ]; then
  echo "El paquete descargado no trae su ejecutable con permiso de ejecución" >&2
  exit 1
fi

BACKUP=""
SAVED_CONTENTS=false
SAVED_OLD=false
RENAMED=false
restore() {
  # Solo movimientos hasta completar la instalación; nunca restaura desde una copia borrada.
  if [ "$SAVED_CONTENTS" = true ]; then
    # mv desde TMP puede cruzar volúmenes y dejar un destino parcial al fallar.
    if [ -e "$DEST/Contents" ]; then
      if ! mv "$DEST/Contents" "$BACKUP/Contents-rechazado"; then
        echo "No pude apartar la versión incompleta; recuperación en $BACKUP" >&2
        exit 1
      fi
    fi
    if ! mv "$BACKUP/Contents" "$DEST/Contents"; then
      echo "No pude restaurar Contents; recuperación en $BACKUP" >&2
      exit 1
    fi
  fi
  if [ "$SAVED_OLD" = true ]; then
    if ! mv "$BACKUP/context-ledger.app" "$OLD"; then
      echo "No pude restaurar la copia antigua; recuperación en $BACKUP" >&2
      exit 1
    fi
  fi
  if [ "$RENAMED" = true ]; then
    if ! mv "$DEST" "$OLD"; then
      echo "La app anterior sigue en $DEST; no pude devolverle el nombre" >&2
      exit 1
    fi
  fi
  if [ -n "$BACKUP" ]; then
    if ! rmdir "$BACKUP"; then echo "Quedó un respaldo en $BACKUP" >&2; fi
  fi
  exit 1
}

# Conserva la carpeta del paquete para que el Dock siga apuntando a la misma app.
pkill -f "$DEST/Contents/MacOS/" 2>/dev/null || true
if [ -d "$OLD" ]; then
  pkill -f "$OLD/Contents/MacOS/" 2>/dev/null || true
  if [ ! -e "$DEST" ]; then
    if ! mv "$OLD" "$DEST"; then
      echo "No pude renombrar la instalación anterior" >&2
      exit 1
    fi
    RENAMED=true
  fi
fi
if [ -d "$DEST" ]; then
  if ! BACKUP=$(mktemp -d "$APPS/.context-ledger-backup.XXXXXX"); then
    echo "No pude crear el respaldo" >&2
    restore
  fi
  if ! mv "$DEST/Contents" "$BACKUP/Contents"; then
    echo "No pude respaldar la instalación anterior" >&2
    restore
  fi
  SAVED_CONTENTS=true
  if [ -d "$OLD" ]; then
    if ! mv "$OLD" "$BACKUP/context-ledger.app"; then
      echo "No pude respaldar la copia antigua" >&2
      restore
    fi
    SAVED_OLD=true
  fi
  if ! mv "$APP/Contents" "$DEST/Contents"; then
    echo "No pude instalar la versión nueva" >&2
    restore
  fi
else
  if ! mv "$APP" "$DEST"; then
    echo "No pude instalar la app en $DEST" >&2
    restore
  fi
fi
# Desde aquí la app válida está instalada. Finder y open no deshacen la instalación;
# ante su fallo, se avisa y se conserva el respaldo para revisarlo.
FINAL_OK=true
if ! touch "$DEST"; then
  echo "Aviso: no pude refrescar la app en Finder. Respaldo: ${BACKUP:-no había instalación anterior}" >&2
  FINAL_OK=false
fi
if ! open "$DEST"; then
  echo "Aviso: no pude abrir la app. Respaldo: ${BACKUP:-no había instalación anterior}" >&2
  FINAL_OK=false
fi
if [ "$FINAL_OK" = true ]; then
  if [ -n "$BACKUP" ]; then
    if ! rm -rf "$BACKUP"; then
      echo "Aviso: la app quedó instalada; no pude limpiar el respaldo en $BACKUP" >&2
    fi
  fi
fi
echo "Instalada en $DEST"
