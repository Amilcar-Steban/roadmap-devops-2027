#!/usr/bin/env bash
# Protecciones del primer día en una cuenta de AWS de laboratorio. Idempotente: puedes repetirlo.
# Uso:  ./aws/primer-dia.sh tu@correo.com [limite_usd]
# Requiere AWS CLI v2 con sesión activa (aws sso login --profile lab && export AWS_PROFILE=lab) y jq.
set -Eeuo pipefail

correo="${1:?Uso: primer-dia.sh tu@correo.com [limite_usd]}"
limite="${2:-10}"
[[ "$correo" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || { echo "Correo no válido: $correo" >&2; exit 2; }
[[ "$limite" =~ ^[0-9]+$ ]] || { echo "El límite debe ser un número entero de USD" >&2; exit 2; }

cuenta="$(aws sts get-caller-identity --query Account --output text)"
region="$(aws configure get region || true)"
region="${AWS_REGION:-${region:-us-east-1}}"
echo "Cuenta $cuenta · región $region"

echo "1/4 Presupuesto mensual de $limite USD (aviso al 80 % del gasto real y al 100 % del previsto)"
if aws budgets describe-budget --account-id "$cuenta" --budget-name laboratorio >/dev/null 2>&1; then
  echo "    ya existía"
else
  presupuesto="$(jq -n --arg l "$limite" \
    '{BudgetName: "laboratorio", BudgetLimit: {Amount: $l, Unit: "USD"}, TimeUnit: "MONTHLY", BudgetType: "COST"}')"
  avisos="$(jq -n --arg c "$correo" '[
    {Notification: {NotificationType: "ACTUAL", ComparisonOperator: "GREATER_THAN", Threshold: 80, ThresholdType: "PERCENTAGE"},
     Subscribers: [{SubscriptionType: "EMAIL", Address: $c}]},
    {Notification: {NotificationType: "FORECASTED", ComparisonOperator: "GREATER_THAN", Threshold: 100, ThresholdType: "PERCENTAGE"},
     Subscribers: [{SubscriptionType: "EMAIL", Address: $c}]}]')"
  aws budgets create-budget --account-id "$cuenta" --budget "$presupuesto" --notifications-with-subscribers "$avisos"
  echo "    creado"
fi

echo "2/4 Cifrado de EBS por defecto en $region"
aws ec2 enable-ebs-encryption-by-default --region "$region" --query EbsEncryptionByDefault --output text

echo "3/4 Bloqueo de acceso público de S3 para toda la cuenta"
aws s3control put-public-access-block --account-id "$cuenta" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
echo "    activado"

echo "4/4 IMDSv2 obligatorio por defecto para instancias nuevas en $region"
aws ec2 modify-instance-metadata-defaults --region "$region" --http-tokens required --http-put-response-hop-limit 2 \
  --query Return --output text

cat <<FIN

Hecho. Comprueba a mano lo que la CLI no puede hacer por ti:
  - MFA en el usuario root (consola → Security credentials) y sin claves de acceso de root
  - El correo de confirmación del presupuesto en $correo
  - ./aws/costes-olvidados.sh al terminar cada sesión de laboratorio
FIN
