#!/usr/bin/env bash
# ==============================================================================
# SP-Labs Bootstrap Script
# Prepares an Ubuntu 22.04+ host for the full 5G / 6G lab environment
#
# Usage:
#   sudo ./bootstrap.sh --full       # Install everything
#   sudo ./bootstrap.sh --5g         # 5G lab prerequisites only
#   sudo ./bootstrap.sh --6g         # 6G lab prerequisites only
#   sudo ./bootstrap.sh --monitor    # Monitoring prerequisites only
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[SP-Labs]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && err "This script must be run as root (use sudo)"

INSTALL_5G=false; INSTALL_6G=false; INSTALL_MONITOR=false
case "${1:-}" in
  --full)    INSTALL_5G=true; INSTALL_6G=true; INSTALL_MONITOR=true ;;
  --5g)      INSTALL_5G=true ;;
  --6g)      INSTALL_6G=true ;;
  --monitor) INSTALL_MONITOR=true ;;
  *)         echo "Usage: $0 {--full|--5g|--6g|--monitor}"; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# --- System packages ---
log "Updating system and installing base packages..."
apt-get update -qq && apt-get upgrade -y -qq
apt-get install -y -qq \
  apt-transport-https ca-certificates curl gnupg lsb-release \
  software-properties-common git make jq net-tools \
  iputils-ping iproute2 tcpdump wget unzip

# --- Docker Engine ---
if ! command -v docker &>/dev/null; then
  log "Installing Docker Engine..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
  [[ -n "${SUDO_USER:-}" ]] && usermod -aG docker "$SUDO_USER"
else
  log "Docker already installed: $(docker --version)"
fi
docker compose version &>/dev/null || apt-get install -y -qq docker-compose-plugin
log "Docker Compose: $(docker compose version)"

# --- Kernel config ---
log "Configuring kernel (ip_forward, TUN, SCTP)..."
sysctl -w net.ipv4.ip_forward=1
grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || \
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
modprobe tun
echo "tun" > /etc/modules-load.d/tun.conf
modprobe sctp 2>/dev/null || true
sysctl -p

# --- NAT for UE traffic ---
log "Configuring NAT for UE pool 10.45.0.0/16..."
iptables -t nat -C POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
iptables -C FORWARD -i ogstun -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i ogstun -j ACCEPT
iptables -C FORWARD -o ogstun -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -o ogstun -m state --state RELATED,ESTABLISHED -j ACCEPT
apt-get install -y -qq iptables-persistent && netfilter-persistent save || true

# --- .env ---
[[ ! -f "${REPO_ROOT}/.env" ]] && cp "${REPO_ROOT}/.env.example" "${REPO_ROOT}/.env"

# --- Call component-specific setup ---
source "${SCRIPT_DIR}/bootstrap-components.sh"

log "============================================"
log "  SP-Labs Bootstrap Complete!"
log "============================================"
log "Next: make deploy-5g | make deploy-6g | make deploy-monitoring"
