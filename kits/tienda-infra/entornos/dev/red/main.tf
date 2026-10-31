# Capa red de dev: VPC, subredes en tres niveles y NAT.
# Estado propio en s3://tienda-tfstate-123456789012/dev/red.tfstate (créalo con bootstrap/).

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
    key          = "dev/red.tfstate"
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
      capa           = "red"
      equipo         = "plataforma"
      gestionado_por = "terraform"
    }
  }
}

data "aws_availability_zones" "disponibles" {
  state = "available"
}

module "red" {
  source = "../../../modules/red"

  nombre = "tienda-dev"
  cidr   = "10.10.0.0/16"
  azs    = slice(data.aws_availability_zones.disponibles.names, 0, 2)
  nat    = "uno"
}

output "vpc_id" {
  description = "ID de la VPC."
  value       = module.red.vpc_id
}

output "ips_nat" {
  description = "IPs públicas de salida."
  value       = module.red.ips_nat
}
