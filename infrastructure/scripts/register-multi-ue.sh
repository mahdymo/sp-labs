#!/usr/bin/env bash
# ==============================================================================
# SP-Labs — Register All Multi-UE Subscribers
#
# Registers subscribers for ALL UE containers (base + profile UEs):
#   ue:             IMSIs 001–005  (basic profile,  default from docker-compose)
#   ue-power:       IMSIs 021–025  (power profile,  5G/2G AMBR)
#   ue-iot:         IMSIs 031–035  (iot profile,    1M/1M AMBR)
#   ue-enterprise:  IMSIs 041–045  (enterprise,     2G/1G AMBR)
#
# Usage:
#   bash register-multi-ue.sh           # Register all 20 subscribers
#   bash register-multi-ue.sh 10        # 10 per group = 40 total
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a; source "${REPO_ROOT}/.env"; set +a
fi

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

PER_GROUP="${1:-${NUM_UES:-5}}"
KEY="${SUBSCRIBER_KEY:-465B5CE8B199B49FAA5F0A2EE238A6BC}"
OPC="${SUBSCRIBER_OPC:-E8ED289DEBA952E4283B54E88E6183CA}"
MCC="${MCC:-999}"
MNC="${MNC:-70}"

echo ""
echo "==========================================="
echo "  SP-Labs — Multi-UE Subscriber Setup"
echo "==========================================="

# Profile definitions: start_offset apn dl_val dl_unit ul_val ul_unit qos
#   AMBR units: 0=bps, 1=Kbps, 2=Mbps, 3=Gbps
declare -A PROFILES=(
  [basic]="1 internet 1 3 500 2 9"
  [power]="21 internet 5 3 2 3 8"
  [iot]="31 internet 1 2 1 2 9"
  [enterprise]="41 internet 2 3 1 3 7"
)

BULK_DOCS=""
TOTAL=0

for profile in basic power iot enterprise; do
  read -r offset apn dl_v dl_u ul_v ul_u qos <<< "${PROFILES[$profile]}"

  echo -e "\n${YELLOW}[${profile^^}]${NC} IMSIs ${offset}–$((offset + PER_GROUP - 1))"

  for i in $(seq 0 $((PER_GROUP - 1))); do
    msisdn=$((offset + i))
    imsi="${MCC}${MNC}$(printf '%010d' $msisdn)"

    [[ -n "$BULK_DOCS" ]] && BULK_DOCS+=","
    BULK_DOCS+="
    {
      imsi:'${imsi}',msisdn:[],imeisv:'4370816125816151',
      mme_host:[],mme_realm:[],purge_flag:[],
      security:{k:'${KEY}',op:null,opc:'${OPC}',amf:'8000',sqn:NumberLong(65536)},
      ambr:{downlink:{value:${dl_v},unit:${dl_u}},uplink:{value:${ul_v},unit:${ul_u}}},
      schema_version:1,
      slice:[{sst:1,default_indicator:true,session:[{
        name:'${apn}',type:3,
        qos:{index:${qos},arp:{priority_level:8,pre_emption_capability:1,pre_emption_vulnerability:1}},
        ambr:{downlink:{value:${dl_v},unit:${dl_u}},uplink:{value:${ul_v},unit:${ul_u}}},
        pcc_rule:[]
      }]}]
    }"
    ((TOTAL++))
  done
  echo -e "  ${GREEN}✓${NC} ${PER_GROUP} subscribers (${apn}, DL=${dl_v}×unit${dl_u})"
done

echo -e "\n${YELLOW}[INSERT]${NC} Writing ${TOTAL} subscribers to MongoDB..."

docker exec mongodb mongosh --quiet --eval "
  db = db.getSiblingDB('open5gs');
  db.subscribers.deleteMany({});
  db.subscribers.insertMany([${BULK_DOCS}]);
  print('Registered ' + db.subscribers.countDocuments() + ' subscribers');
"

echo -e "${GREEN}[OK]${NC} ${TOTAL} subscribers registered"

# Verify
docker exec mongodb mongosh --quiet --eval "
  db = db.getSiblingDB('open5gs');
  print('');
  print('Subscriber groups:');
  var all = db.subscribers.find({},{imsi:1}).sort({imsi:1}).toArray();
  all.forEach(function(r){ print('  ' + r.imsi); });
  print('');
  print('Total: ' + all.length);
"

echo ""
echo "==========================================="
echo -e "  ${GREEN}Done!${NC} ${TOTAL} subscribers across 4 profiles"
echo ""
echo "  IMSI Map:"
echo -e "    ${CYAN}Basic${NC}:      ${MCC}${MNC}0000000001–$(printf '%010d' $PER_GROUP)"
echo -e "    ${CYAN}Power${NC}:      ${MCC}${MNC}0000000021–$(printf '%010d' $((20 + PER_GROUP)))"
echo -e "    ${CYAN}IoT${NC}:        ${MCC}${MNC}0000000031–$(printf '%010d' $((30 + PER_GROUP)))"
echo -e "    ${CYAN}Enterprise${NC}: ${MCC}${MNC}0000000041–$(printf '%010d' $((40 + PER_GROUP)))"
echo ""
echo "  Deploy UEs:  make deploy-multi-ue"
echo "  Traffic:     make generate-multi-traffic"
echo "==========================================="
