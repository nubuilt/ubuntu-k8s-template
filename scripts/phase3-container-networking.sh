#!/usr/bin/env bash
#===============================================================================
# Phase 3: Container Engine & Networking
# Part of: Ubuntu 24.04 LTS — Kubernetes Node Template
#
# Description:
#   Loads required kernel modules, configures network routing for pod
#   communication, fixes CoreDNS loop issue on Ubuntu 24.04, installs and
#   configures containerd with SystemdCgroup, and sets up crictl.
#
# Usage:
#   chmod +x phase3-container-networking.sh
#   sudo ./phase3-container-networking.sh
#===============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_step() { echo -e "${GREEN}[PHASE 3]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

#---------------------------------------
# 3.1 Kernel Modules & Network Routing
#---------------------------------------
log_step "Loading required kernel modules (overlay, br_netfilter)..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf > /dev/null
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

log_step "Configuring sysctl for IPv4 forwarding and iptables bridging..."
cat <<EOF | tee /etc/sysctl.d/k8s-net.conf > /dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system > /dev/null 2>&1

# Verify
if [[ $(cat /proc/sys/net/ipv4/ip_forward) == "1" ]]; then
    log_step "✅ IP forwarding is enabled"
else
    log_warn "IP forwarding may not be active"
fi

#---------------------------------------
# 3.2 Fix CoreDNS Loop & Add Fallback DNS
#---------------------------------------
log_step "Fixing systemd-resolved stub listener (CoreDNS loop prevention)..."
# Use regex to match whether it's commented or not, and replace the whole line
sed -i 's/^#*DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
sed -i 's/^#*FallbackDNS=.*/FallbackDNS=8.8.8.8 1.1.1.1/' /etc/systemd/resolved.conf
systemctl restart systemd-resolved

log_step "Reconfiguring /etc/resolv.conf symlink..."
rm -f /etc/resolv.conf
ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

# Verify
NAMESERVER=$(grep "nameserver" /etc/resolv.conf | head -1 | awk '{print $2}')
if [[ "$NAMESERVER" != "127.0.0.53" ]]; then
    log_step "✅ DNS is NOT pointing to stub resolver (currently: $NAMESERVER)"
else
    log_warn "DNS still points to 127.0.0.53 — CoreDNS loop risk!"
fi

#---------------------------------------
# 3.3 Containerd & crictl Configuration
#---------------------------------------
log_step "Installing containerd (Non-interactive)..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -yq containerd

log_step "Generating default containerd configuration..."
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null

log_step "Enabling SystemdCgroup in containerd config..."
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

log_step "Updating sandbox image to match kubeadm v1.32 (pause:3.10)..."
sed -i 's|sandbox_image = "registry.k8s.io/pause:.*"|sandbox_image = "registry.k8s.io/pause:3.10"|' /etc/containerd/config.toml

log_step "Restarting and enabling containerd..."
systemctl restart containerd
systemctl enable containerd

log_step "Configuring crictl to use containerd endpoint..."
cat <<EOF | tee /etc/crictl.yaml > /dev/null
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
EOF

# Verify
if systemctl is-active --quiet containerd; then
    log_step "✅ Containerd is running"
else
    log_warn "Containerd is not running — check 'systemctl status containerd'"
fi

#---------------------------------------
# Summary
#---------------------------------------
echo ""
log_step "============================================"
log_step "  Phase 3 Complete! ✅"
log_step "  - Kernel modules loaded"
log_step "  - Network routing configured"
log_step "  - CoreDNS loop fixed"
log_step "  - Containerd installed & configured"
log_step "  - crictl configured"
log_step "============================================"
echo ""
log_step "Next: Run phase4-k8s-tools.sh"