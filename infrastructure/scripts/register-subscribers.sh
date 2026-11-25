#!/usr/bin/env bash
# ==============================================================================
# SP-Labs — Register Multiple Subscribers in Open5GS via MongoDB
#
# Creates subscribers with different profiles simulating real SP traffic mix:
#   - Basic users     (1 Gbps DL / 500 Mbps UL, eMBB, APN: internet)
#   - Power users     (5 Gbps DL / 2 Gbps UL,   eMBB, APN: internet)
#   - IoT devices     (1 Mbps DL / 1 Mbps UL,   MIoT, APN: iot)
#   - Enterprise      (2 Gbps DL / 1 Gbps UL,   eMBB, APN: enterprise)
#
# Usage:
#   bash register-subscribers.sh                    # 10 subs (default)
#   bash register-subscribers.sh 20                 # 20 subs
#   bash register-subscribers.sh 50 --profiles      # 50 subs, mixed profiles
#
# IMSI range: 999700000000001 – 999700000000NNN
# All share the same K/OPc (lab simplification)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a; source "${REPO_ROOT}/.env"; set +a
fi

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; NC='\033[0m'

NUM_SUBS="${1:-10}"
USE_PROFILES="${2:-}"
KEY="${SUBSCRIBER_KEY:-465B5CE8B199B49FAA5F0A2EE238A6BC}"
OPC="${SUBSCRIBER_OPC:-E8ED289DEBA952E4283B54E88E6183CA}"
MCC="${MCC:-999}"
MNC="${MNC:-70}"

echo ""
echo "==========================================="
echo "  SP-Labs — Multi-Subscriber Registration"
echo "==========================================="
echo -e "  Count:    ${CYAN}${NUM_SUBS}${NC} subscribers"
echo -e "  Profiles: ${CYAN}${USE_PROFILES:-single (internet/eMBB)}${NC}"
echo -e "  IMSI:     ${CYAN}${MCC}${MNC}0000000001 – ${MCC}${MNC}$(printf '%010d' ${NUM_SUBS})${NC}"
echo ""

# Profile assignment: 60% basic, 15% power, 15% iot, 10% enterprise
get_profile() {
  local idx=$1 total=$2
  if [[ "${USE_PROFILES}" == "--profiles" ]]; then
    local pct=$(( (idx * 100) / total ))
    if   (( pct < 60 )); then echo "basic"
    elif (( pct < 75 )); then echo "power"
    elif (( pct < 90 )); then echo "iot"
    else                       echo "enterprise"; fi
  else
    echo "basic"
  fi
}

# Profile → {apn, dl_value, dl_unit, ul_value, ul_unit, sst, qos_index}
# AMBR units: 0=bps, 1=Kbps, 2=Mbps, 3=Gbps
profile_values() {
  case "$1" in
    basic)      echo "internet 1 3 500 2 1 9" ;;
    power)      echo "internet 5 3 2 3 1 8" ;;
    iot)        echo "iot 1 2 1 2 3 9" ;;
    enterprise) echo "enterprise 2 3 1 3 1 7" ;;
  esac
}

# ==============================================================================
# Build & execute bulk MongoDB insert
# ==============================================================================
echo -e "${YELLOW}[1/3] Building subscriber records...${NC}"

BASIC=0; POWER=0; IOT=0; ENTERPRISE=0
BULK_DOCS=""

for i in $(seq 1 "${NUM_SUBS}"); do
  imsi="${MCC}${MNC}$(printf '%010d' $i)"
  profile=$(get_profile $i "${NUM_SUBS}")
  read -r apn dl_v dl_u ul_v ul_u sst qos <<< "$(profile_values "$profile")"

  case "$profile" in
    basic) ((BASIC++));; power) ((POWER++));;
    iot) ((IOT++));; enterprise) ((ENTERPRISE++));;
  esac

  [[ -n "$BULK_DOCS" ]] && BULK_DOCS+=","
  BULK_DOCS+="
  {
    imsi:'${imsi}', msisdn:[], imeisv:'4370816125816151',
    mme_host:[], mme_realm:[], purge_flag:[],
    security:{k:'${KEY}',op:null,opc:'${OPC}',amf:'8000',sqn:NumberLong(65536)},
    ambr:{downlink:{value:${dl_v},unit:${dl_u}},uplink:{value:${ul_v},unit:${ul_u}}},
    schema_version:1,
    slice:[{sst:${sst},default_indicator:true,session:[{
      name:'${apn}',type:3,
      qos:{index:${qos},arp:{priority_level:8,pre_emption_capability:1,pre_emption_vulnerability:1}},
      ambr:{downlink:{value:${dl_v},unit:${dl_u}},uplink:{value:${ul_v},unit:${ul_u}}},
      pcc_rule:[]
    }]}]
  }"
done

echo -e "${GREEN}[OK]${NC} ${NUM_SUBS} records built"
echo -e "     Basic: ${BASIC}  Power: ${POWER}  IoT: ${IOT}  Enterprise: ${ENTERPRISE}"

echo -e "\n${YELLOW}[2/3] Inserting into MongoDB...${NC}"

docker exec mongodb mongosh --quiet --eval "
  db = db.getSiblingDB('open5gs');
  db.subscribers.deleteMany({});
  db.subscribers.insertMany([${BULK_DOCS}]);
  print('Registered ' + db.subscribers.countDocuments() + ' subscribers');
"

echo -e "${GREEN}[OK]${NC} Subscribers inserted"

echo -e "\n${YELLOW}[3/3] Verifying...${NC}"

docker exec mongodb mongosh --quiet --eval "
  db = db.getSiblingDB('open5gs');
  var total = db.subscribers.countDocuments();
  print('Total subscribers in DB: ' + total);
  var s = db.subscribers.find({},{imsi:1,'slice.sst':1,'slice.session.name':1}).limit(5).toArray();
  s.forEach(function(r){
    print('  IMSI: '+r.imsi+'  SST: '+r.slice[0].sst+'  APN: '+r.slice[0].session[0].name);
  });
  if(total>5) print('  ... and '+(total-5)+' more');
"

echo ""
echo "==========================================="
echo -e "  ${GREEN}Registration complete!${NC}"
echo ""
echo -e "  ${CYAN}Basic     ${NC} (1G/500M, internet): ${BASIC}"
echo -e "  ${CYAN}Power     ${NC} (5G/2G,   internet): ${POWER}"
echo -e "  ${CYAN}IoT       ${NC} (1M/1M,   iot):      ${IOT}"
echo -e "  ${CYAN}Enterprise${NC} (2G/1G,   enterprise):${ENTERPRISE}"
echo ""
echo "  Next: make restart-ues"
echo "==========================================="
