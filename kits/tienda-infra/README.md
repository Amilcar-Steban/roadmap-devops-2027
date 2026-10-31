# tienda-infra

La arquitectura AWS de la tienda (Fase 3) como código: Terraform u OpenTofu, en módulos y capas,
con dos entornos, estado remoto, pruebas, políticas y un pipeline de pull requests. Proyecto de la
Fase 4 del Roadmap DevOps 2027.

```
modules/          red · datos · app · edge · bucket-seguro   (cada uno con tests/ que no necesitan AWS)
entornos/dev/     red/ datos/ app/ edge/                      una carpeta y un estado por capa
entornos/prod/    red/ datos/ app/ edge/
bootstrap/        bucket de estados, proveedor OIDC de GitHub, roles de plan y apply (una sola vez)
policy/           reglas de conftest sobre el plan, con sus pruebas
ansible/          el servidor de la Fase 0 con roles idempotentes
.github/workflows terraform.yml (PR → plan, main → apply) · aplicar.yml · deriva.yml
```

## Cómo se conectan las capas

| Capa  | Lee de                                          | Publica                                  |
|-------|-------------------------------------------------|------------------------------------------|
| red   | —                                               | VPC y subredes, con etiquetas `Name` y `tipo` |
| datos | VPC y subredes `tipo=datos` por etiquetas       | `/tienda/<entorno>/datos/*` en Parameter Store |
| app   | subredes `publica`/`privada` y `/…/datos/*`     | `/tienda/<entorno>/app/alb_dns`          |
| edge  | `/…/app/alb_dns`                                | URL, bucket y distribución               |

Ninguna capa lee el estado de otra (`terraform_remote_state`): así un rol solo necesita permisos
sobre su propio estado, y una capa puede reescribirse sin romper a las demás.

| | dev | prod |
|---|---|---|
| NAT Gateway | uno | uno por AZ |
| RDS | single-AZ, sin protección | Multi-AZ, `deletion_protection` y snapshot final |
| Valkey | 1 nodo | primario + réplica con failover |
| Tareas ECS | 1–2 de 0,25 vCPU | 2–6 de 0,5 vCPU |

## Probar sin AWS

```bash
for m in modules/*/; do terraform -chdir="$m" init -backend=false && terraform -chdir="$m" test; done
tflint --init && tflint --recursive --config "$PWD/.tflint.hcl"
trivy config --severity HIGH,CRITICAL .
conftest verify -p policy
```

Funciona igual con `tofu` en lugar de `terraform` (OpenTofu 1.11 o posterior).

## Desplegar

1. **Bootstrap** (una vez, con tu perfil de administrador):
   ```bash
   aws sso login --profile lab && export AWS_PROFILE=lab
   terraform -chdir=bootstrap init
   terraform -chdir=bootstrap apply -var="repo=TU-USUARIO/tienda-infra"
   ```
   Sustituye `tienda-tfstate-123456789012` por la salida `bucket_estado` en `entornos/*/*/main.tf`
   (`grep -rl 123456789012 entornos | xargs sed -i.bak "s/123456789012/TU_CUENTA/"`).
2. **Bloqueo de proveedores para todo el equipo** (Linux del CI, Mac y Windows):
   ```bash
   for d in entornos/*/*/ bootstrap; do
     terraform -chdir="$d" init -backend=false
     terraform -chdir="$d" providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=windows_amd64
   done
   git add '**/.terraform.lock.hcl'
   ```
3. **Primera creación de un entorno**: las capas leen a las anteriores, así que la primera vez se
   aplican en orden (`red`, `datos`, `app`, `edge`), con tu perfil:
   `terraform -chdir=entornos/dev/red init && terraform -chdir=entornos/dev/red apply`, y así con cada capa.
4. **GitHub**: variable de repositorio `AWS_PLAN_ROLE_ARN` y, en los entornos `desarrollo` y
   `produccion` (este con revisores obligatorios), la variable `AWS_APPLY_ROLE_ARN`. Desde ese momento,
   los cambios solo entran por pull request.
5. **La aplicación**: en el repositorio de la Fase 2/3 (`tienda-pipeline`), apunta el workflow
   Deploy AWS a lo que acabas de crear: variables `ECR_REPOSITORY` (la parte de `ecr_url` tras la
   barra), `ECS_CLUSTER`, `ECS_SERVICE`, `WEB_BUCKET` y `CF_DISTRIBUTION` (salidas de las capas app y
   edge), y regenera la definición de tarea a partir de la que creó Terraform:
   ```bash
   aws ecs describe-task-definition --task-definition tienda-prod-api --query taskDefinition \
     | jq 'del(.taskDefinitionArn,.revision,.status,.requiresAttributes,.compatibilities,.registeredAt,.registeredBy)' \
     > aws/ecs/task-definition.json
   ```
   Ajusta también la familia y los roles en `aws/iam/gha-deploy-politica.json` (`tienda-prod-api`,
   `tienda-prod-ecs-execution`, `tienda-prod-api-task`).

## Destruir dev

En orden inverso: `edge`, `app`, `datos`, `red`. Revisa al día siguiente Cost Explorer y
`aws/costes-olvidados.sh` (Fase 3).

## Decisiones

- **Carpetas por entorno y no workspaces**: se ve en qué entorno estás, y cada uno puede tener su
  cuenta, su backend y su versión de los módulos.
- **Un estado por capa**: un error en `app` no puede tocar la base de datos, y los planes son rápidos.
- **Ningún secreto en Terraform**: RDS genera la contraseña y la guarda en Secrets Manager; ECS la
  inyecta en el contenedor. En el estado solo está el ARN del secreto.
- **`deletion_protection` en lugar de `prevent_destroy`**: `prevent_destroy` no admite variables, y
  la protección de AWS funciona también si alguien intenta borrar desde la consola.
- **El servicio ignora `task_definition` y `desired_count`**: las versiones las publica el pipeline de
  la aplicación y el número de tareas lo decide el autoescalado.
- **Se aplica el plan revisado**: el job de main guarda el plan y el apply usa exactamente ese archivo.

## Qué aprendí

(Coste mensual de dev y prod según infracost, cuánto tarda crear un entorno desde cero, qué
deriva detectaste, qué te costó más de importar.)
