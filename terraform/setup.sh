#!/bin/bash
###############################################################################
# setup.sh - Bootstrap completo do Terraform
# Uso: ./setup.sh [dev|homol|prod]
#
# Este script:
#   1. Gera o backend.hcl com nome do bucket unico (inclui AWS account ID)
#   2. Cria S3 + DynamoDB para state remoto
#   3. Migra o state para S3
#   4. Provisiona toda a infraestrutura
#   5. Exporta a chave SSH para arquivo
#
# Author: Christopher Amaral
###############################################################################
set -e

ENV=${1:-dev}
TFVARS="inventories/${ENV}/terraform.tfvars"

if [ ! -f "$TFVARS" ]; then
  echo "Erro: $TFVARS nao encontrado."
  echo "Uso: ./setup.sh [dev|homol|prod]"
  exit 1
fi

echo "============================================"
echo " Terraform Setup - Ambiente: ${ENV}"
echo "============================================"

# --- Extrair valores do tfvars ---------------------------------------------
PROJECT_NAME=$(grep 'project_name' "$TFVARS" | sed 's/.*= *"//' | sed 's/".*//')
REGION=$(grep 'aws_region' "$TFVARS" | sed 's/.*= *"//' | sed 's/".*//')
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

if [ -z "$ACCOUNT_ID" ]; then
  echo "Erro: AWS CLI nao configurado. Execute 'aws configure' primeiro."
  exit 1
fi

BUCKET_NAME="${PROJECT_NAME}-tfstate-${ACCOUNT_ID}"
TABLE_NAME="${PROJECT_NAME}-tfstate-lock"

echo ""
echo "Project:  $PROJECT_NAME"
echo "Region:   $REGION"
echo "Account:  $ACCOUNT_ID"
echo "Bucket:   $BUCKET_NAME"
echo "DynamoDB: $TABLE_NAME"
echo ""

# --- Gerar backend.hcl -----------------------------------------------------
cat > "inventories/${ENV}/backend.hcl" <<EOF
bucket         = "${BUCKET_NAME}"
key            = "${ENV}/terraform.tfstate"
region         = "${REGION}"
encrypt        = true
dynamodb_table = "${TABLE_NAME}"
EOF

echo "[1/5] backend.hcl gerado: inventories/${ENV}/backend.hcl"

# --- Bootstrap: S3 + DynamoDB com backend local ----------------------------
echo "[2/5] Criando S3 + DynamoDB (backend local)..."
if [ -f backend.tf ]; then
  mv backend.tf backend.tf.bak
fi

terraform init -input=false
terraform apply \
  -var-file="$TFVARS" \
  -target=module.storage \
  -auto-approve

# --- Migrar state para S3 --------------------------------------------------
echo "[3/5] Migrando state para S3..."
mv backend.tf.bak backend.tf
terraform init \
  -backend-config="inventories/${ENV}/backend.hcl" \
  -migrate-state \
  -force-copy

# --- Provisionamento completo ----------------------------------------------
echo "[4/5] Provisionando infraestrutura completa..."
terraform apply \
  -var-file="$TFVARS" \
  -auto-approve

# --- Exportar chave SSH ----------------------------------------------------
echo "[5/5] Exportando chave SSH..."
SSH_KEY_FILE="ssh-key-${ENV}.pem"
terraform output -raw ssh_private_key > "$SSH_KEY_FILE"
chmod 600 "$SSH_KEY_FILE"

EC2_IP=$(terraform output -raw ec2_public_ip)
INSTANCE_ID=$(terraform output -raw ec2_instance_id)
ROLE_ARN=$(terraform output -raw github_actions_role_arn)

echo ""
echo "============================================"
echo " Setup finalizado com sucesso!"
echo "============================================"
echo ""
echo " EC2 IP:        $EC2_IP"
echo " Instance ID:   $INSTANCE_ID"
echo " Role ARN:      $ROLE_ARN"
echo " SSH Key:       terraform/$SSH_KEY_FILE"
echo ""
echo " Conectar via SSH:"
echo "   ssh -i terraform/$SSH_KEY_FILE ubuntu@$EC2_IP"
echo ""
echo " GitHub Secrets necessarios:"
echo "   AWS_ROLE_ARN          = $ROLE_ARN"
echo "   EC2_INSTANCE_ID       = $INSTANCE_ID"
echo "   EC2_SSH_HOST           = $EC2_IP"
echo "   EC2_SSH_PRIVATE_KEY    = (conteudo do arquivo $SSH_KEY_FILE)"
echo ""
echo " Aguarde ~5-8 minutos para o bootstrap da EC2 completar."
echo " Verifique com: ssh -i terraform/$SSH_KEY_FILE ubuntu@$EC2_IP 'cat /var/log/bootstrap-status'"
echo "============================================"
