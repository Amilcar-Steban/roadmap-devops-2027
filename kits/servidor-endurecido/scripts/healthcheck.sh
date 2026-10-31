#!/usr/bin/env bash
# Comprueba disco, memoria y la API. Sale con 1 si algo falla,
# y systemd marca health.service como failed (visible en systemctl --failed).
# Sin "set -e" a propósito: queremos ejecutar todas las comprobaciones.
set -uo pipefail

URL="${HEALTH_URL:-http://127.0.0.1:8080/api/health}"
UMBRAL_DISCO="${UMBRAL_DISCO:-85}"
MIN_MEM_MB="${MIN_MEM_MB:-150}"
fallo=0

uso="$(df --output=pcent / | tail -n 1 | tr -dc '0-9')"
if (( uso >= UMBRAL_DISCO )); then
  echo "FALLO disco: / al ${uso} %"; fallo=1
else
  echo "OK    disco: / al ${uso} %"
fi

mem="$(awk '/MemAvailable/ {print int($2 / 1024)}' /proc/meminfo)"
if (( mem < MIN_MEM_MB )); then
  echo "FALLO memoria disponible: ${mem} MB"; fallo=1
else
  echo "OK    memoria disponible: ${mem} MB"
fi

if curl -fsS --max-time 5 "$URL" >/dev/null; then
  echo "OK    api: $URL"
else
  echo "FALLO api: $URL"; fallo=1
fi

exit "$fallo"
