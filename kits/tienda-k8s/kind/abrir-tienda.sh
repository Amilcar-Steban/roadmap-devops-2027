#!/usr/bin/env bash
# Abre el Gateway de la tienda en http://tienda.localhost:8080 (port-forward al Service de Envoy).
# *.localhost resuelve a 127.0.0.1 en macOS, Linux y Windows sin tocar /etc/hosts.
set -Eeuo pipefail

NS="${1:-tienda}"
SEL="gateway.envoyproxy.io/owning-gateway-namespace=$NS"
svc="$(kubectl get svc -n envoy-gateway-system -l "$SEL" -o name | head -n1)"
[[ -n "$svc" ]] || { echo "No encuentro el Service del Gateway de $NS. ¿Está instalada la tienda?" >&2; exit 1; }
# Envoy Gateway crea el proxy al ver el Gateway: espera a que esté listo
kubectl wait deploy -n envoy-gateway-system -l "$SEL" --for=condition=Available --timeout=180s
echo "Tienda en http://tienda.localhost:8080 (Ctrl+C para cerrar)"
exec kubectl port-forward -n envoy-gateway-system "$svc" 8080:80
