# La tienda en AWS (Fase 3)

Archivos para los laboratorios y el proyecto de la Fase 3. Se añaden al repositorio de la Fase 2.

| Archivo | Para qué | Módulo |
|---------|----------|--------|
| `primer-dia.sh` | Presupuesto con avisos, cifrado EBS por defecto, bloqueo de acceso público de S3 e IMDSv2 por defecto | 1 |
| `costes-olvidados.sh` | Informe de solo lectura de lo que cobra por hora (NAT, ALB, EC2, RDS, IPs, EBS…) | 16 |
| `iam/politica-uploads.json` | Mínimo privilegio: leer y escribir solo en `uploads/` | 2 |
| `iam/confianza-ec2.json` | Política de confianza de un rol para EC2 | 2 |
| `iam/scp-regiones.json` | SCP: solo dos regiones, auditoría protegida | 3 |
| `iam/gha-oidc-confianza.json` | Confianza OIDC para GitHub Actions, limitada a un repo y un entorno | 18 |
| `iam/gha-deploy-politica.json` | Permisos mínimos del pipeline: ECR, ECS, PassRole, S3 y CloudFront | 18 |
| `ecs/task-definition.json` | API en Fargate ARM64, contraseña desde el secreto que gestiona RDS | 18 |
| `../.github/workflows/deploy-aws.yml` | Despliegue con OIDC: build arm64, ECS con espera de estabilidad, frontend | 18 |

Sustituye `123456789012`, los nombres de recursos, el ARN del secreto y `TU-USUARIO` por los tuyos.

## Primer día

```bash
aws configure sso                 # crea el perfil "lab" con Identity Center
aws sso login --profile lab
export AWS_PROFILE=lab
./aws/primer-dia.sh tu@correo.com 10
```

## Después de cada laboratorio

```bash
./aws/costes-olvidados.sh us-east-1
```

## Crear un rol a partir de estos archivos

```bash
aws iam create-role --role-name lab-uploads --assume-role-policy-document file://aws/iam/confianza-ec2.json
aws iam put-role-policy --role-name lab-uploads --policy-name uploads \
  --policy-document file://aws/iam/politica-uploads.json
aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY \
  --policy-document file://aws/iam/politica-uploads.json
```

En la Fase 4 crearás toda la infraestructura del proyecto con Terraform en lugar de con la consola.
