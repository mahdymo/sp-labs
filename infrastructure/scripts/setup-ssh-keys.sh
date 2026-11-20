#!/usr/bin/env bash
# ==============================================================================
# SP-Labs — SSH Key Setup for Multi-VM Deployment
#
# Generates an Ed25519 SSH key pair and distributes the public key to all
# target VMs listed in the Ansible inventory.
#
# Usage:
#   ./setup-ssh-keys.sh                     # Use defaults
#   ./setup-ssh-keys.sh --key ~/.ssh/mykey  # Custom key path
#   ./setup-ssh-keys.sh --user admin        # Custom SSH user
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[SP-Labs]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# --- Defaults ---
SSH_KEY="${ANSIBLE_SSH_KEY:-$HOME/.ssh/sp-labs-key}"
SSH_USER="${ANSIBLE_USER:-ubuntu}"
SSH_PORT="${ANSIBLE_SSH_PORT:-22}"
INVENTORY="${REPO_ROOT}/infrastructure/ansible/inventory.ini"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --key)  SSH_KEY="$2"; shift 2 ;;
    --user) SSH_USER="$2"; shift 2 ;;
    --port) SSH_PORT="$2"; shift 2 ;;
    *) echo "Usage: $0 [--key path] [--user name] [--port num]"; exit 1 ;;
  esac
done

# --- Source .env if present ---
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a; source "${REPO_ROOT}/.env"; set +a
  SSH_KEY="${ANSIBLE_SSH_KEY:-$SSH_KEY}"
  SSH_USER="${ANSIBLE_USER:-$SSH_USER}"
  SSH_PORT="${ANSIBLE_SSH_PORT:-$SSH_PORT}"
fi

echo ""
echo "==========================================="
echo "  SP-Labs — SSH Key Setup"
echo "==========================================="
echo ""
log "Key path: ${SSH_KEY}"
log "SSH user: ${SSH_USER}"
log "SSH port: ${SSH_PORT}"
echo ""

# --- Step 1: Generate key pair ---
if [[ -f "${SSH_KEY}" ]]; then
  log "SSH key already exists at ${SSH_KEY} — reusing it"
else
  log "Generating Ed25519 SSH key pair..."
  mkdir -p "$(dirname "${SSH_KEY}")"
  ssh-keygen -t ed25519 -f "${SSH_KEY}" -C "sp-labs-ansible" -N ""
  log "Key pair created: ${SSH_KEY} / ${SSH_KEY}.pub"
fi

# --- Step 2: Extract VM IPs from inventory ---
log "Reading VM IPs from inventory..."
VM_IPS=()

if [[ -f "${INVENTORY}" ]]; then
  # Parse ansible_host= values from inventory
  while IFS= read -r line; do
    # Match lines with ansible_host=IP (skip comments, localhost)
    if [[ "$line" =~ ansible_host=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
      ip="${BASH_REMATCH[1]}"
      # Extract hostname (first token on the line)
      host=$(echo "$line" | awk '{print $1}')
      if [[ "$host" != "#"* ]]; then
        VM_IPS+=("${host}:${ip}")
      fi
    fi
  done < "${INVENTORY}"
fi

# Also check .env for VM_*_IP variables
for var in VM_5G_CORE_IP VM_RAN_SIM_IP VM_SIONNA_IP VM_NS3_IP VM_ORAN_IP VM_MONITOR_IP; do
  if [[ -n "${!var:-}" ]]; then
    # Only add if not already found in inventory
    ip="${!var}"
    already=false
    for entry in "${VM_IPS[@]:-}"; do
      if [[ "$entry" == *":${ip}" ]]; then
        already=true; break
      fi
    done
    if ! $already; then
      VM_IPS+=("${var}:${ip}")
    fi
  fi
done

if [[ ${#VM_IPS[@]} -eq 0 ]]; then
  warn "No VM IPs found in inventory or .env"
  warn "Edit inventory.ini or set VM_*_IP variables in .env first"
  warn ""
  warn "Example .env entries:"
  warn "  VM_5G_CORE_IP=192.168.1.10"
  warn "  VM_RAN_SIM_IP=192.168.1.20"
  warn "  VM_MONITOR_IP=192.168.1.70"
  exit 1
fi

log "Found ${#VM_IPS[@]} target VM(s):"
for entry in "${VM_IPS[@]}"; do
  echo "  - ${entry}"
done
echo ""

# --- Step 3: Distribute public key ---
PASS=0; FAIL=0

for entry in "${VM_IPS[@]}"; do
  host="${entry%%:*}"
  ip="${entry##*:}"

  echo -n "  Copying key to ${host} (${ip})... "

  # Try ssh-copy-id (will prompt for password)
  if ssh-copy-id -i "${SSH_KEY}" -p "${SSH_PORT}" \
       -o StrictHostKeyChecking=no \
       -o ConnectTimeout=10 \
       "${SSH_USER}@${ip}" 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
    ((PASS++))
  else
    echo -e "${RED}FAILED${NC}"
    warn "  Could not copy key to ${ip}. Check:"
    warn "    - Is the VM reachable? (ping ${ip})"
    warn "    - Is SSH running on port ${SSH_PORT}?"
    warn "    - Is password auth enabled for initial setup?"
    ((FAIL++))
  fi
done

echo ""

# --- Step 4: Verify password-less SSH ---
log "Verifying password-less SSH connectivity..."
echo ""

VERIFY_PASS=0; VERIFY_FAIL=0

for entry in "${VM_IPS[@]}"; do
  host="${entry%%:*}"
  ip="${entry##*:}"

  echo -n "  Testing ${host} (${ip})... "

  if ssh -i "${SSH_KEY}" -p "${SSH_PORT}" \
       -o StrictHostKeyChecking=no \
       -o PasswordAuthentication=no \
       -o ConnectTimeout=10 \
       -o BatchMode=yes \
       "${SSH_USER}@${ip}" "hostname" 2>/dev/null; then
    echo -e " ${GREEN}✓ Connected${NC}"
    ((VERIFY_PASS++))
  else
    echo -e " ${RED}✗ Failed${NC}"
    ((VERIFY_FAIL++))
  fi
done

# --- Summary ---
echo ""
echo "==========================================="
if [[ $VERIFY_FAIL -eq 0 && $VERIFY_PASS -gt 0 ]]; then
  echo -e "  ${GREEN}All ${VERIFY_PASS} VMs reachable via SSH${NC}"
  echo ""
  echo "  Key:  ${SSH_KEY}"
  echo "  User: ${SSH_USER}"
  echo ""
  echo "  Next steps:"
  echo "    1. Run:  ./infrastructure/scripts/preflight-check.sh"
  echo "    2. Then: cd infrastructure/ansible"
  echo "            ansible-playbook -i inventory.ini site.yml"
else
  echo -e "  ${RED}${VERIFY_FAIL} VM(s) unreachable${NC}"
  echo "  Fix connectivity issues and re-run this script."
fi
echo "==========================================="
