#!/usr/bin/env bash
# ==============================================================================
# SP-Labs — Multi-UE Traffic Generator
#
# Drives differentiated traffic patterns across multiple UE containers to
# simulate realistic SP network load for BIG-IP testing & Grafana dashboards.
#
# Traffic profiles per UE type:
#   ue        — Bulk users: moderate pings + HTTP downloads
#   ue-power  — Heavy hitter: large downloads, high bandwidth
#   ue-iot    — IoT sensor: tiny payloads, infrequent, low bandwidth
#   ue-enterprise — Business user: steady HTTP, DNS, mixed workload
#
# Usage:
#   bash generate-multi-traffic.sh              # 5 min (default)
#   bash generate-multi-traffic.sh 15           # 15 min
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; NC='\033[0m'
DURATION_MIN="${1:-5}"
DURATION_SEC=$((DURATION_MIN * 60))
PIDS=()

cleanup() {
  echo -e "\n${YELLOW}[CLEANUP]${NC} Stopping all traffic generators..."
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  echo -e "${GREEN}[DONE]${NC} All generators stopped"
}
trap cleanup EXIT

echo ""
echo "==========================================="
echo "  SP-Labs — Multi-UE Traffic Generator"
echo "==========================================="
echo -e "  Duration: ${CYAN}${DURATION_MIN} minutes${NC}"
echo -e "  Started:  $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ==============================================================================
# Discover active UE containers with TUN interfaces
# ==============================================================================
echo -e "${YELLOW}[DISCOVERY]${NC} Scanning for active UE containers..."

declare -A UE_MAP  # container → TUN IP
CONTAINERS=()

for cname in ue ue-power ue-iot ue-enterprise; do
  if docker inspect -f '{{.State.Running}}' "$cname" 2>/dev/null | grep -q true; then
    # Find all uesimtunX interfaces in this container
    tun_ips=$(docker exec "$cname" ip -4 addr show 2>/dev/null \
      | grep -oP 'inet \K[\d.]+(?=.*uesimtun)' || true)
    if [[ -n "$tun_ips" ]]; then
      UE_MAP["$cname"]="$tun_ips"
      CONTAINERS+=("$cname")
      tun_count=$(echo "$tun_ips" | wc -l)
      echo -e "  ${GREEN}✓${NC} ${cname}: ${tun_count} tunnel(s) — IPs: $(echo $tun_ips | tr '\n' ' ')"
    else
      echo -e "  ${YELLOW}⚠${NC} ${cname}: running but no TUN interface yet"
    fi
  fi
done

if [[ ${#CONTAINERS[@]} -eq 0 ]]; then
  echo -e "\n${RED}[ERROR]${NC} No UE containers with active tunnels found."
  echo "  Run 'make deploy-5g' and 'make register-subs' first."
  exit 1
fi

TOTAL_TUNS=0
for c in "${CONTAINERS[@]}"; do
  TOTAL_TUNS=$((TOTAL_TUNS + $(echo "${UE_MAP[$c]}" | wc -l)))
done
echo -e "\n  Total: ${CYAN}${#CONTAINERS[@]}${NC} containers, ${CYAN}${TOTAL_TUNS}${NC} tunnels"

# ==============================================================================
# Traffic pattern functions — each runs in background for DURATION_SEC
# ==============================================================================

# Standard user: moderate pings + periodic HTTP
traffic_basic() {
  local cname=$1 tun_ip=$2 iface=$3
  # Steady pings
  docker exec "$cname" ping -I "$iface" -i 0.5 -c $((DURATION_SEC * 2)) 8.8.8.8 &>/dev/null &
  PIDS+=($!)
  docker exec "$cname" ping -I "$iface" -i 1 -c "$DURATION_SEC" 1.1.1.1 &>/dev/null &
  PIDS+=($!)
  # Periodic HTTP
  (
    for _ in $(seq 1 $((DURATION_SEC / 5))); do
      docker exec "$cname" wget -q --timeout=3 --bind-address="$tun_ip" \
        -O /dev/null http://1.1.1.1/ 2>/dev/null || true
      sleep 5
    done
  ) &
  PIDS+=($!)
}

# Power user: large packets, frequent downloads, burst floods
traffic_power() {
  local cname=$1 tun_ip=$2 iface=$3
  # Large ping packets — drives throughput
  docker exec "$cname" ping -I "$iface" -i 0.2 -s 1400 \
    -c $((DURATION_SEC * 5)) 8.8.8.8 &>/dev/null &
  PIDS+=($!)
  # Frequent HTTP downloads
  (
    for _ in $(seq 1 $((DURATION_SEC / 2))); do
      docker exec "$cname" wget -q --timeout=3 --bind-address="$tun_ip" \
        -O /dev/null http://1.1.1.1/ 2>/dev/null || true
      docker exec "$cname" wget -q --timeout=3 --bind-address="$tun_ip" \
        -O /dev/null http://8.8.8.8/ 2>/dev/null || true
      sleep 2
    done
  ) &
  PIDS+=($!)
  # Periodic burst floods
  (
    for _ in $(seq 1 $((DURATION_MIN * 3))); do
      docker exec "$cname" ping -I "$iface" -f -c 200 -W 2 \
        8.8.8.8 &>/dev/null || true
      sleep 20
    done
  ) &
  PIDS+=($!)
}

# IoT device: tiny packets, long intervals
traffic_iot() {
  local cname=$1 tun_ip=$2 iface=$3
  # Small infrequent pings — simulating sensor heartbeat
  docker exec "$cname" ping -I "$iface" -i 10 -s 64 \
    -c $((DURATION_SEC / 10)) 8.8.8.8 &>/dev/null &
  PIDS+=($!)
  # Occasional tiny HTTP "telemetry upload"
  (
    for _ in $(seq 1 $((DURATION_SEC / 30))); do
      docker exec "$cname" wget -q --timeout=5 --bind-address="$tun_ip" \
        -O /dev/null http://1.1.1.1/ 2>/dev/null || true
      sleep 30
    done
  ) &
  PIDS+=($!)
}

# Enterprise user: steady mixed workload
traffic_enterprise() {
  local cname=$1 tun_ip=$2 iface=$3
  # Steady pings
  docker exec "$cname" ping -I "$iface" -i 1 \
    -c "$DURATION_SEC" 8.8.8.8 &>/dev/null &
  PIDS+=($!)
  # DNS lookups
  (
    for _ in $(seq 1 $((DURATION_SEC / 3))); do
      docker exec "$cname" wget -q --timeout=2 --bind-address="$tun_ip" \
        -O /dev/null http://1.1.1.1/ 2>/dev/null || true
      sleep 3
    done
  ) &
  PIDS+=($!)
  # Medium HTTP downloads
  (
    for _ in $(seq 1 $((DURATION_SEC / 4))); do
      docker exec "$cname" wget -q --timeout=3 --bind-address="$tun_ip" \
        -O /dev/null http://8.8.8.8/ 2>/dev/null || true
      sleep 4
    done
  ) &
  PIDS+=($!)
}

# ==============================================================================
# Launch traffic for each UE container
# ==============================================================================
echo -e "\n${YELLOW}[LAUNCHING]${NC} Starting traffic generators..."

for cname in "${CONTAINERS[@]}"; do
  tun_ips="${UE_MAP[$cname]}"
  tun_idx=0

  while IFS= read -r tun_ip; do
    iface="uesimtun${tun_idx}"

    # Pick traffic pattern based on container name
    case "$cname" in
      ue)             traffic_basic      "$cname" "$tun_ip" "$iface" ;;
      ue-power)       traffic_power      "$cname" "$tun_ip" "$iface" ;;
      ue-iot)         traffic_iot        "$cname" "$tun_ip" "$iface" ;;
      ue-enterprise)  traffic_enterprise "$cname" "$tun_ip" "$iface" ;;
      *)              traffic_basic      "$cname" "$tun_ip" "$iface" ;;
    esac

    echo -e "  ${GREEN}▶${NC} ${cname}/${iface} (${tun_ip}): $(
      case "$cname" in
        ue)            echo 'basic — pings + HTTP' ;;
        ue-power)      echo 'power — large pkts + floods' ;;
        ue-iot)        echo 'iot — tiny heartbeats' ;;
        ue-enterprise) echo 'enterprise — steady mixed' ;;
        *)             echo 'basic' ;;
      esac
    )"

    ((tun_idx++))
  done <<< "$tun_ips"
