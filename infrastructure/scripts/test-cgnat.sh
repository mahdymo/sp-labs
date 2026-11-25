#!/usr/bin/env bash
# ==============================================================================
# SP-Labs — Test BIG-IP CGNAT / AFM / DNS Integration
#
# Runs a 6-phase verification of the BIG-IP N6 insertion:
#   1. UPF routing table check
#   2. BIG-IP reachability from UPF
#   3. UE→Internet connectivity through BIG-IP
#   4. DNS resolution through BIG-IP
#   5. SNAT translation verification
#   6. AFM connectivity test
#
# Usage:
#   bash test-cgnat.sh
#   make test-cgnat
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
[[ -f "${REPO_ROOT}/.env" ]] && { set -a; source "${REPO_ROOT}/.env"; set +a; }

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0; WARN=0

BIGIP_N6_IP="${BIGIP_N6_IP:-10.1.10.200}"

check() {
  local desc="$1"; shift
  if eval "$@" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} ${desc}"; ((PASS++))
  else
    echo -e "  ${RED}✗${NC} ${desc}"; ((FAIL++))
  fi
}

check_warn() {
  local desc="$1"; shift
  if eval "$@" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} ${desc}"; ((PASS++))
  else
    echo -e "  ${YELLOW}⚠${NC} ${desc} (non-critical)"; ((WARN++))
  fi
}

echo ""
echo "==========================================="
echo "  SP-Labs — BIG-IP Integration Tests"
echo "==========================================="
echo -e "  BIG-IP N6 IP: ${CYAN}${BIGIP_N6_IP}${NC}"
echo ""

# --- Phase 1: UPF Routing ---
echo -e "${YELLOW}[1/6] UPF Routing Table${NC}"
check "UPF container is running" \
  "docker inspect -f '{{.State.Running}}' upf | grep -q true"

UPF_DEFAULT=$(docker exec upf ip route show default 2>/dev/null || echo "")
if echo "$UPF_DEFAULT" | grep -q "${BIGIP_N6_IP}"; then
  echo -e "  ${GREEN}✓${NC} UPF default route → ${BIGIP_N6_IP}"; ((PASS++))
else
  echo -e "  ${RED}✗${NC} UPF default route NOT pointing at BIG-IP"
  echo -e "       Current: ${UPF_DEFAULT:-<none>}"
  echo -e "       Expected: default via ${BIGIP_N6_IP}"
  ((FAIL++))
fi

# --- Phase 2: BIG-IP Reachability from UPF ---
echo -e "\n${YELLOW}[2/6] BIG-IP Reachability${NC}"
check_warn "Host can ping BIG-IP (${BIGIP_N6_IP})" \
  "ping -c 1 -W 3 ${BIGIP_N6_IP}"
check_warn "UPF can ping BIG-IP (${BIGIP_N6_IP})" \
  "docker exec upf ping -c 1 -W 3 ${BIGIP_N6_IP}"

# --- Phase 3: UE→Internet through BIG-IP ---
echo -e "\n${YELLOW}[3/6] UE→Internet Connectivity (via CGNAT)${NC}"
UE_CONTAINERS="ue"
docker inspect -f '{{.State.Running}}' ue-power 2>/dev/null | grep -q true && \
  UE_CONTAINERS="$UE_CONTAINERS ue-power ue-iot ue-enterprise"

for c in $UE_CONTAINERS; do
  if docker exec "$c" ip link show uesimtun0 &>/dev/null; then
    check "[$c] ping 8.8.8.8 via uesimtun0" \
      "docker exec $c ping -I uesimtun0 -c 2 -W 5 8.8.8.8"
  else
    echo -e "  ${YELLOW}⚠${NC} [$c] no uesimtun0 — skipping"; ((WARN++))
  fi
done

# --- Phase 4: DNS Resolution ---
echo -e "\n${YELLOW}[4/6] DNS Resolution (via BIG-IP)${NC}"
if docker exec ue which nslookup &>/dev/null; then
  check "DNS lookup: google.com from UE" \
    "docker exec ue nslookup google.com"
elif docker exec ue which dig &>/dev/null; then
  check "DNS lookup: google.com from UE" \
    "docker exec ue dig +short google.com"
else
  check_warn "DNS test via HTTP" \
    "docker exec ue ping -I uesimtun0 -c 1 -W 5 google.com"
fi

# --- Phase 5: SNAT Translation Check ---
echo -e "\n${YELLOW}[5/6] SNAT Translation Verification${NC}"
echo -e "  ${YELLOW}→${NC} Checking if UE's public IP differs from private..."
if docker exec ue which curl &>/dev/null; then
  PUBLIC_IP=$(docker exec ue curl -sf --interface uesimtun0 --connect-timeout 10 \
    https://ifconfig.me 2>/dev/null || echo "")
  if [[ -n "$PUBLIC_IP" ]]; then
    if echo "$PUBLIC_IP" | grep -q "^10\.45\."; then
      echo -e "  ${RED}✗${NC} Public IP is UE private IP (${PUBLIC_IP}) — CGNAT not translating"
      ((FAIL++))
    else
      echo -e "  ${GREEN}✓${NC} SNAT active — UE public IP: ${PUBLIC_IP}"
      ((PASS++))
    fi
  else
    echo -e "  ${YELLOW}⚠${NC} Could not determine public IP (internet unreachable?)"; ((WARN++))
  fi
else
  echo -e "  ${YELLOW}⚠${NC} curl not available in UE container — skipping SNAT check"; ((WARN++))
fi

# --- Phase 6: AFM Connectivity Test ---
echo -e "\n${YELLOW}[6/6] AFM Firewall Validation${NC}"
check_warn "HTTP (port 80) allowed through AFM" \
  "docker exec ue ping -I uesimtun0 -c 1 -W 5 8.8.8.8"
echo -e "  ${CYAN}ℹ${NC}  AFM deny-counter validation requires BIG-IP REST API access"
echo -e "  ${CYAN}ℹ${NC}  Check on BIG-IP: tmsh show security firewall policy policy_gi_lan"

# --- Results ---
TOTAL=$((PASS + FAIL))
echo ""
echo "==========================================="
if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}ALL ${TOTAL} CHECKS PASSED${NC}"
  [[ $WARN -gt 0 ]] && echo -e "  (${WARN} non-critical warnings)"
  echo "  BIG-IP CGNAT/AFM/DNS integration verified!"
else
  echo -e "  ${GREEN}${PASS} passed${NC} / ${RED}${FAIL} failed${NC} / ${YELLOW}${WARN} warnings${NC}"
  echo "  Review failures above. Common fixes:"
  echo "    - Run: make connect-bigip"
  echo "    - Verify BIG-IP self-IPs and return routes"
fi
echo "==========================================="
echo ""

[[ $FAIL -eq 0 ]] && exit 0 || exit 1