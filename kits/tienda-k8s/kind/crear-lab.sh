#!/usr/bin/env bash
# Clúster kind de 3 nodos con lo necesario para la tienda: Calico (NetworkPolicies de entrada y salida),
# Gateway API + Envoy Gateway y metrics-server (para el HPA). Idempotente: si el clúster existe, solo completa lo que falte.
# Requiere: docker, kind, kubectl y helm 3.18+ o 4.
set -Eeuo pipefail

CLUSTER="${1:-lab}"
CALICO="v3.33.0"
ENVOY_GATEWAY="v1.9.3"
METRICS_SERVER="3.14.0" # versión del chart (metrics-server 0.9)
cd "$(dirname "$0")"

if ! grep -qx "$CLUSTER" <<<"$(kind get clusters)"; then
  kind create cluster --name "$CLUSTER" --config kind-config.yaml
fi
kubectl config use-context "kind-$CLUSTER"

echo "== Calico $CALICO (los nodos no están Ready hasta que hay un CNI)"
kubectl apply --server-side -f "https://raw.githubusercontent.com/projectcalico/calico/$CALICO/manifests/calico.yaml" >/dev/null
kubectl -n kube-system rollout status ds/calico-node --timeout 5m
kubectl wait --for=condition=Ready nodes --all --timeout 3m

echo "== Envoy Gateway $ENVOY_GATEWAY (incluye los CRDs de Gateway API)"
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm --version "$ENVOY_GATEWAY" \
  -n envoy-gateway-system --create-namespace --wait --timeout 5m

kubectl apply -f - <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
YAML

echo "== metrics-server (kind usa certificados autofirmados en el kubelet)"
helm upgrade --install metrics-server metrics-server --repo https://kubernetes-sigs.github.io/metrics-server/ \
  --version "$METRICS_SERVER" -n kube-system --set 'args={--kubelet-insecure-tls}' --wait --timeout 5m

echo "== Namespace tienda con Pod Security restricted"
kubectl create namespace tienda --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace tienda --overwrite \
  pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted

kubectl get nodes -o wide
echo "Listo. Instala la tienda con:"
echo "  helm upgrade --install tienda ../chart/tienda -n tienda -f ../chart/tienda/values-kind.yaml --set imagen.registro=ghcr.io/TU-USUARIO"