done

echo -e "\n${CYAN}[RUNNING]${NC} ${#PIDS[@]} background generators active for ${DURATION_MIN}m"
echo -e "         Grafana:    ${CYAN}http://<HOST>:3000${NC}"
echo -e "         Prometheus: ${CYAN}http://<HOST>:9090/targets${NC}"
echo ""

# --- Progress display ---
ELAPSED=0
INTERVAL=15
while [ $ELAPSED -lt $DURATION_SEC ]; do
  REMAINING=$(( (DURATION_SEC - ELAPSED) / 60 ))
  REMAINING_SEC=$(( (DURATION_SEC - ELAPSED) % 60 ))

  # Quick health check on first UE
  first="${CONTAINERS[0]}"
  first_ip=$(echo "${UE_MAP[$first]}" | head -1)
  STATUS="${RED}✗${NC}"
  docker exec "$first" ping -I uesimtun0 -c 1 -W 1 8.8.8.8 &>/dev/null \
    && STATUS="${GREEN}✓${NC}"

  # Count active background jobs
  ACTIVE=0
  for pid in "${PIDS[@]}"; do
    kill -0 "$pid" 2>/dev/null && ((ACTIVE++)) || true
  done

  echo -e "  [$(date '+%H:%M:%S')] ${STATUS} ${ACTIVE}/${#PIDS[@]} generators active — ${REMAINING}m ${REMAINING_SEC}s left"
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

# --- Final metrics ---
echo -e "\n${YELLOW}[RESULTS]${NC} Final metric snapshot from Prometheus..."
if command -v curl &>/dev/null; then
  for metric in gnb ran_ue amf_session ues_active fivegs_upffunction_upf_sessionnbr \
                fivegs_ep_n3_gtp_indatapktn3upf fivegs_ep_n3_gtp_outdatapktn3upf; do
    VAL=$(curl -sf "http://localhost:9090/api/v1/query?query=${metric}" 2>/dev/null \
      | grep -oP '"value":\[\d+\.?\d*,"(\d+)"' | grep -oP '"\d+"' | tr -d '"' | head -1)
    if [ -n "$VAL" ]; then
      echo -e "  ${GREEN}${metric}${NC} = ${VAL}"
    else
      echo -e "  ${YELLOW}${metric}${NC} = (no data)"
    fi
  done
fi

echo ""
echo "==========================================="
echo -e "  ${GREEN}Multi-UE traffic generation complete!${NC}"
echo -e "  Containers: ${#CONTAINERS[@]}  Tunnels: ${TOTAL_TUNS}  Duration: ${DURATION_MIN}m"
echo -e "  Ended: $(date '+%Y-%m-%d %H:%M:%S')"
echo "==========================================="

