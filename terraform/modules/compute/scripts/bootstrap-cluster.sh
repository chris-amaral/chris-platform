#!/bin/bash
###############################################################################
# bootstrap-cluster.sh
# Description: Provisioning script for EC2 user-data.
#              Installs Docker, Kind, kubectl and Helm.
#              Creates a single-node Kind cluster ready for deployments.
# Author: Christopher Amaral
# Tested on: Ubuntu 22.04 LTS (amd64)
###############################################################################
set -euxo pipefail

LOG_FILE="/var/log/bootstrap-cluster.log"
STATUS_FILE="/var/log/bootstrap-status"

exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "=== Bootstrap started ==="
echo "RUNNING" > "$STATUS_FILE"

# --- System update ----------------------------------------------------------
log "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  software-properties-common \
  unzip \
  jq \
  git

# --- Docker -----------------------------------------------------------------
log "Installing Docker CE..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
usermod -aG docker ubuntu

# --- kubectl ----------------------------------------------------------------
log "Installing kubectl..."
KUBECTL_VERSION=$(curl -Ls https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl kubectl.sha256

# --- Helm -------------------------------------------------------------------
log "Installing Helm 3..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# --- Kind -------------------------------------------------------------------
log "Installing Kind..."
KIND_VERSION=$(curl -s https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | jq -r '.tag_name')
curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
install -o root -g root -m 0755 kind /usr/local/bin/kind
rm -f kind

# --- Create Kind Cluster ----------------------------------------------------
log "Creating Kind cluster..."
cat <<'KINDCFG' > /tmp/kind-cluster.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "0.0.0.0"
  apiServerPort: 6443
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30080
        hostPort: 30080
        protocol: TCP
KINDCFG

# Kind must run as ubuntu (docker group member)
su - ubuntu -c "kind create cluster --name dev-cluster --config /tmp/kind-cluster.yaml --wait 5m"
su - ubuntu -c "mkdir -p ~/.kube && kind get kubeconfig --name dev-cluster > ~/.kube/config"

# --- Validation -------------------------------------------------------------
log "Validating installations..."
docker --version
kubectl version --client --output=yaml
helm version --short
kind version

# Wait until all nodes are Ready
su - ubuntu -c "kubectl wait --for=condition=Ready nodes --all --timeout=300s"

log "Cluster status:"
su - ubuntu -c "kubectl get nodes -o wide"
su - ubuntu -c "kubectl get pods -A"

# --- Done -------------------------------------------------------------------
echo "SUCCESS" > "$STATUS_FILE"
log "=== Bootstrap completed successfully ==="
