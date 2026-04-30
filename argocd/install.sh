#!/bin/bash
###############################################################################
# install.sh — instalacao manual do ArgoCD no cluster Kind
#
# Use este script SOMENTE se o bootstrap automatico da EC2 (user-data) nao
# tiver instalado o ArgoCD com sucesso. O caminho normal e:
#   1. ./terraform/setup.sh dev          # provisiona EC2 + bootstrap
#   2. SSH na EC2 (~5-8 min depois)      # ArgoCD ja esta no ar
#
# Este script faz o que o user-data faz, com mais verbosidade e validacoes.
#
# Mantenedor: Christopher Amaral
###############################################################################
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v2.13.1}"
NAMESPACE="argocd"

echo "============================================================"
echo " Instalacao ArgoCD - chris-platform"
echo " Versao: ${ARGOCD_VERSION}"
echo "============================================================"

# 1. Cluster acessivel?
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERRO: kubectl nao consegue falar com o cluster."
  echo "Verifique se o Kind esta rodando: docker ps | grep kind"
  exit 1
fi

# 2. Namespace
echo "[1/5] Criando namespace ${NAMESPACE}..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# 3. ArgoCD core
echo "[2/5] Aplicando manifesto oficial do ArgoCD..."
kubectl apply -n "${NAMESPACE}" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

# 4. Esperar pods Ready (timeout generoso, primeira vez baixa imagens)
echo "[3/5] Aguardando pods do ArgoCD ficarem Ready (ate 5 minutos)..."
kubectl wait --for=condition=available deployment --all \
  -n "${NAMESPACE}" --timeout=5m

# 5. Patch do Service para NodePort 30080 + modo insecure (HTTP atras de Kind)
echo "[4/5] Configurando Service em NodePort 30080..."
kubectl patch svc argocd-server -n "${NAMESPACE}" -p '{
  "spec": {
    "type": "NodePort",
    "ports": [
      {"port": 80, "targetPort": 8080, "nodePort": 30080, "protocol": "TCP", "name": "http"}
    ]
  }
}'

kubectl -n "${NAMESPACE}" patch configmap argocd-cmd-params-cm \
  -p '{"data": {"server.insecure": "true"}}'

kubectl -n "${NAMESPACE}" rollout restart deployment argocd-server
kubectl -n "${NAMESPACE}" rollout status deployment argocd-server --timeout=2m

# 6. Aplicar bootstrap (App-of-Apps)
echo "[5/5] Aplicando AppProject + Applications (bootstrap)..."
kubectl apply -f "$(dirname "$0")/projects/chris-platform.yaml"
kubectl apply -f "$(dirname "$0")/applications/webapp.yaml"

# 7. Mostrar credenciais e endpoints
echo ""
echo "============================================================"
echo " ArgoCD instalado com sucesso"
echo "============================================================"
echo " UI:        http://<EC2_PUBLIC_IP>:30080"
echo " Usuario:   admin"
echo " Senha:     $(kubectl -n ${NAMESPACE} get secret argocd-initial-admin-secret \
                    -o jsonpath='{.data.password}' | base64 -d)"
echo ""
echo " Aplicacoes gerenciadas:"
kubectl -n "${NAMESPACE}" get applications.argoproj.io
echo "============================================================"
