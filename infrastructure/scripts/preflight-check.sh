#!/usr/bin/env bash
# ==============================================================================
# SP-Labs — Pre-Flight Check
#
# Validates that the jump host and target VMs are ready for deployment.
# Run this BEFORE ansible-playbook or make deploy-*.
#
# Usage:
#   ./preflight-check.sh              # Full check
#   ./preflight-check.sh --local      # Jump host only
#   ./preflight-check.sh --remote     # Remote VMs only
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0; WARN=0

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

[[ -f "${REPO_ROOT}/.env" ]] && { set -a; source "${REPO_ROOT}/.env"; set +a; }

SSH_KEY="${ANSIBLE_SSH_KEY:-$HOME/.ssh/sp-labs-key}"
SSH_USER="${ANSIBLE_USER:-ubuntu}"
SSH_PORT="${ANSIBLE_SSH_PORT:-22}"
INVENTORY="${REPO_ROOT}/infrastructure/ansible/inventory.ini"
MODE="${1:-all}"

echo ""
echo "==========================================="
echo "  SP-Labs — Pre-Flight Check"
echo "==========================================="

# --- Source the remote checks helper ---
source "${SCRIPT_DIR}/preflight-remote.sh"

# =====================================================================
# SECTION 1: Jump Host Tools
# =====================================================================
if [[ "$MODE" != "--remote" ]]; then

echo -e "\n${YELLOW}[1/5] Jump Host Tools${NC}"
check "git is installed" "command -v git"
check "make is installed" "command -v make"
check "jq is installed" "command -v jq"
check "curl is installed" "command -v curl"

if command -v docker &>/dev/null; then
  check "Docker is installed" "true"
  check "Docker daemon is running" "docker info"
  check "Docker Compose v2 available" "docker compose version"
else
  echo -e "  ${YELLOW}⚠${NC} Docker not on jump host (OK for multi-VM)"
  ((WARN++))
fi

if command -v ansible &>/dev/null; then
  check "Ansible is installed" "true"
else
  echo -e "  ${YELLOW}⚠${NC} Ansible not installed (needed for multi-VM)"
  ((WARN++))
fi

check "SSH client is installed" "command -v ssh"

# =====================================================================
# SECTION 2: Repository & Configuration
# =====================================================================
echo -e "\n${YELLOW}[2/5] Repository & Configuration${NC}"
check ".env file exists" "test -f ${REPO_ROOT}/.env"
check "Makefile exists" "test -f ${REPO_ROOT}/Makefile"
check "5g-lab/docker-compose.yml exists" \
  "test -f ${REPO_ROOT}/5g-lab/docker-compose.yml"
check "Ansible inventory exists" "test -f ${INVENTORY}"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  check ".env has MCC defined" "grep -q '^MCC=' ${REPO_ROOT}/.env"
  check ".env has MNC defined" "grep -q '^MNC=' ${REPO_ROOT}/.env"
fi

# =====================================================================
# SECTION 3: SSH Key
# =====================================================================
echo -e "\n${YELLOW}[3/5] SSH Key${NC}"
if [[ -f "${SSH_KEY}" ]]; then
  check "SSH private key exists (${SSH_KEY})" "true"
  check "SSH public key exists" "test -f ${SSH_KEY}.pub"
else
  echo -e "  ${YELLOW}⚠${NC} SSH key not found at ${SSH_KEY}"
  echo "       Run: ./infrastructure/scripts/setup-ssh-keys.sh"
  ((WARN++))
fi

fi  # end --local / --all

# =====================================================================
# SECTION 4: Remote VMs (multi-VM only)
# =====================================================================
if [[ "$MODE" != "--local" ]]; then
  run_remote_checks
fi

# =====================================================================
# SECTION 5: Local Network & Ports
# =====================================================================
if [[ "$MODE" != "--remote" ]]; then

echo -e "\n${YELLOW}[5/5] Local Network & Ports${NC}"
check_warn "Internet: can reach Docker Hub" \
  "curl -sf --connect-timeout 5 https://hub.docker.com"
check_warn "Internet: can reach GitHub" \
  "curl -sf --connect-timeout 5 https://github.com"

if command -v docker &>/dev/null; then
  for pd in "9999:WebUI" "3000:Grafana" "9090:Prometheus"; do
    p="${pd%%:*}"; d="${pd##*:}"
    check_warn "Port ${p} (${d}) is available" \
      "! ss -tlnp 2>/dev/null | grep -q ':${p} '"
  done
fi

check_warn "Kernel: tun loaded" \
  "lsmod | grep -q '^tun ' || test -c /dev/net/tun"
check_warn "IP forwarding enabled" \
  "sysctl -n net.ipv4.ip_forward 2>/dev/null | grep -q 1"

fi

# =====================================================================
# RESULTS
# =====================================================================
TOTAL=$((PASS + FAIL))
echo ""
echo "==========================================="
if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}ALL ${TOTAL} CHECKS PASSED${NC}"
  [[ $WARN -gt 0 ]] && echo -e "  (${WARN} non-critical warnings)"
  echo "  You are ready to deploy!"
else
  echo -e "  ${GREEN}${PASS} passed${NC} / ${RED}${FAIL} failed${NC} / ${YELLOW}${WARN} warnings${NC}"
  echo "  Fix failures above, then re-run."
fi
echo "==========================================="
echo ""

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
