#!/usr/bin/env bash
# Hace backup comprimido de un directorio y conserva solo los N más recientes.
# Uso: backup.sh -s /var/www -d /backups [-k 7]
set -Eeuo pipefail

SRC=""; DEST=""; KEEP=7
log() { echo "[backup] $(date +%FT%T) $*" >&2; }

usage() { echo "Uso: $0 -s ORIGEN -d DESTINO [-k CANTIDAD]"; exit 2; }

while getopts ":s:d:k:h" opt; do
  case "$opt" in
    s) SRC="$OPTARG" ;;
    d) DEST="$OPTARG" ;;
    k) KEEP="$OPTARG" ;;
    h|*) usage ;;
  esac
done
[[ -d "$SRC" ]]  || { log "Origen no existe: $SRC"; usage; }
mkdir -p "$DEST"

TMP="$(mktemp)"
trap 'rm -f "$TMP"; log "Limpieza hecha"' EXIT        # se ejecuta siempre al salir
trap 'log "Falló en la línea $LINENO"' ERR

nombre="$(basename "$SRC")-$(date +%Y%m%d-%H%M%S).tar.gz"
log "Creando $nombre"
tar -czf "$TMP" -C "$(dirname "$SRC")" "$(basename "$SRC")"
mv "$TMP" "$DEST/$nombre"

log "Rotando: se conservan $KEEP"
ls -1t "$DEST"/*.tar.gz | tail -n +"$((KEEP + 1))" | xargs -r rm -f

tam="$(du -h "$DEST/$nombre" | cut -f1)"
log "OK: $DEST/$nombre ($tam)"