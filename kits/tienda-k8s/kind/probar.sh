#!/usr/bin/env bash
# Prueba de humo de la tienda en el laboratorio: frontend, API, un pedido y el aislamiento de red.
# Uso: ./kind/abrir-tienda.sh en otra terminal y, después, ./kind/probar.sh
set -Eeuo pipefail

URL="${URL:-http://tienda.localhost:8080}"
fallos=0
comprobar() { # descripción, comando
  if eval "$2" >/dev/null 2>&1; then echo "  ok   $1"; else echo "  FALLO $1"; fallos=$((fallos + 1)); fi
}

echo "Tienda en $URL"
comprobar "el frontend responde" "curl -fsS --max-time 5 $URL/"
comprobar "la API lista productos" "curl -fsS --max-time 5 $URL/api/productos | grep -q Camiseta"
comprobar "se puede crear un pedido" \
  "curl -fsS --max-time 5 -X POST -H 'content-type: application/json' -d '{\"producto_id\":1,\"cantidad\":1}' $URL/api/pedidos"
comprobar "un host desconocido recibe 404" \
  "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H 'Host: otro.localhost' ${URL/tienda.localhost/127.0.0.1}/)\" = 404 ]"
comprobar "desde otro namespace NO se llega a la API (NetworkPolicy)" \
  "! kubectl run sonda-red -n default --rm -i --restart=Never --image=busybox:1.37 --command -- wget -qO- -T 3 http://tienda-api.tienda/health"
comprobar "la API NO sale a Internet (NetworkPolicy de salida)" \
  "! kubectl exec -n tienda deploy/tienda-api -- python -c \"import socket; socket.create_connection(('1.1.1.1', 443), timeout=3)\""
comprobar "un pod como root es rechazado (Pod Security restricted)" \
  "! kubectl run sonda-root -n tienda --restart=Never --image=busybox:1.37 --dry-run=server -- true"

if (( fallos > 0 )); then
  echo "$fallos comprobaciones fallidas"
  exit 1
fi
echo "Todo correcto"
