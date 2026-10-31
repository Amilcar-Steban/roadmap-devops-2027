#!/usr/bin/env bash
# Lista de verificación de la pila, automatizada. Uso: ./scripts/verify.sh [--parada]
#   --parada  además mide cuánto tarda la API en detenerse (la para y la vuelve a arrancar)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

correctas=0; fallidas=0
pasa()  { printf '  \033[32mOK\033[0m     %s\n' "$1"; correctas=$((correctas + 1)); }
falla() { printf '  \033[31mFALLO\033[0m  %s\n' "$1"; fallidas=$((fallidas + 1)); }
comprueba() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then pasa "$desc"; else falla "$desc"; fi; }

todos_sanos()       { ! docker compose ps --format '{{.Service}} {{.Health}}' | awk '$2 != "" && $2 != "healthy"' | grep -q .; }
sin_root()          { [[ "$(docker compose exec -T "$1" id -u)" != "0" ]]; }
publicos()          { docker compose ps --format '{{.Ports}}' | tr ',' '\n' | grep -- '->' | grep -v '127.0.0.1:' || true; }
proxy_responde()    { curl -fsS --max-time 5 http://127.0.0.1:8080/ | grep -qi '<html'; }
api_responde()      { curl -fsS --max-time 5 http://127.0.0.1:8080/api/productos | grep -q productos; }
db_sin_internet()   { ! docker compose exec -T db wget -q -T 3 -O /dev/null https://example.com; }
api_solo_lectura()  { ! docker compose exec -T api touch /app/prueba-escritura; }
api_read_only()     { [[ "$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' "$(docker compose ps -q api | head -n 1)")" == "true" ]]; }

echo "Estado"
comprueba "todos los servicios con healthcheck están healthy" todos_sanos
comprueba "el proxy sirve el frontend en 127.0.0.1:8080"      proxy_responde
comprueba "la API responde a través del proxy"                 api_responde

echo "Seguridad"
comprueba "api no corre como root"       sin_root api
comprueba "frontend no corre como root"  sin_root frontend
comprueba "proxy no corre como root"     sin_root proxy
expuestos="$(publicos | tr '\n' ' ')"
if [[ -z "$expuestos" ]]; then pasa "solo hay puertos publicados en 127.0.0.1"; else falla "puertos publicados hacia fuera: $expuestos"; fi
comprueba "la base de datos no tiene salida a internet (red internal)" db_sin_internet
if api_read_only; then
  comprueba "la API tiene el sistema de archivos en solo lectura" api_solo_lectura
else
  echo "  (sin compose.prod.yaml: no se comprueba read_only)"
fi

if [[ "${1:-}" == "--parada" ]]; then
  echo "Parada"
  inicio=$(date +%s)
  docker compose stop api >/dev/null 2>&1
  dur=$(( $(date +%s) - inicio ))
  docker compose start api >/dev/null 2>&1
  if (( dur <= 3 )); then pasa "la API se detiene en ${dur} s"; else falla "la API tarda ${dur} s en detenerse (¿forma shell en CMD?)"; fi
fi

echo
echo "Resultado: $correctas correctas, $fallidas fallidas"
(( fallidas == 0 ))
