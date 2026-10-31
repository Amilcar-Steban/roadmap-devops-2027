# Capa "cluster" para el repositorio tienda-infra de la Fase 4: cópiala en entornos/dev/cluster/
# (y prod) y aplícala después de la capa red. Crea:
#   - EKS 1.37 con nodos Graviton gestionados en las subredes privadas
#   - complementos: VPC CNI (con NetworkPolicies), CoreDNS, kube-proxy, Pod Identity, EBS CSI
#   - Pod Identity para External Secrets (solo lectura del secreto de RDS)
#   - access entry para el rol de despliegue de GitHub Actions, limitado al namespace "tienda"
# Un clúster EKS cobra por hora (plano de control + nodos): destrúyelo al terminar el laboratorio.

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
    key          = "dev/cluster.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = { proyecto = "tienda", entorno = "dev", capa = "cluster", equipo = "plataforma", gestionado_por = "terraform" }
  }
}

variable "cidrs_api_publica" {
  description = "IPs que pueden llegar a la API de Kubernetes desde internet (la tuya: curl -s ifconfig.me)/32."
  type        = list(string)
  validation {
    condition     = length(var.cidrs_api_publica) > 0 && !contains(var.cidrs_api_publica, "0.0.0.0/0")
    error_message = "Indica tu IP (x.x.x.x/32): la API del clúster no debe estar abierta a todo internet."
  }
}

variable "rol_despliegue_arn" {
  description = "Rol IAM que asume GitHub Actions para desplegar (helm upgrade) en el namespace tienda."
  type        = string
}

locals {
  nombre = "tienda-dev"
}

# Lo que creó la capa red, por etiquetas (como hacen las demás capas)
data "aws_vpc" "principal" {
  tags = { Name = local.nombre }
}

data "aws_subnets" "privadas" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.principal.id]
  }
  tags = { tipo = "privada" }
}

# Publicado por la capa datos
data "aws_ssm_parameter" "secreto_bd_arn" {
  name = "/tienda/dev/datos/secreto_bd_arn"
}

# Excepciones justificadas para trivy:
#   AWS-0040: endpoint público, pero restringido a cidrs_api_publica (laboratorio sin VPN)
#   AWS-0104: los nodos necesitan salida (vía NAT) para descargar imágenes y hablar con AWS
#trivy:ignore:AWS-0040
#trivy:ignore:AWS-0104
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.nombre
  kubernetes_version = "1.37" # comprueba las versiones con soporte: aws eks describe-cluster-versions
  vpc_id             = data.aws_vpc.principal.id
  subnet_ids         = data.aws_subnets.privadas.ids

  endpoint_public_access                   = true # laboratorio; en producción, privado + VPN o bastión
  endpoint_public_access_cidrs             = var.cidrs_api_publica
  enable_cluster_creator_admin_permissions = true

  # Logs del plano de control en CloudWatch: quién hizo qué (audit) y por qué falló (api)
  enabled_log_types                      = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 14

  addons = {
    vpc-cni = {
      before_compute = true
      # Sin esto, las NetworkPolicies se aceptan pero NO se aplican
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    eks-pod-identity-agent = { before_compute = true }
    coredns                = {}
    kube-proxy             = {}
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = module.ebs_csi_pod_identity.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  eks_managed_node_groups = {
    general = {
      ami_type       = "AL2023_ARM_64_STANDARD"
      instance_types = ["m7g.large", "m8g.large"] # varios tipos: más capacidad disponible
      min_size       = 2
      max_size       = 4
      desired_size   = 2
    }
  }

  # El pipeline solo puede tocar el namespace tienda (nada del resto del clúster)
  access_entries = {
    despliegue = {
      principal_arn = var.rol_despliegue_arn
      policy_associations = {
        tienda = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
          access_scope = { type = "namespace", namespaces = ["tienda"] }
        }
      }
    }
  }
}

module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                      = "${local.nombre}-ebs-csi"
  attach_aws_ebs_csi_policy = true
}

# External Secrets lee SOLO el secreto de la base de datos
module "external_secrets_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                                  = "${local.nombre}-external-secrets"
  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = [nonsensitive(data.aws_ssm_parameter.secreto_bd_arn.value)]
  external_secrets_create_permission    = false

  associations = {
    eso = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }
}

output "configurar_kubectl" {
  description = "Comando para conectar kubectl con el clúster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region us-east-1"
}
