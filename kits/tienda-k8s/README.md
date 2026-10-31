# La tienda en Kubernetes (Fase 5)

Chart de Helm de la tienda (API + frontend), un laboratorio completo en kind y la capa EKS para el
repositorio de infraestructura de la Fase 4. Se añade al repositorio `tienda-pipeline`.

```
chart/tienda/          el chart: Deployments, Services, HPA, PDB, HTTPRoute, NetworkPolicies, ExternalSecret
  values.yaml          valores por defecto (seguros, de producción)
  values-kind.yaml     laboratorio: PostgreSQL y Valkey dentro del clúster, Gateway propio
  values-prod.yaml     EKS: RDS, ElastiCache y secreto desde Secrets Manager
  tests/               pruebas unitarias (helm-unittest)
kind/                  crear-lab.sh · abrir-tienda.sh · probar.sh · kind-config.yaml
eks/main.tf            capa "cluster" para tienda-infra (Fase 4): EKS 1.37, Graviton, Pod Identity
.github/workflows/k8s.yml   valida el chart en cada PR y (opcional) despliega en EKS desde main
```

## Laboratorio en tu portátil (gratis)

Necesitas Docker, kind, kubectl y Helm 4 (instalación en "Prepara tu equipo" de la Fase 5).

```bash
./kind/crear-lab.sh                       # kind 1.37 + Calico + Envoy Gateway + metrics-server, ~3 min
helm upgrade --install tienda chart/tienda -n tienda -f chart/tienda/values-kind.yaml \
  --set imagen.registro=ghcr.io/TU-USUARIO --rollback-on-failure --timeout 5m
./kind/abrir-tienda.sh                    # en otra terminal: http://tienda.localhost:8080
./kind/probar.sh                          # 7 comprobaciones, incluidas red (entrada y salida) y Pod Security
kind delete cluster --name lab            # al terminar
```

Las imágenes son las que publica el workflow Imagen de la Fase 2 en GHCR. Si tus paquetes son
privados, hazlos públicos en GitHub (Package settings → Change visibility) o crea un
`imagePullSecret`.

La base de datos del laboratorio vive en un `emptyDir`: si reinicias PostgreSQL, vuelve vacía y la
API devuelve 500 hasta que la reinicias (`kubectl rollout restart deploy/tienda-api -n tienda`),
porque crea el esquema al arrancar. En EKS los datos están en RDS.

## Qué demuestra cada pieza

| Prueba | Cómo | Resultado esperado |
|---|---|---|
| Actualizar sin cortes | bucle de `curl` + `helm upgrade --set api.etiqueta=sha-…` | 0 errores (`maxUnavailable: 0`, readiness, `preStop`) |
| Perder un nodo | bucle de `curl` + `kubectl drain lab-worker --ignore-daemonsets --delete-emptydir-data` | 0 errores: el PDB espera a que haya otra réplica lista |
| La base se cae | `kubectl scale deploy/postgres --replicas=0 -n tienda` | la API sale del Service (readiness) pero **no se reinicia** (liveness por TCP) |
| Red cerrada | `./kind/probar.sh` | desde otro namespace no se llega a la API; la API no sale a internet (con Calico: el CNI de kind no aplica la salida) |
| Migraciones | `--set migraciones.job=true` | un Job (hook de Helm) crea el esquema con el dueño y la API arranca sin crear tablas (en prod, activado) |
| Seguridad | `kubectl run x --image=busybox -n tienda` | rechazado por Pod Security `restricted` |
| Autoescalado | carga con `hey` o un bucle y `kubectl get hpa -w` | el HPA sube réplicas al pasar del 70 % de CPU |

## En EKS

1. Copia `eks/main.tf` a `entornos/dev/cluster/` en tienda-infra, ajusta el bucket del estado y
   aplícalo después de `red` y `datos` (unos 15 minutos).
2. Instala en el clúster Envoy Gateway (o el AWS Load Balancer Controller), External Secrets con su
   `ClusterSecretStore` `aws-secrets-manager`, y metrics-server.
3. Rellena `values-prod.yaml` con las salidas de la Fase 4 (endpoint de RDS y de la caché, ARN del
   secreto, CIDRs de las subredes de datos).
4. Variables del repositorio: `EKS_DEPLOY_ROLE_ARN` y `EKS_CLUSTER`. Desde ese momento, cada push a
   main con cambios en `chart/` despliega con `helm upgrade --rollback-on-failure`.

Un clúster EKS cobra por hora: `terraform destroy` al terminar, y revisa que no queden balanceadores
ni volúmenes EBS huérfanos.

## Qué aprendí

(Cuánto tardó cada prueba, qué falló la primera vez, capturas de `kubectl get hpa -w` y del drain.)
