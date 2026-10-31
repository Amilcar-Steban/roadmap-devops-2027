#!/usr/bin/env bash
# Se ejecuta EN EL SERVIDOR (desde el pipeline por SSH, o a mano).
# Uso: scripts/deploy.sh <etiqueta>   Despliega esa versión y, si no queda sana, vuelve a la anterior.
# Requiere en .env las variables de producción (COMPOSE_FILE, GHCR_USER...) de .env.example.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

nueva="${1:?Uso: deploy.sh <etiqueta>}"
[[ "$nueva" =~ ^(sha-[0-9a-f]{7}|[0-9]+\.[0-9]+\.[0-9]+)$ ]] || { echo "Etiqueta no válida: $nueva" >&2; exit 2; }
anterior="$(cat .version-actual 2>/dev/null || true)"
espera="${WAIT_TIMEOUT:-120}"

desplegar() {
  printf 'TAG=%s\n' "$1" > .env.version
  docker compose --env-file .env --env-file .env.version pull --quiet api frontend
  docker compose --env-file .env --env-file .env.version up -d --wait --wait-timeout "$espera"
}

echo "Desplegando $nueva (anterior: ${anterior:-ninguna})"
if desplegar "$nueva"; then
  echo "$nueva" > .version-actual
  echo "OK: $nueva en marcha"
  exit 0
fi

echo "FALLO: $nueva no quedó sana" >&2
if [[ -n "$anterior" ]]; then
  echo "Volviendo a $anterior"
  desplegar "$anterior"
fi
exit 1
