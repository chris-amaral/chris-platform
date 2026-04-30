#!/bin/bash
###############################################################################
# setup.sh — bootstrap completo do projeto chris-platform.
#
# Uso: ./setup.sh [dev|homol|prod]
#
# O que esse script automatiza para nao quebrar a "primeira execucao":
#   1. Le o tfvars do ambiente e gera o backend.hcl com bucket unico (inclui
#      o AWS account ID, evitando colisao de nome global no S3)
#   2. Cria o S3 + DynamoDB com backend local (resolve o "ovo e galinha" do
#      remote state — voce precisa do bucket para guardar o state que cria
#      o bucket)
#   3. Migra o state para o S3
#   4. Provisiona toda a infraestrutura (VPC, EC2 com Kind + ArgoCD, IAM
#      com OIDC para GitHub, etc.)
#   5. Exporta a chave SSH gerada para um arquivo local 600 e mostra os
#      Secrets que voce precisa setar no GitHub para o pipeline rodar.
#
# Mantenedor: Christopher Amaral
###############################################################################
set -e

ENV=${1:-dev}
TFVARS="inventories/${ENV}/terraform.tfvars"

if [ ! -f "$TFVARS" ]; then
  echo "Erro: $TFVARS nao encontrado."
  echo "Uso: ./setup.sh [dev|homol|prod]"
  exit 1
fi

# Limpa cache anterior do Terraform para evitar conflito de provider/backend
rm -rf .terraform .terraform.lock.hcl 2>/dev/null || true

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

# Limpar state anterior para evitar conflito de backend
rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup 2>/dev/null

if [ -f backend.tf ]; then
  mv backend.tf backend.tf.bak
fi

terraform init -input=false

# Importar recursos existentes (caso ja existam de execucao anterior)
echo "Verificando recursos existentes..."
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "Bucket $BUCKET_NAME ja existe. Importando..."
  terraform import -var-file="$TFVARS" module.storage.aws_s3_bucket.tfstate "$BUCKET_NAME" 2>/dev/null || true
  terraform import -var-file="$TFVARS" module.storage.aws_s3_bucket_versioning.tfstate "$BUCKET_NAME" 2>/dev/null || true
  terraform import -var-file="$TFVARS" module.storage.aws_s3_bucket_server_side_encryption_configuration.tfstate "$BUCKET_NAME" 2>/dev/null || true
  terraform import -var-file="$TFVARS" module.storage.aws_s3_bucket_public_access_block.tfstate "$BUCKET_NAME" 2>/dev/null || true
fi

if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" 2>/dev/null >/dev/null; then
  echo "DynamoDB $TABLE_NAME ja existe. Importando..."
  terraform import -var-file="$TFVARS" module.storage.aws_dynamodb_table.tfstate_lock "$TABLE_NAME" 2>/dev/null || true
fi

terraform apply \
  -var-file="$TFVARS" \
  -target=module.storage \
  -auto-approve

# --- Migrar state para S3 --------------------------------------------------
echo "[3/5] Migrando state para S3..."
if [ -f backend.tf.bak ]; then
  mv backend.tf.bak backend.tf
fi

rm -rf .terraform 2>/dev/null
terraform init \
  -backend-config="inventories/${ENV}/backend.hcl" \
  -input=false

# --- Provisionamento completo ----------------------------------------------
echo "[4/5] Provisionando infraestrutura completa..."

# Importar OIDC provider se ja existir na conta
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" 2>/dev/null >/dev/null; then
  echo "OIDC Provider ja existe. Importando..."
  terraform import -var-file="$TFVARS" module.iam.aws_iam_openid_connect_provider.github_actions "$OIDC_ARN" 2>/dev/null || true
fi

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
echo "   EC2_SSH_HOST          = $EC2_IP"
echo "   EC2_SSH_PRIVATE_KEY   = (conteudo do arquivo $SSH_KEY_FILE)"
echo ""
echo " Aguarde ~5-8 minutos para o bootstrap da EC2 completar."
echo " Verifique com: ssh -i $SSH_KEY_FILE ubuntu@$EC2_IP 'cat /var/log/bootstrap-status'"
echo ""
echo " Apos o bootstrap, ArgoCD UI estara disponivel em:"
echo "   http://$EC2_IP:30080  (usuario admin)"
echo "   senha inicial: ssh ... 'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath={.data.password} | base64 -d'"
echo "============================================"
