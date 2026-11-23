#!/usr/bin/env bash
# ==============================================================================
# SP-Labs — 5G Traffic Generator for Grafana Dashboard Population
#
# Generates sustained traffic through the UERANSIM UE tunnel (uesimtun0)
# to produce visible metrics in Prometheus/Grafana.
#
# Usage: bash infrastructure/scripts/generate-traffic.sh [duration_minutes]
# Default: 5 minutes of traffic generation
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
DURATION_MIN="${1:-5}"
DURATION_SEC=$((DURATION_MIN * 60))

echo ""
echo "==========================================="
echo "  SP-Labs — 5G Traffic Generator"
echo "==========================================="
echo -e "  Duration:  ${CYAN}${DURATION_MIN} minutes${NC}"
echo -e "  Started:   $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# --- Pre-flight: verify UE tunnel is up ---
echo -e "${YELLOW}[PRE-FLIGHT] Checking UE tunnel...${NC}"

if ! docker exec ue ip link show uesimtun0 &>/dev/null; then
    echo -e "${RED}[ERROR] UE tunnel (uesimtun0) not found.${NC}"
    echo "  Run 'make deploy-5g' and wait for UE registration."
    exit 1
fi

UE_IP=$(docker exec ue ip -4 addr show uesimtun0 | grep -oP 'inet \K[\d.]+')
echo -e "${GREEN}[OK]${NC} UE tunnel active — IP: ${UE_IP}"

# --- Phase 1: ICMP continuous pings ---
echo -e "\n${YELLOW}[PHASE 1/4] ICMP Traffic — Continuous pings${NC}"
docker exec ue ping -I uesimtun0 -i 0.5 -c $((DURATION_SEC * 2)) 8.8.8.8 &>/dev/null &
PID_PING1=$!
docker exec ue ping -I uesimtun0 -i 0.5 -c $((DURATION_SEC * 2)) 1.1.1.1 &>/dev/null &
PID_PING2=$!
docker exec ue ping -I uesimtun0 -i 1 -s 1400 -c $DURATION_SEC 8.8.4.4 &>/dev/null &
PID_PING3=$!
echo -e "${GREEN}[OK]${NC} 3 ping streams started"

# --- Phase 2: DNS lookups ---
echo -e "${YELLOW}[PHASE 2/4] DNS Traffic — Periodic lookups${NC}"
(
    for i in $(seq 1 $((DURATION_SEC / 3))); do
        docker exec ue sh -c "wget -q --timeout=2 -O /dev/null http://1.1.1.1/ 2>/dev/null || true" &>/dev/null
        sleep 3
    done
) &
PID_DNS=$!
echo -e "${GREEN}[OK]${NC} DNS stream started (every 3s)"

# --- Phase 3: HTTP downloads ---
echo -e "${YELLOW}[PHASE 3/4] HTTP Traffic — Small downloads${NC}"
(
    for i in $(seq 1 $((DURATION_SEC / 5))); do
        docker exec ue sh -c "wget -q --timeout=3 --bind-address=${UE_IP} -O /dev/null http://1.1.1.1/ 2>/dev/null || true; \
            wget -q --timeout=3 --bind-address=${UE_IP} -O /dev/null http://8.8.8.8/ 2>/dev/null || true" &>/dev/null
        sleep 5
    done
) &
PID_HTTP=$!
echo -e "${GREEN}[OK]${NC} HTTP download stream started (every 5s)"

# --- Phase 4: Burst traffic ---
echo -e "${YELLOW}[PHASE 4/4] Burst Traffic — Periodic ping floods${NC}"
(
    for i in $(seq 1 $((DURATION_MIN * 2))); do
        docker exec ue ping -I uesimtun0 -f -c 100 -W 2 8.8.8.8 &>/dev/null || true
        sleep 30
    done
) &
PID_BURST=$!
echo -e "${GREEN}[OK]${NC} Burst generator started (100-pkt floods every 30s)"

# --- Progress display ---
echo ""
echo -e "${CYAN}[RUNNING]${NC} Traffic generation active for ${DURATION_MIN} minutes..."
echo -e "         Grafana:    ${CYAN}http://<HOST>:3000${NC}"
echo -e "         Prometheus: ${CYAN}http://<HOST>:9090/targets${NC}"
echo ""

ELAPSED=0
INTERVAL=15
while [ $ELAPSED -lt $DURATION_SEC ]; do
    REMAINING=$(( (DURATION_SEC - ELAPSED) / 60 ))
    REMAINING_SEC=$(( (DURATION_SEC - ELAPSED) % 60 ))
    METRICS_OK="${RED}✗${NC}"
    docker exec ue ping -I uesimtun0 -c 1 -W 1 8.8.8.8 &>/dev/null && METRICS_OK="${GREEN}✓${NC}"
    echo -e "  [$(date '+%H:%M:%S')] ${METRICS_OK} Traffic flowing — ${REMAINING}m ${REMAINING_SEC}s remaining"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

# --- Cleanup ---
echo -e "\n${YELLOW}[CLEANUP]${NC} Stopping traffic generators..."
kill $PID_PING1 $PID_PING2 $PID_PING3 $PID_DNS $PID_HTTP $PID_BURST 2>/dev/null || true
wait 2>/dev/null || true

# --- Final metrics snapshot ---
echo -e "\n${YELLOW}[RESULTS]${NC} Querying final metric values from Prometheus..."
if command -v curl &>/dev/null; then
    echo ""
    for section_name in "AMF" "SMF" "UPF"; do
        echo "  ${section_name} Metrics:"
        case $section_name in
            AMF) metrics="gnb ran_ue amf_session fivegs_amffunction_rm_reginitreq fivegs_amffunction_rm_reginitsucc" ;;
            SMF) metrics="ues_active bearers_active fivegs_smffunction_sm_n4sessionestabreq" ;;
            UPF) metrics="fivegs_upffunction_upf_sessionnbr fivegs_ep_n3_gtp_indatapktn3upf fivegs_ep_n3_gtp_outdatapktn3upf" ;;
        esac
        for metric in $metrics; do
            VAL=$(curl -s "http://localhost:9090/api/v1/query?query=${metric}" 2>/dev/null | \
                  grep -oP '"value":\[\d+\.?\d*,"(\d+)"' | grep -oP '"\d+"' | tr -d '"' | head -1)
            if [ -n "$VAL" ]; then
                echo -e "    ${GREEN}${metric}${NC} = ${VAL}"
            else
                echo -e "    ${YELLOW}${metric}${NC} = (no data)"
            fi
        done
        echo ""
    done
fi

echo "==========================================="
echo -e "  ${GREEN}Traffic generation complete!${NC}"
echo -e "  Duration: ${DURATION_MIN} minutes"
echo -e "  Ended:    $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "  Dashboard: Grafana → SP-Labs → SP-Labs — 5G Core Overview"
echo "==========================================="
echo ""

