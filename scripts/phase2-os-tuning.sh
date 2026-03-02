#!/usr/bin/env bash
#===============================================================================
# Phase 2: OS Tuning & Hardening
# Part of: Ubuntu 24.04 LTS — Kubernetes Node Template
#
# Description:
#   Updates system packages, disables swap, configures time synchronization,
#   expands system limits, sets up log rotation, and disables unnecessary services.
#
# Usage:
#   chmod +x phase2-os-tuning.sh
#   sudo ./phase2-os-tuning.sh
#===============================================================================

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_step() { echo -e "${GREEN}[PHASE 2]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

#---------------------------------------
# 2.1 Update System & Disable Swap
#---------------------------------------
log_step "Updating system packages (Non-interactive)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -yq
apt-get upgrade -yq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

log_step "Disabling swap (defense-in-depth)..."
swapoff -a
# Use a more robust regex to comment out swap lines in fstab
sed -i '/\sswap\s/s/^/#/' /etc/fstab

# Verify using swapon (returns empty if no swap is active)
if [[ -z "$(swapon --show)" ]]; then
    log_step "✅ Swap is disabled"
else
    log_warn "Swap may still be active — check manually with 'free -h'"
fi

#---------------------------------------
# 2.2 Time Synchronization & System Limits
#---------------------------------------
log_step "Enabling NTP time synchronization..."
timedatectl set-ntp true

log_step "Expanding system limits (file-max, inotify)..."
cat <<EOF | tee /etc/sysctl.d/k8s-limits.conf > /dev/null
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192
EOF
sysctl --system > /dev/null 2>&1

#---------------------------------------
# 2.3 Journald Log Rotation & Disable Unused Services
#---------------------------------------
log_step "Configuring journald log rotation (1GB / 7 days)..."
mkdir -p /etc/systemd/journald.conf.d
cat <<EOF | tee /etc/systemd/journald.conf.d/size.conf > /dev/null
[Journal]
SystemMaxUse=1G
MaxRetentionSec=7day
EOF
systemctl restart systemd-journald

log_step "Disabling UFW, snapd, and multipathd..."
systemctl disable --now ufw 2>/dev/null || true
systemctl disable --now snapd snapd.socket 2>/dev/null || true
systemctl disable --now multipathd 2>/dev/null || true

#---------------------------------------
# Summary
#---------------------------------------
echo ""
log_step "============================================"
log_step "  Phase 2 Complete! ✅"
log_step "  - System updated"
log_step "  - Swap disabled"
log_step "  - NTP enabled"
log_step "  - System limits expanded"
log_step "  - Log rotation configured"
log_step "  - Unnecessary services disabled"
log_step "============================================"

# Check if reboot is required due to package updates
if [ -f /var/run/reboot-required ]; then
    echo ""
    log_warn "A system reboot is required due to package updates (e.g., Kernel)."
    log_warn "It is recommended to reboot before proceeding to Phase 3."
fi

echo ""
log_step "Next: Run phase3-container-networking.sh"