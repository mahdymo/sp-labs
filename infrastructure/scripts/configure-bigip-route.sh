#!/usr/bin/env bash
# ==============================================================================
# SP-Labs — Configure N6 Routing to External BIG-IP
#
# Redirects UPF's default route through BIG-IP for CGNAT/AFM/DNS processing.
# BIG-IP must be reachable on the 10.1.10.0/24 transit network.
#
# Usage:
#   bash configure-bigip-route.sh
#   BIGIP_N6_IP=10.1.10.200 bash configure-bigip-route.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
[[ -f "${REPO_ROOT}/.env" ]] && { set -a; source "${REPO_ROOT}/.env"; set +a; }

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; NC='\033[0m'

BIGIP_N6_IP="${BIGIP_N6_IP:-10.1.10.200}"
BIGIP_TRANSIT_NET="${BIGIP_TRANSIT_NET:-10.1.10.0/24}"
UE_POOL="${UE_POOL:-10.45.0.0/16}"
UPF_N6_IP="${UPF_N6_IP:-10.33.37.14}"
N6_SUBNET="${N6_SUBNET:-10.33.37.0/24}"
HOST_N6_GW="${HOST_N6_GW:-10.33.37.1}"

echo ""
echo "==========================================="
echo "  SP-Labs — BIG-IP N6 Route Configuration"
echo "==========================================="
echo -e "  BIG-IP N6 IP:     ${CYAN}${BIGIP_N6_IP}${NC}"
echo -e "  Transit network:  ${CYAN}${BIGIP_TRANSIT_NET}${NC}"
echo -e "  UPF N6 address:   ${CYAN}${UPF_N6_IP}${NC}"
echo -e "  UE pool:          ${CYAN}${UE_POOL}${NC}"
echo ""

# --- Step 1: Verify UPF ---
echo -e "${YELLOW}[1/6] Checking UPF container...${NC}"
if docker inspect -f '{{.State.Running}}' upf 2>/dev/null | grep -q true; then
  echo -e "  ${GREEN}✓${NC} UPF is running"
else
  echo -e "  ${RED}✗${NC} UPF not running — run: make deploy-5g"; exit 1
fi

# --- Step 2: Verify BIG-IP reachability ---
echo -e "\n${YELLOW}[2/6] Checking BIG-IP at ${BIGIP_N6_IP}...${NC}"
if ping -c 2 -W 3 "${BIGIP_N6_IP}" &>/dev/null; then
  echo -e "  ${GREEN}✓${NC} BIG-IP is reachable"
else
  echo -e "  ${YELLOW}⚠${NC} Cannot ping ${BIGIP_N6_IP} — continuing (may block ICMP)"
fi

# --- Step 3: Find N6 Docker bridge ---
echo -e "\n${YELLOW}[3/6] Identifying N6 Docker bridge...${NC}"
N6_BRIDGE_ID=$(docker network inspect sp-labs-n6 --format '{{.Id}}' 2>/dev/null | cut -c1-12)
[[ -z "$N6_BRIDGE_ID" ]] && { echo -e "  ${RED}✗${NC} sp-labs-n6 not found"; exit 1; }
N6_BRIDGE="br-${N6_BRIDGE_ID}"
echo -e "  ${GREEN}✓${NC} N6 bridge: ${N6_BRIDGE}"

# --- Step 4: Host gateway on N6 bridge ---
echo -e "\n${YELLOW}[4/6] Configuring host gateway on N6 bridge...${NC}"
if ip addr show dev "${N6_BRIDGE}" 2>/dev/null | grep -q "${HOST_N6_GW}"; then
  echo -e "  ${GREEN}✓${NC} ${HOST_N6_GW} already on ${N6_BRIDGE}"
else
  sudo ip addr add "${HOST_N6_GW}/24" dev "${N6_BRIDGE}" 2>/dev/null || true
  echo -e "  ${GREEN}✓${NC} Added ${HOST_N6_GW}/24 to ${N6_BRIDGE}"
fi
sudo sysctl -qw net.ipv4.ip_forward=1
sudo iptables -C FORWARD -i "${N6_BRIDGE}" -j ACCEPT 2>/dev/null || \
  sudo iptables -A FORWARD -i "${N6_BRIDGE}" -j ACCEPT
sudo iptables -C FORWARD -o "${N6_BRIDGE}" -j ACCEPT 2>/dev/null || \
  sudo iptables -A FORWARD -o "${N6_BRIDGE}" -j ACCEPT
echo -e "  ${GREEN}✓${NC} Forwarding rules set"

# --- Step 5: Remove old host MASQUERADE ---
echo -e "\n${YELLOW}[5/6] Removing host MASQUERADE (BIG-IP CGNAT replaces it)...${NC}"
if sudo iptables -t nat -C POSTROUTING -s "${UE_POOL}" ! -o ogstun -j MASQUERADE 2>/dev/null; then
  sudo iptables -t nat -D POSTROUTING -s "${UE_POOL}" ! -o ogstun -j MASQUERADE
  echo -e "  ${GREEN}✓${NC} Removed old MASQUERADE rule"
else
  echo -e "  ${GREEN}✓${NC} No existing MASQUERADE rule (clean)"
fi

# --- Step 6: Redirect UPF default route ---
echo -e "\n${YELLOW}[6/6] Setting UPF default route → BIG-IP (${BIGIP_N6_IP})...${NC}"
docker exec upf ip route replace "${BIGIP_TRANSIT_NET}" via "${HOST_N6_GW}" 2>/dev/null || true
docker exec upf ip route replace default via "${BIGIP_N6_IP}"
echo -e "  ${GREEN}✓${NC} UPF default route → ${BIGIP_N6_IP}"
echo -e "\n  UPF routing table:"
docker exec upf ip route | sed 's/^/    /'

echo ""
echo "==========================================="
echo -e "  ${GREEN}BIG-IP N6 route configuration complete!${NC}"
echo ""
echo "  Traffic flow:"
echo -e "    UE (10.45.0.x) → UPF → ${CYAN}BIG-IP${NC} → Internet"
echo ""
echo "  Configure on BIG-IP (tmsh):"
echo -e "    ${CYAN}create net route ue_pool network ${UE_POOL} gw ${HOST_N6_GW}${NC}"
echo -e "    ${CYAN}create net route lab_n6 network ${N6_SUBNET} gw ${HOST_N6_GW}${NC}"
echo ""
echo "  Verify: make test-cgnat"
echo "==========================================="
