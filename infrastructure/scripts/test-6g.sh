#!/usr/bin/env bash
# ==============================================================================
# SP-Labs — 6G Lab Environment Validation
# Validates: container health → Sionna → ns-3 → O-RAN RIC
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
PASS=0; FAIL=0

check() {
  local desc="$1"; shift
  if eval "$@" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} ${desc}"
    ((PASS++))
  else
    echo -e "  ${RED}✗${NC} ${desc}"
    ((FAIL++))
  fi
}

echo ""
echo "==========================================="
echo "  SP-Labs — 6G Lab Validation"
echo "==========================================="

# --- 1. Container health ---
echo -e "\n${YELLOW}[1/3] Container Health${NC}"

# Sionna (check both GPU and CPU variants)
SIONNA_RUNNING=false
if docker inspect -f '{{.State.Running}}' sionna 2>/dev/null | grep -q true; then
  check "Container 'sionna' (GPU) is running" "true"
  SIONNA_RUNNING=true
elif docker inspect -f '{{.State.Running}}' sionna-cpu 2>/dev/null | grep -q true; then
  check "Container 'sionna-cpu' (CPU) is running" "true"
  SIONNA_RUNNING=true
else
  check "Container 'sionna' or 'sionna-cpu' is running" "false"
fi

check "Container 'ns3' exists" \
  "docker ps -a --format '{{.Names}}' | grep -q '^ns3$'"

for svc in oran-ric-db oran-ric-e2term oran-ric-e2mgr; do
  check "Container '${svc}' is running" \
    "docker inspect -f '{{.State.Running}}' ${svc} 2>/dev/null | grep -q true"
done

# --- 2. Sionna validation ---
echo -e "\n${YELLOW}[2/3] Sionna Environment${NC}"

if $SIONNA_RUNNING; then
  SIONNA_CTR=$(docker ps --filter "name=sionna" --format '{{.Names}}' | head -1)

  check "Jupyter is accessible on port 8888" \
    "curl -sf http://localhost:8888 >/dev/null"
  check "TensorFlow is importable" \
    "docker exec ${SIONNA_CTR} python3 -c 'import tensorflow as tf; print(tf.__version__)'"
  check "Sionna is importable" \
    "docker exec ${SIONNA_CTR} python3 -c 'import sionna; print(sionna.__version__)'"

  # GPU check (non-critical)
  if docker exec ${SIONNA_CTR} python3 -c "import tensorflow as tf; assert len(tf.config.list_physical_devices('GPU')) > 0" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} GPU acceleration available"
    ((PASS++))
  else
    echo -e "  ${YELLOW}⚠${NC} No GPU detected — running in CPU-only mode"
  fi
else
  echo -e "  ${YELLOW}⚠${NC} Sionna not running — skipping validation"
fi

# --- 3. ns-3 validation ---
echo -e "\n${YELLOW}[3/3] ns-3 Environment${NC}"

if docker ps -a --format '{{.Names}}' | grep -q '^ns3$'; then
  check "ns-3 build exists in container" \
    "docker exec ns3 test -f ./ns3 2>/dev/null || docker run --rm sp-labs/ns3:latest test -f ./ns3"
else
  echo -e "  ${YELLOW}⚠${NC} ns-3 container not found — build with 'make deploy-6g'"
fi

# --- Results ---
TOTAL=$((PASS + FAIL))
echo ""
echo "==========================================="
if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}ALL ${TOTAL} TESTS PASSED${NC}"
else
  echo -e "  ${GREEN}${PASS} passed${NC} / ${RED}${FAIL} failed${NC} (${TOTAL} total)"
fi
echo "==========================================="
echo ""

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
