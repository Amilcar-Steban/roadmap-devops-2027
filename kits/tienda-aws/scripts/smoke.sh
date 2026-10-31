#!/usr/bin/env bash
# Comprueba que un despliegue responde. Uso: scripts/smoke.sh https://staging.tienda.ejemplo.com
set -Eeuo pipefail
base="${1:?Falta la URL base}"

comprobar() {
  local ruta="$1" esperado="$2" codigo=""
  for _ in 1 2 3 4 5; do
    codigo="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$base$ruta" || true)"
    if [[ "$codigo" == "$esperado" ]]; then
      echo "OK     $ruta -> $codigo"
      return 0
    fi
    sleep 3
  done
  echo "FALLO  $ruta -> $codigo (esperado $esperado)"
  return 1
}

comprobar / 200
comprobar /api/productos 200
comprobar /api/pedidos 200
