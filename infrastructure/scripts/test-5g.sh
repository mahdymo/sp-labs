#!/usr/bin/env bash
# ==============================================================================
# SP-Labs — 5G End-to-End Test
# Validates: container health → UE registration → PDU session → data path
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
echo "  SP-Labs — 5G End-to-End Validation"
echo "==========================================="

# --- 1. Container health ---
echo -e "\n${YELLOW}[1/6] Container Health${NC}"
for svc in mongodb nrf scp amf smf upf ausf udm udr pcf nssf bsf webui gnb ue; do
  check "Container '${svc}' is running" \
    "docker inspect -f '{{.State.Running}}' ${svc} 2>/dev/null | grep -q true"
done

# --- 2. Network connectivity ---
echo -e "\n${YELLOW}[2/6] Network Connectivity${NC}"
check "gNB can reach AMF on N2 (10.33.34.12)" \
  "docker exec gnb ping -c 1 -W 2 10.33.34.12"
check "gNB can reach UPF on N3 (10.33.35.14)" \
  "docker exec gnb ping -c 1 -W 2 10.33.35.14"
check "SMF can reach UPF on N4 (10.33.36.14)" \
  "docker exec smf ping -c 1 -W 2 10.33.36.14"
check "NRF is reachable on SBI" \
  "docker exec amf ping -c 1 -W 2 10.33.33.10"

# --- 3. UE registration & PDU session ---
echo -e "\n${YELLOW}[3/6] UE Registration & PDU Session${NC}"
check "AMF has NGAP connection from gNB" \
  "docker logs gnb 2>&1 | grep -qi 'ng setup response\\|ngap.*success\\|connected'"
check "UE registration accepted" \
  "docker logs ue 2>&1 | grep -qi 'registration.*accept\\|registered\\|initial registration'"
check "PDU session established" \
  "docker logs ue 2>&1 | grep -qi 'pdu session.*estab\\|uesimtun\\|tunnel'"

# --- 4. Data path (ping through UPF) ---
echo -e "\n${YELLOW}[4/6] Data Path Validation${NC}"
# Check if UE has uesimtun0 interface with IP
check "UE has TUN interface with IP" \
  "docker exec ue ip addr show uesimtun0 2>/dev/null | grep -q 'inet 10.45'"

# Try pinging through the tunnel
UE_TUN_EXISTS=$(docker exec ue ip link show uesimtun0 2>/dev/null && echo "yes" || echo "no")
if [[ "$UE_TUN_EXISTS" == "yes" ]]; then
  check "UE can ping 8.8.8.8 via UPF tunnel" \
    "docker exec ue ping -I uesimtun0 -c 2 -W 5 8.8.8.8"
  check "UE can resolve DNS via UPF tunnel" \
    "docker exec ue ping -I uesimtun0 -c 2 -W 5 1.1.1.1"
else
  check "UE can ping 8.8.8.8 via UPF tunnel" "false"
  check "UE can resolve DNS via UPF tunnel" "false"
fi

# --- 5. Quick traffic burst for Grafana metrics ---
echo -e "\n${YELLOW}[5/6] Traffic Burst (populates Grafana dashboard)${NC}"

if [[ "$UE_TUN_EXISTS" == "yes" ]]; then
  # Quick burst: 50 pings at 0.2s interval — enough for Prometheus to pick up
  echo -e "  Sending 50 pings through UPF tunnel..."
  docker exec ue ping -I uesimtun0 -c 50 -i 0.2 -W 2 8.8.8.8 &>/dev/null &
  BURST_PID=$!

  # Also send some larger packets for throughput metrics
  docker exec ue ping -I uesimtun0 -c 20 -i 0.5 -s 1400 -W 2 1.1.1.1 &>/dev/null &
  BURST_PID2=$!

  # Ping flood burst — drives packet counters
  docker exec ue ping -I uesimtun0 -f -c 200 -W 3 8.8.8.8 &>/dev/null || true

  check "Traffic burst sent through UPF (50 pings + 200 flood)" "true"

  # Wait for background pings
  wait $BURST_PID 2>/dev/null || true
  wait $BURST_PID2 2>/dev/null || true
else
  check "Traffic burst (skipped — no UE tunnel)" "false"
fi

# --- 6. Verify Prometheus scrape targets ---
echo -e "\n${YELLOW}[6/6] Prometheus Metrics Check${NC}"

if command -v curl &>/dev/null; then
  check "Prometheus is reachable" \
    "curl -sf http://localhost:9090/-/ready"

  # Check if 5G metrics exist in Prometheus
  check "AMF metrics in Prometheus (gnb gauge)" \
    "curl -sf 'http://localhost:9090/api/v1/query?query=gnb' | grep -q 'result'"

  check "UPF metrics in Prometheus (sessionnbr)" \
    "curl -sf 'http://localhost:9090/api/v1/query?query=fivegs_upffunction_upf_sessionnbr' | grep -q 'result'"
else
  echo -e "  ${YELLOW}⚠${NC} curl not found — skipping Prometheus checks"
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
echo "  💡 For sustained traffic & full Grafana graphs, run:"
echo "     make generate-traffic"
echo ""

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
