# Capa app de dev: ECR, balanceador y servicio ECS Fargate.
# Estado propio en s3://tienda-tfstate-123456789012/dev/app.tfstate (créalo con bootstrap/).

terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    bucket       = "tienda-tfstate-123456789012"
    key          = "dev/app.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      proyecto       = "tienda"
      entorno        = "dev"
      capa           = "app"
      equipo         = "plataforma"
      gestionado_por = "terraform"
    }
  }
}

# Lo que crea la capa red se encuentra por etiquetas: no hace falta leer su estado
data "aws_vpc" "principal" {
  tags = { Name = "tienda-dev" }
}

data "aws_subnets" "publicas" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.principal.id]
  }
  tags = { tipo = "publica" }
}

data "aws_subnets" "privadas" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.principal.id]
  }
  tags = { tipo = "privada" }
}

# Publicado por la capa datos
data "aws_ssm_parameters_by_path" "datos" {
  path = "/tienda/dev/datos"
}

locals {
  datos = zipmap(
    [for n in data.aws_ssm_parameters_by_path.datos.names : basename(n)],
    nonsensitive(data.aws_ssm_parameters_by_path.datos.values),
  )
}

module "app" {
  source = "../../../modules/app"

  nombre                = "tienda-dev"
  vpc_id                = data.aws_vpc.principal.id
  subredes_publicas     = data.aws_subnets.publicas.ids
  subredes_privadas     = data.aws_subnets.privadas.ids
  security_groups_extra = [local.datos.sg_clientes_id]

  # Imagen de arranque: el workflow Deploy AWS de la Fase 3 publica después las versiones reales
  imagen     = "public.ecr.aws/docker/library/python:3.13-slim"
  cpu        = 256
  memoria    = 512
  tareas_min = 1
  tareas_max = 2

  variables_entorno = {
    DB_HOST   = local.datos.endpoint_bd
    DB_NAME   = local.datos.bd_nombre
    DB_USER   = local.datos.bd_usuario
    REDIS_URL = "rediss://${local.datos.endpoint_cache}:6379/0"
  }
  secretos     = { DB_PASSWORD = "${local.datos.secreto_bd_arn}:password::" }
  secretos_arn = [local.datos.secreto_bd_arn]

  proteccion_borrado = false
}

# Para la capa edge
resource "aws_ssm_parameter" "alb_dns" {
  name  = "/tienda/dev/app/alb_dns"
  type  = "String"
  value = module.app.alb_dns
}

output "ecr_url" {
  description = "Repositorio de imágenes."
  value       = module.app.ecr_url
}

output "cluster" {
  description = "Clúster ECS."
  value       = module.app.cluster
}

output "servicio" {
  description = "Servicio ECS."
  value       = module.app.servicio
}

output "rol_ejecucion_arn" {
  description = "executionRoleArn de la task definition."
  value       = module.app.rol_ejecucion_arn
}

output "rol_tarea_arn" {
  description = "taskRoleArn de la task definition."
  value       = module.app.rol_tarea_arn
}
