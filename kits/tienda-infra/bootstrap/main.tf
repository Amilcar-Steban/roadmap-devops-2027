# Se aplica una sola vez, a mano, con tu perfil de administrador (aws sso login --profile lab):
# crea el bucket de estados, el proveedor OIDC de GitHub y los dos roles del pipeline.
#
#   terraform init && terraform apply -var="repo=TU-USUARIO/tienda-infra"
#
# Su propio estado empieza en local. Cuando el bucket exista, descomenta el backend y ejecuta
# terraform init -migrate-state para guardarlo también en S3.

terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # backend "s3" {
  #   bucket       = "tienda-tfstate-123456789012"
  #   key          = "bootstrap.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = { proyecto = "tienda", capa = "bootstrap", equipo = "plataforma", gestionado_por = "terraform" }
  }
}

variable "repo" {
  description = "Repositorio de GitHub con la infraestructura, en formato usuario/nombre."
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.repo))
    error_message = "repo debe tener el formato usuario/nombre."
  }
}

data "aws_caller_identity" "actual" {}

locals {
  cuenta        = data.aws_caller_identity.actual.account_id
  bucket_estado = "tienda-tfstate-${local.cuenta}"
}

# --- Bucket de estados: privado, cifrado, con versiones (para recuperar un estado roto)

module "estado" {
  source = "../modules/bucket-seguro"

  nombre                  = local.bucket_estado
  versionado              = true
  dias_versiones_antiguas = 90
}

# --- GitHub como proveedor de identidad (OIDC): el pipeline no guarda claves de AWS

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# Plan: lo usan los pull requests, la rama main y la detección de deriva. Solo lectura,
# más lo justo en el bucket de estados para el archivo de bloqueo.
resource "aws_iam_role" "plan" {
  name = "gha-terraform-plan"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.repo}:pull_request",
            "repo:${var.repo}:ref:refs/heads/main",
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "plan_lectura" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_estado" {
  name = "estado-terraform"
  role = aws_iam_role.plan.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LeerEstados"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetObject"]
        Resource = [module.estado.arn, "${module.estado.arn}/*"]
      },
      {
        Sid      = "Bloqueo"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${module.estado.arn}/*.tflock"
      },
    ]
  })
}

# Apply: solo desde los entornos de GitHub (desarrollo sin aprobación, produccion con ella).
# AdministratorAccess es lo habitual para un rol de Terraform que crea IAM; acótalo con un
# permissions boundary o con SCP cuando tu organización crezca (Fase 3, módulos 2 y 3).
resource "aws_iam_role" "apply" {
  name = "gha-terraform-apply"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.repo}:environment:desarrollo",
            "repo:${var.repo}:environment:produccion",
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "apply_admin" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "bucket_estado" {
  description = "Bucket de estados: sustituye tienda-tfstate-123456789012 en entornos/*/*/main.tf."
  value       = module.estado.nombre
}

output "rol_plan_arn" {
  description = "Variable AWS_PLAN_ROLE_ARN del repositorio."
  value       = aws_iam_role.plan.arn
}

output "rol_apply_arn" {
  description = "Variable AWS_APPLY_ROLE_ARN de los entornos desarrollo y produccion."
  value       = aws_iam_role.apply.arn
}
