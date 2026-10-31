# Capa datos de prod: PostgreSQL y Valkey.
# Estado propio en s3://tienda-tfstate-123456789012/prod/datos.tfstate (créalo con bootstrap/).

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
    key          = "prod/datos.tfstate"
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
      entorno        = "prod"
      capa           = "datos"
      equipo         = "plataforma"
      gestionado_por = "terraform"
    }
  }
}

# Lo que crea la capa red se encuentra por etiquetas: no hace falta leer su estado
data "aws_vpc" "principal" {
  tags = { Name = "tienda-prod" }
}

data "aws_subnets" "datos" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.principal.id]
  }
  tags = { tipo = "datos" }
}

module "datos" {
  source = "../../../modules/datos"

  nombre             = "tienda-prod"
  vpc_id             = data.aws_vpc.principal.id
  subredes_datos     = data.aws_subnets.datos.ids
  prefijo_ssm        = "/tienda/prod/datos"
  multi_az           = true
  replicas_cache     = 1
  proteccion_borrado = true
}

output "endpoint_bd" {
  description = "Host de PostgreSQL."
  value       = module.datos.endpoint_bd
}
