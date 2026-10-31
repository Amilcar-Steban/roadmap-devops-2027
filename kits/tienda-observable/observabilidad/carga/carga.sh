#!/bin/sh
# Unas 5 peticiones por segundo: sobre todo el catálogo, a veces un pedido.
# "Lazo abierto": cada petición sale en segundo plano y no espera a la anterior. Así se comportan
# los usuarios reales; si esperásemos cada respuesta, una API colgada frenaría la carga y las
# métricas mostrarían pocos errores justo cuando más gente está fallando.
i=0
while true; do
  curl -s -o /dev/null --max-time 20 http://proxy:8080/api/productos &
  i=$((i + 1))
  if [ $((i % 10)) -eq 0 ]; then
    curl -s -o /dev/null --max-time 20 -X POST -H 'content-type: application/json' \
      -d '{"producto_id": 3, "cantidad": 1}' http://proxy:8080/api/pedidos &
  fi
  sleep 0.2
done
