#!/usr/bin/env bash
# ==============================================================================
# SP-Labs — Register default subscriber in Open5GS via MongoDB
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source .env for subscriber defaults
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a; source "${REPO_ROOT}/.env"; set +a
fi

IMSI="${SUBSCRIBER_IMSI:-999700000000001}"
KEY="${SUBSCRIBER_KEY:-465B5CE8B199B49FAA5F0A2EE238A6BC}"
OPC="${SUBSCRIBER_OPC:-E8ED289DEBA952E4283B54E88E6183CA}"
APN="${SUBSCRIBER_APN:-internet}"
SST="${SUBSCRIBER_SST:-1}"

echo "[SP-Labs] Registering subscriber IMSI=${IMSI}..."

docker exec mongodb mongosh --quiet --eval "
  db = db.getSiblingDB('open5gs');

  // Remove existing subscriber if present
  db.subscribers.deleteOne({ 'imsi': '${IMSI}' });

  // Insert subscriber
  db.subscribers.insertOne({
    'imsi': '${IMSI}',
    'msisdn': [],
    'imeisv': '4370816125816151',
    'mme_host': [],
    'mme_realm': [],
    'purge_flag': [],
    'security': {
      'k': '${KEY}',
      'op': null,
      'opc': '${OPC}',
      'amf': '8000',
      'sqn': NumberLong(65536)
    },
    'ambr': {
      'downlink': { 'value': 1, 'unit': 3 },
      'uplink': { 'value': 1, 'unit': 3 }
    },
    'schema_version': 1,
    'slice': [
      {
        'sst': ${SST},
        'default_indicator': true,
        'session': [
          {
            'name': '${APN}',
            'type': 3,
            'qos': { 'index': 9, 'arp': { 'priority_level': 8, 'pre_emption_capability': 1, 'pre_emption_vulnerability': 1 } },
            'ambr': { 'downlink': { 'value': 1, 'unit': 3 }, 'uplink': { 'value': 1, 'unit': 3 } },
            'pcc_rule': []
          }
        ]
      }
    ]
  });

  print('Subscriber registered successfully: ' + '${IMSI}');
  print('Total subscribers: ' + db.subscribers.countDocuments());
"

echo "[SP-Labs] Subscriber ${IMSI} registered successfully"
