#!/bin/bash
###############################################################################
# teardown.sh - Destruir toda a infraestrutura
# Uso: ./teardown.sh [dev|homol|prod]
#
# Author: Christopher Amaral
###############################################################################
set -e

ENV=${1:-dev}
TFVARS="inventories/${ENV}/terraform.tfvars"

if [ ! -f "$TFVARS" ]; then
  echo "Erro: $TFVARS nao encontrado."
  exit 1
fi

echo "============================================"
echo " Terraform Teardown - Ambiente: ${ENV}"
echo "============================================"
echo ""
echo "ATENCAO: Isso vai destruir TODOS os recursos do ambiente ${ENV}."
echo ""
read -p "Tem certeza? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Cancelado."
  exit 0
fi

# Destruir tudo (S3 nao tem mais prevent_destroy)
terraform destroy \
  -var-file="$TFVARS" \
  -auto-approve

# Limpar arquivos locais
rm -f "ssh-key-${ENV}.pem"
rm -f terraform.tfstate terraform.tfstate.backup

echo ""
echo "============================================"
echo " Teardown finalizado. Recursos destruidos."
echo "============================================"
