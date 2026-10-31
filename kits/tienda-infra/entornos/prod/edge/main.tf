# Capa edge de prod: CloudFront y el bucket del frontend.
# Estado propio en s3://tienda-tfstate-123456789012/prod/edge.tfstate (créalo con bootstrap/).

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
    key          = "prod/edge.tfstate"
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
      capa           = "edge"
      equipo         = "plataforma"
      gestionado_por = "terraform"
    }
  }
}

data "aws_caller_identity" "actual" {}

data "aws_ssm_parameter" "alb_dns" {
  name = "/tienda/prod/app/alb_dns"
}

module "edge" {
  source = "../../../modules/edge"

  nombre         = "tienda-prod"
  bucket_web     = "tienda-prod-web-${data.aws_caller_identity.actual.account_id}"
  alb_dns        = nonsensitive(data.aws_ssm_parameter.alb_dns.value)
  forzar_borrado = false
}

output "url" {
  description = "URL pública de la tienda."
  value       = module.edge.url
}

output "bucket_web" {
  description = "Variable WEB_BUCKET del workflow Deploy AWS."
  value       = module.edge.bucket_web
}

output "distribucion_id" {
  description = "Variable CF_DISTRIBUTION del workflow Deploy AWS."
  value       = module.edge.distribucion_id
}
