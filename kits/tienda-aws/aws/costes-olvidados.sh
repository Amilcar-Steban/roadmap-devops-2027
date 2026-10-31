#!/usr/bin/env bash
# Lista los recursos que cobran por hora aunque nadie los use. SOLO LECTURA: no borra nada.
# Uso:  ./aws/costes-olvidados.sh              (todas las regiones habilitadas)
#       ./aws/costes-olvidados.sh us-east-1    (solo las regiones indicadas)
# Sale con código 1 si encuentra algo: sirve para un aviso diario desde cron o un workflow.
# Compatible con el bash 3.2 de macOS.
set -Euo pipefail

if [[ $# -gt 0 ]]; then
  regiones=("$@")
else
  read -r -a regiones <<< "$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)"
fi

encontrados=0
mostrar() {
  local titulo="$1" datos="$2"
  [[ -z "$datos" || "$datos" == "None" ]] && return 0
  printf '  %s\n' "$titulo"
  printf '%s\n' "$datos" | sed 's/^/      /'
  encontrados=$((encontrados + $(printf '%s\n' "$datos" | grep -c .)))
}
consulta() { "$@" --output text 2>/dev/null || true; }

for r in "${regiones[@]}"; do
  echo "== $r"
  mostrar "Instancias EC2 en marcha" "$(consulta aws ec2 describe-instances --region "$r" \
    --filters Name=instance-state-name,Values=running \
    --query 'Reservations[].Instances[].[InstanceId,InstanceType,Placement.AvailabilityZone]')"
  mostrar "NAT Gateways (por hora y por GB)" "$(consulta aws ec2 describe-nat-gateways --region "$r" \
    --filter Name=state,Values=available --query 'NatGateways[].[NatGatewayId,SubnetId]')"
  mostrar "Balanceadores (ALB/NLB)" "$(consulta aws elbv2 describe-load-balancers --region "$r" \
    --query 'LoadBalancers[].[LoadBalancerName,Type]')"
  # shellcheck disable=SC2016  # las comillas invertidas son sintaxis de JMESPath, no de bash
  mostrar "IPs elásticas sin asociar" "$(consulta aws ec2 describe-addresses --region "$r" \
    --query 'Addresses[?AssociationId==`null`].[PublicIp,AllocationId]')"
  mostrar "Volúmenes EBS sueltos" "$(consulta aws ec2 describe-volumes --region "$r" \
    --filters Name=status,Values=available --query 'Volumes[].[VolumeId,Size,VolumeType]')"
  mostrar "Bases de datos RDS" "$(consulta aws rds describe-db-instances --region "$r" \
    --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus]')"
  mostrar "Clústeres de ElastiCache" "$(consulta aws elasticache describe-cache-clusters --region "$r" \
    --query 'CacheClusters[].[CacheClusterId,CacheNodeType,CacheClusterStatus]')"
done

echo
if (( encontrados > 0 )); then
  echo "$encontrados recursos que cobran por hora. Bórralos si ya no los usas."
  exit 1
fi
echo "Nada que cobre por hora. Buen trabajo."
