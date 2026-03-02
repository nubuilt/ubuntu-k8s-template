#!/usr/bin/env bash
#===============================================================================
# Phase 4: Pre-baking K8s Tools
# Part of: Ubuntu 24.04 LTS — Kubernetes Node Template
#
# Description:
#   Adds the official Kubernetes apt repository, installs kubeadm, kubelet,
#   and kubectl at a specific version, then locks them with apt-mark hold
#   to prevent accidental upgrades.
#
# Usage:
#   chmod +x phase4-k8s-tools.sh
#   sudo ./phase4-k8s-tools.sh
#
# Configuration:
#   Change K8S_VERSION below to target a different Kubernetes release.
#===============================================================================

set -euo pipefail

# ── Configuration ──
K8S_VERSION="1.32"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_step() { echo -e "${GREEN}[PHASE 4]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

#---------------------------------------
# 4.1 Add Kubernetes Apt Repository
#---------------------------------------
log_step "Installing prerequisite packages..."
apt-get install -yq apt-transport-https ca-certificates curl gpg

log_step "Creating keyrings directory..."
mkdir -p /etc/apt/keyrings

log_step "Adding Kubernetes v${K8S_VERSION} apt repository..."
# Added --yes to prevent interactive prompts if the file already exists
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
    | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
    | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

#---------------------------------------
# 4.2 Install Kubernetes Components
#---------------------------------------
log_step "Updating package index..."
apt-get update -yq

log_step "Installing kubeadm, kubelet, and kubectl..."
# CKA Tip: To find exact versions available, use: apt-cache madison kubeadm
apt-get install -yq kubelet kubeadm kubectl

log_step "Enabling kubelet service..."
systemctl enable kubelet

#---------------------------------------
# 4.3 Lock Package Versions
#---------------------------------------
log_step "Locking package versions with apt-mark hold..."
apt-mark hold kubelet kubeadm kubectl

# Verify
KUBEADM_VER=$(kubeadm version -o short 2>/dev/null || echo "unknown")
KUBELET_VER=$(kubelet --version 2>/dev/null | awk '{print $2}' || echo "unknown")
KUBECTL_VER=$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | awk '{print $2}' || echo "unknown")

#---------------------------------------
# Summary
#---------------------------------------
echo ""
log_step "============================================"
log_step "  Phase 4 Complete! ✅"
log_step "  - kubeadm:  ${KUBEADM_VER}"
log_step "  - kubelet:  ${KUBELET_VER}"
log_step "  - kubectl:  ${KUBECTL_VER}"
log_step "  - All packages held (locked)"
log_step "============================================"
echo ""
log_step "Next: Run phase5-cleanup.sh (⚠️ VM will shutdown!)"