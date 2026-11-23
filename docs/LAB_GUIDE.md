# SP-Labs — Complete Lab Guide

> **Audience:** Engineers deploying, operating, and troubleshooting the SP-Labs
> 5G & 6G telco lab environment.
>
> **Last updated:** 2026-11-23 · **Spec version:** 1.0

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Architecture Overview](#2-architecture-overview)
3. [Prerequisites](#3-prerequisites)
4. [Repository Layout](#4-repository-layout)
5. [Environment Configuration](#5-environment-configuration)
6. [Deploying the 5G Lab](#6-deploying-the-5g-lab)
7. [Deploying the Monitoring Stack](#7-deploying-the-monitoring-stack)
8. [Deploying the 6G Lab](#8-deploying-the-6g-lab)
9. [End-to-End Verification](#9-end-to-end-verification)
10. [Web Interfaces](#10-web-interfaces)
11. [Subscriber Management](#11-subscriber-management)
12. [Monitoring & Dashboards](#12-monitoring--dashboards)
13. [Day-to-Day Operations](#13-day-to-day-operations)
14. [Configuration Deep-Dive](#14-configuration-deep-dive)
15. [Networking Reference](#15-networking-reference)
16. [Troubleshooting](#16-troubleshooting)
17. [Lessons Learned & Gotchas](#17-lessons-learned--gotchas)
18. [Appendix A — Make Targets](#appendix-a--make-targets)
19. [Appendix B — Container Reference](#appendix-b--container-reference)
20. [Appendix C — Config File Reference](#appendix-c--config-file-reference)

---

## 1. Introduction

SP-Labs is a fully automated, Docker Compose-based telco lab that deploys:

| Lab | Components | Purpose |
|-----|-----------|---------|
| **5G Lab** | Open5GS v2.7.0 (11 NFs) + UERANSIM v3.2.6 (gNB + UE) + MongoDB 6.0 + WebUI | End-to-end 5G SA network |
| **6G Lab** | NVIDIA Sionna 0.19.1, ns-3 3.42, O-RAN Near-RT RIC | 6G research & AI/ML-driven RAN |
| **Monitoring** | Prometheus v2.55.0 + Grafana 11.3.0 + Node Exporter v1.8.2 | Observability for all lab components |

**Philosophy:** Clone → Bootstrap → `make deploy-5g` → working 5G network in
under 10 minutes. No manual configuration required for single-host deployment.

---

## 2. Architecture Overview

### 2.1 5G SA Core (3GPP Release 16+)

The lab implements a full 5G Standalone (SA) core using the Service-Based
Architecture (SBA). Every network function (NF) registers with the NRF and
communicates over HTTP/2 SBI interfaces through the SCP.

```
                    ┌──────────────────────────────────────────────────────┐
                    │              5G Service-Based Architecture (SBA)     │
                    │                                                      │
                    │  ┌─────┐ ┌──────┐ ┌─────┐ ┌─────┐ ┌──────┐         │
                    │  │ NRF │ │ NSSF │ │ BSF │ │ SCP │ │ PCF  │         │
                    │  └──┬──┘ └──┬───┘ └──┬──┘ └──┬──┘ └──┬───┘         │
                    │     │       │        │       │       │   SBI Bus    │
   ┌──────────┐     │  ┌──┴──┐ ┌──┴───┐ ┌──┴──┐ ┌─┴───┐ ┌┴────┐        │
   │ UERANSIM │     │  │ AMF │ │ AUSF │ │ UDM │ │ UDR │ │ SMF │        │
   │          │     │  └──┬──┘ └──────┘ └─────┘ └─────┘ └──┬──┘        │
   │  ┌────┐  │ N2  │     │                                 │ N4        │
   │  │ gNB├──┼─────┼─────┘                                 │ (PFCP)   │
   │  └──┬─┘  │     │                                  ┌────┴────┐     │
   │     │    │ N3  │                                  │   UPF   │     │
   │  ┌──┴─┐  │(GTP)│                                  │         │     │
   │  │ UE ├──┼─────┼──────────────────────────────────▶│  ┌───┐  │     │
   │  └────┘  │     │                                  │  │TUN│  │     │
   └──────────┘     │                                  │  └─┬─┘  │     │
                    │                                  └────┼────┘     │
                    └───────────────────────────────────────┼──────────┘
                                                           │ N6
                                                    ┌──────┴──────┐
                                                    │ Data Network│
                                                    │ (internet)  │
                                                    └─────────────┘
```

### 2.2 5G Interface Reference

| Interface | Between | Protocol | Purpose |
|-----------|---------|----------|---------|
| **SBI** | NF ↔ NF | HTTP/2 (port 7777) | Service-based interface |
| **N2** | gNB ↔ AMF | NGAP/SCTP (port 38412) | RAN control plane |
| **N3** | gNB ↔ UPF | GTP-U/UDP (port 2152) | User data tunnel |
| **N4** | SMF ↔ UPF | PFCP/UDP (port 8805) | Session establishment & rules |
| **N6** | UPF ↔ DN | IP | User traffic to internet |

### 2.3 Signal Flows

**UE Registration:**
```
UE → gNB → [N2/NGAP] → AMF → [SBI] → AUSF → UDM → UDR (auth vectors)
                         AMF → [SBI] → UDM (registration confirm)
                         AMF → [N2] → gNB → UE (Registration Accept)
```

**PDU Session Establishment:**
```
UE → AMF (NAS) → SMF (SBI) → PCF (SBI: policy fetch)
                  SMF → UPF [N4/PFCP: session create, tunnel setup]
                  SMF → AMF → gNB → UE (PDU Session Accept + tunnel info)
```

**User Data Path:**
```
UE → gNB → [N3/GTP-U] → UPF → [N6/ogstun] → Internet
```

### 2.4 Monitoring Architecture

```
┌─────────────────────────────────────────────┐
│          Prometheus (10.33.38.200)           │
│  Scrapes:                                   │
│   • AMF metrics  → 10.33.33.12:9090 (SBI)  │
│   • SMF metrics  → 10.33.33.13:9090 (SBI)  │
│   • UPF metrics  → 10.33.38.14:9090 (mgmt) │
│   • Node Exporter → node-exporter:9100      │
│   • Self          → localhost:9090          │
└──────────────┬──────────────────────────────┘
               │
        ┌──────┴──────┐
        │   Grafana   │
        │ (10.33.38.201)
        │ Port :3000  │
        └─────────────┘
```

Prometheus is attached to both the **SBI** and **mgmt** networks so it can
reach NF metrics on SBI (10.33.33.x) and UPF/node-exporter on mgmt
(10.33.38.x).

---

## 3. Prerequisites

### 3.1 Hardware Requirements

| Deployment | vCPUs | RAM | Disk | GPU |
|------------|-------|-----|------|-----|
| 5G Lab only | 8 | 16 GB | 80 GB SSD | — |
| 5G + Monitoring | 8 | 16 GB | 100 GB SSD | — |
| 5G + 6G + Monitoring | 16 | 32 GB | 150 GB SSD | NVIDIA 8 GB+ VRAM |

### 3.2 Software Requirements

| Software | Version | Notes |
|----------|---------|-------|
| **OS** | Ubuntu 22.04 LTS or 24.04 LTS | Tested on 22.04 |
| **Docker Engine** | 24.0+ | Installed by bootstrap |
| **Docker Compose** | v2.x | Bundled with Docker 24+ |
| **Git** | Any | To clone the repo |
| **make** | Any | For Makefile targets |
| **NVIDIA Drivers** | 535+ | Only for 6G/Sionna |
| **NVIDIA Container Toolkit** | Latest | Only for 6G/Sionna |

### 3.3 Network Requirements

- **Internet access** to pull Docker images from Docker Hub
- Ports **9999** (WebUI), **3000** (Grafana), **9090** (Prometheus) must be
  free on the host (or firewall-opened for remote access)
- No conflicting Docker networks in the `10.33.33.0/24` – `10.33.38.0/24`
  or `10.33.60.0/24` range

---

## 4. Repository Layout

```
sp-labs/
├── 5g-lab/                          # ── 5G SA Core ──
│   ├── docker-compose.yml           # Main compose: 15 containers
│   ├── open5gs/config/              # Open5GS NF configs (YAML)
│   │   ├── nrf.yaml  ├── scp.yaml  ├── amf.yaml
│   │   ├── smf.yaml  ├── upf.yaml  ├── udr.yaml
│   │   ├── pcf.yaml  ├── ausf.yaml ├── udm.yaml
│   │   ├── bsf.yaml  └── nssf.yaml
│   └── ueransim/config/            # UERANSIM configs
│       ├── gnb.yaml  └── ue.yaml
├── 6g-lab/                          # ── 6G Research ──
│   ├── docker-compose.yml           # Sionna + ns-3 + O-RAN RIC
│   ├── sionna/  ├── ns3/  └── oran-ric/
├── monitoring/                      # ── Observability ──
│   ├── docker-compose.yml           # Prometheus + Grafana + Node Exporter
│   ├── prometheus/prometheus.yml    # Scrape targets
│   └── grafana/                     # Provisioning + dashboards
├── infrastructure/                  # ── Automation ──
│   ├── scripts/                     # bootstrap, preflight, test, register
│   ├── ansible/                     # Multi-VM provisioning
│   └── vagrant/                     # Local multi-VM dev
├── docs/                            # ── Documentation ──
│   ├── ARCHITECTURE.md   ├── NETWORKING.md   ├── SPEC.md
│   ├── PREREQUISITES.md  ├── TROUBLESHOOTING.md
│   └── LAB_GUIDE.md                # ⬅ THIS DOCUMENT
├── .env.example                     # Template environment variables
├── Makefile                         # Top-level make targets
└── README.md
```


---

## 5. Environment Configuration

### 5.1 Create Your .env File

```bash
cp .env.example .env
```

The `.env` file is **git-ignored** and holds all tunable parameters. Defaults
work out of the box — edit only if you need to customize.

### 5.2 Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MCC` | `999` | Mobile Country Code (test network) |
| `MNC` | `70` | Mobile Network Code (test network) |
| `TAC` | `1` | Tracking Area Code |
| `SUBSCRIBER_IMSI` | `999700000000001` | Default test subscriber IMSI |
| `SUBSCRIBER_KEY` | `465B5CE8...` | Authentication key (K) |
| `SUBSCRIBER_OPC` | `E8ED289D...` | Authentication OPc |
| `SUBSCRIBER_APN` | `internet` | Default Data Network Name |
| `SUBSCRIBER_SST` | `1` | Network Slice (1 = eMBB) |
| `GRAFANA_ADMIN_PASSWORD` | `sp-labs-admin` | Grafana admin password |
| `NET_SBI` – `NET_MGMT` | `10.33.33–38.0/24` | Docker network subnets |

> **Multi-VM deployment** requires additional variables (`VM_5G_CORE_IP`,
> `ANSIBLE_USER`, `ANSIBLE_SSH_KEY`, etc.). See
> [PREREQUISITES.md](PREREQUISITES.md) §3 for details.

---

## 6. Deploying the 5G Lab

### 6.1 Quick Deploy (Recommended)

```bash
# 1. Clone the repo
git clone https://github.com/<your-org>/sp-labs.git
cd sp-labs

# 2. Bootstrap the host (installs Docker, configures kernel, sets up NAT)
chmod +x infrastructure/scripts/bootstrap.sh
sudo ./infrastructure/scripts/bootstrap.sh --full

# 3. Deploy the 5G core + RAN simulator
make deploy-5g
```

The `make deploy-5g` target:
1. Creates `.env` from `.env.example` if missing
2. Runs `docker compose -f 5g-lab/docker-compose.yml up -d`
3. Waits 15 seconds for services to start
4. Runs `register-subscriber.sh` to insert the default subscriber into MongoDB
5. Reports "5G Lab is UP"

### 6.2 What Gets Started (15 Containers)

| # | Container | Image | Role |
|---|-----------|-------|------|
| 1 | `mongodb` | `mongo:6.0` | Subscriber database |
| 2 | `nrf` | `openverso/open5gs:2.7.0` | NF Repository Function |
| 3 | `scp` | `openverso/open5gs:2.7.0` | Service Communication Proxy |
| 4 | `amf` | `openverso/open5gs:2.7.0` | Access & Mobility Management |
| 5 | `smf` | `openverso/open5gs:2.7.0` | Session Management |
| 6 | `upf` | `openverso/open5gs:2.7.0` | User Plane Function |
| 7 | `ausf` | `openverso/open5gs:2.7.0` | Authentication Server |
| 8 | `udm` | `openverso/open5gs:2.7.0` | Unified Data Management |
| 9 | `udr` | `openverso/open5gs:2.7.0` | Unified Data Repository |
| 10 | `pcf` | `openverso/open5gs:2.7.0` | Policy Control |
| 11 | `nssf` | `openverso/open5gs:2.7.0` | Network Slice Selection |
| 12 | `bsf` | `openverso/open5gs:2.7.0` | Binding Support |
| 13 | `webui` | `gradiant/open5gs-webui:2.7.1` | Subscriber management UI |
| 14 | `gnb` | `openverso/ueransim:3.2.6` | Simulated gNodeB |
| 15 | `ue` | `openverso/ueransim:3.2.6` | Simulated User Equipment |

### 6.3 Startup Order & Dependencies

```
mongodb
  └─► nrf
       └─► scp
            ├─► amf ──► gnb ──► ue
            ├─► smf ──► upf
            ├─► ausf
            ├─► udm
            ├─► udr (also depends on mongodb)
            ├─► pcf (also depends on mongodb)
            ├─► nssf
            └─► bsf
  └─► webui
```

### 6.4 Manual Deploy (Without Make)

```bash
cd 5g-lab
docker compose up -d
sleep 15
bash ../infrastructure/scripts/register-subscriber.sh
docker compose ps
```

### 6.5 Verifying Deployment

```bash
# All 15 containers should show "Up"
docker compose -f 5g-lab/docker-compose.yml ps

# Check key NF logs
docker logs amf --tail=20   # Look for: NG Setup Response
docker logs gnb --tail=20   # Look for: Connected to AMF
docker logs ue  --tail=20   # Look for: Registration complete, PDU session
```


---

## 7. Deploying the Monitoring Stack

### 7.1 Deploy

```bash
make deploy-monitoring
```

Or manually:
```bash
# Ensure the external networks exist (created by 5G lab)
docker network inspect sp-labs-mgmt >/dev/null 2>&1 || \
  docker network create --driver bridge --subnet 10.33.38.0/24 sp-labs-mgmt
docker network inspect sp-labs-sbi >/dev/null 2>&1 || \
  docker network create --driver bridge --subnet 10.33.33.0/24 sp-labs-sbi

cd monitoring
docker compose up -d
```

### 7.2 What Gets Started (3 Containers)

| Container | Image | Port | Purpose |
|-----------|-------|------|---------|
| `prometheus` | `prom/prometheus:v2.55.0` | 9090 | Metrics collection & storage |
| `grafana` | `grafana/grafana:11.3.0` | 3000 | Dashboards & visualization |
| `node-exporter` | `prom/node-exporter:v1.8.2` | 9100 | Host OS metrics |

> **Important:** Deploy the 5G lab **before** the monitoring stack. The
> monitoring compose references `sp-labs-sbi` and `sp-labs-mgmt` as
> `external: true` — they must exist first.

---

## 8. Deploying the 6G Lab

### 8.1 Deploy

```bash
make deploy-6g
```

This auto-detects GPU availability:
- **GPU detected:** `docker compose --profile gpu up -d` → `sionna` container
- **No GPU:** `docker compose --profile cpu up -d` → `sionna-cpu` container

### 8.2 What Gets Started

| Container | Port | Purpose |
|-----------|------|---------|
| `sionna` or `sionna-cpu` | 8888 | GPU/CPU Sionna PHY simulator (Jupyter) |
| `ns3` | — | ns-3 network simulator (batch) |
| `oran-ric-db` | — | O-RAN RIC database (Redis) |
| `oran-ric-e2term` | — | E2 termination |
| `oran-ric-e2mgr` | 3800 | E2 manager |

> The ns-3 Dockerfile **builds from source** (~20 min on first run).

---

## 9. End-to-End Verification

### 9.1 Automated Test

```bash
make test-5g
```

This runs `infrastructure/scripts/test-5g.sh` which validates four phases:

| Phase | Tests |
|-------|-------|
| **1/4 — Container Health** | All 15 containers running |
| **2/4 — Network Connectivity** | gNB↔AMF (N2), gNB↔UPF (N3), SMF↔UPF (N4), NRF (SBI) |
| **3/4 — UE Registration** | NGAP connection, registration accept, PDU session |
| **4/4 — Data Path** | UE has uesimtun0 with 10.45.x.x IP, can ping 8.8.8.8 |

**Expected output:**
```
===========================================
  SP-Labs — 5G End-to-End Validation
===========================================

[1/4] Container Health
  ✓ Container 'mongodb' is running
  ✓ Container 'nrf' is running
  ... (15 containers)

[2/4] Network Connectivity
  ✓ gNB can reach AMF on N2 (10.33.34.12)
  ✓ gNB can reach UPF on N3 (10.33.35.14)
  ✓ SMF can reach UPF on N4 (10.33.36.14)
  ✓ NRF is reachable on SBI

[3/4] UE Registration & PDU Session
  ✓ AMF has NGAP connection from gNB
  ✓ UE registration accepted
  ✓ PDU session established

[4/4] Data Path Validation
  ✓ UE has TUN interface with IP
  ✓ UE can ping 8.8.8.8 via UPF tunnel
  ✓ UE can resolve DNS via UPF tunnel

===========================================
  ALL 18 TESTS PASSED
===========================================
```

### 9.2 Manual Verification

```bash
# Check UE registration
docker logs ue 2>&1 | grep -i "registration"

# Check PDU session
docker logs ue 2>&1 | grep -i "pdu\|tunnel\|uesimtun"

# Check UE IP address
docker exec ue ip addr show uesimtun0

# Ping through the 5G tunnel
docker exec ue ping -I uesimtun0 -c 3 8.8.8.8
```

### 9.3 6G Lab Verification

```bash
make test-6g
```


---

## 10. Web Interfaces

| Service | URL | Credentials | Purpose |
|---------|-----|-------------|---------|
| **Open5GS WebUI** | `http://<HOST>:9999` | `admin` / `1423` | Subscriber management |
| **Grafana** | `http://<HOST>:3000` | `admin` / `sp-labs-admin` | Monitoring dashboards |
| **Prometheus** | `http://<HOST>:9090` | — (no auth) | Metrics & targets |
| **Sionna Jupyter** | `http://<HOST>:8888` | Token from `docker logs sionna` | 6G PHY research |

> Replace `<HOST>` with your server's IP address or hostname.

### 10.1 Open5GS WebUI

The `gradiant/open5gs-webui:2.7.1` image runs a Next.js application connected
to MongoDB. The default admin account (`admin`/`1423`) is **auto-created on
first startup** because we set `NODE_ENV=development` in the container.

**To add a subscriber via WebUI:**
1. Navigate to `http://<HOST>:9999`
2. Log in with `admin` / `1423`
3. Click **Subscriber** → **+** (Add)
4. Fill in IMSI, K, OPc, APN, SST
5. Click **Save**

### 10.2 Grafana

1. Navigate to `http://<HOST>:3000`
2. Log in with `admin` / `sp-labs-admin`
3. Go to **Dashboards** → **SP-Labs** folder → **SP-Labs — 5G Core Overview**

The dashboard is auto-provisioned from
`monitoring/grafana/dashboards/5g-core-dashboard.json`.

---

## 11. Subscriber Management

### 11.1 Default Test Subscriber

| Field | Value |
|-------|-------|
| IMSI | `999700000000001` |
| Key (K) | `465B5CE8B199B49FAA5F0A2EE238A6BC` |
| OPc | `E8ED289DEBA952E4283B54E88E6183CA` |
| AMF | `8000` |
| SST | `1` (eMBB) |
| DNN/APN | `internet` |
| AMBR | 1 Gbps up / 1 Gbps down |

### 11.2 Register via Script (Recommended)

```bash
bash infrastructure/scripts/register-subscriber.sh
```

This inserts (or replaces) the subscriber directly into MongoDB. The script
reads IMSI/Key/OPc from `.env` variables.

### 11.3 Register via MongoDB CLI

```bash
docker exec mongodb mongosh --quiet --eval "
  db = db.getSiblingDB('open5gs');
  db.subscribers.insertOne({
    imsi: '999700000000002',
    security: {
      k: '465B5CE8B199B49FAA5F0A2EE238A6BC',
      opc: 'E8ED289DEBA952E4283B54E88E6183CA',
      amf: '8000', sqn: NumberLong(65536)
    },
    ambr: { downlink: { value: 1, unit: 3 }, uplink: { value: 1, unit: 3 } },
    schema_version: 1,
    slice: [{
      sst: 1, default_indicator: true,
      session: [{
        name: 'internet', type: 3,
        qos: { index: 9, arp: { priority_level: 8,
          pre_emption_capability: 1, pre_emption_vulnerability: 1 } },
        ambr: { downlink: { value: 1, unit: 3 },
                uplink: { value: 1, unit: 3 } },
        pcc_rule: []
      }]
    }]
  });
"
```

### 11.4 List / Delete Subscribers

```bash
# List all subscribers
docker exec mongodb mongosh --quiet --eval "
  db = db.getSiblingDB('open5gs');
  db.subscribers.find({}, {imsi: 1, _id: 0}).forEach(printjson);
"

# Delete a subscriber
docker exec mongodb mongosh --quiet --eval "
  db = db.getSiblingDB('open5gs');
  db.subscribers.deleteOne({ imsi: '999700000000001' });
"
```


---

## 12. Monitoring & Dashboards

### 12.1 Prometheus Targets

| Job | Target | Network | Monitors |
|-----|--------|---------|----------|
| `prometheus` | `localhost:9090` | — | Prometheus self-metrics |
| `node-exporter` | `node-exporter:9100` | mgmt | Host CPU, memory, disk, network |
| `open5gs-amf` | `10.33.33.12:9090` | SBI | AMF sessions, registrations |
| `open5gs-smf` | `10.33.33.13:9090` | SBI | SMF PDU sessions |
| `open5gs-upf` | `10.33.38.14:9090` | mgmt | UPF throughput (RX/TX bytes) |

**Verify targets are up:**
```bash
curl -s http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

### 12.2 Grafana Dashboard Panels

The **"SP-Labs — 5G Core Overview"** dashboard includes:

| Panel | Type | Metric |
|-------|------|--------|
| Active UE Registrations | Stat | `amf_session_total` |
| PDU Sessions | Stat | `smf_session_total` |
| UPF Throughput | Time series | `rate(upf_session_rx_bytes_total[1m])`, `rate(upf_session_tx_bytes_total[1m])` |
| Host CPU Usage | Time series | `100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` |
| Host Memory Usage | Gauge | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` |

### 12.3 Adding Custom Dashboards

Place JSON files in `monitoring/grafana/dashboards/` and restart Grafana.
Ensure the datasource UID in your JSON matches `"uid": "prometheus"`.

```bash
docker restart grafana
```

### 12.4 Inspecting Raw Metrics

```bash
# Check what metrics AMF exposes
docker exec prometheus wget -qO- http://10.33.33.12:9090/metrics | head -30

# Check what metrics UPF exposes
docker exec prometheus wget -qO- http://10.33.38.14:9090/metrics | head -30
```

---

## 13. Day-to-Day Operations

### 13.1 Starting / Stopping

```bash
make deploy-5g           # Start 5G lab
make deploy-monitoring   # Start monitoring
make deploy-6g           # Start 6G lab
make deploy-all          # Start everything

make stop-5g             # Stop 5G lab
make stop-monitoring     # Stop monitoring
make stop-6g             # Stop 6G lab
make stop-all            # Stop everything

make restart-5g          # Stop + start 5G lab
make destroy-all         # Stop everything + delete volumes (data loss!)
```

### 13.2 Viewing Logs

```bash
make logs-5g                              # All 5G containers
docker logs amf -f --tail=50              # Specific container
docker logs amf 2>&1 | grep -i "error"    # Search for errors
```

### 13.3 Checking Status

```bash
make status    # Shows all three labs
```

### 13.4 Restarting a Single NF

```bash
docker restart amf    # Restart just AMF
docker restart ue     # Restart UE (e.g., after re-registering subscriber)
```

### 13.5 Updating Configurations

After editing any config file under `5g-lab/open5gs/config/`:

```bash
docker restart <nf-name>    # Pick up the changed config
```


---

## 14. Configuration Deep-Dive

### 14.1 Open5GS Config Structure

Each Open5GS NF has a YAML config mounted at `/opt/open5gs/etc/open5gs/<nf>.yaml`:

```yaml
logger:
  file: /opt/open5gs/var/log/open5gs/<nf>.log   # MUST be scalar string
  level: info                                     # debug|info|warn|error

global:
  max:
    ue: 1024

<nf>:
  sbi:
    server:
      - dev: eth0
        port: 7777
    client:
      scp:
        - uri: http://scp:7777
```

### 14.2 AMF Config Highlights

```yaml
amf:
  ngap:
    server:
      - dev: eth1              # N2 interface (10.33.34.12)
  metrics:
    server:
      - dev: eth0              # Prometheus metrics on SBI
        port: 9090
  guami:
    - plmn_id: { mcc: 999, mnc: 70 }
      amf_id: { region: 2, set: 1 }
  tai:
    - plmn_id: { mcc: 999, mnc: 70 }
      tac: 1
  plmn_support:
    - plmn_id: { mcc: 999, mnc: 70 }
      s_nssai:
        - sst: 1               # eMBB slice
  security:
    integrity_order: [NIA2, NIA1, NIA0]
    ciphering_order: [NEA0, NEA1, NEA2]
  network_name:
    full: SP-Labs 5G
```

### 14.3 SMF Config Highlights

```yaml
smf:
  pfcp:
    server:
      - dev: eth1              # N4 interface (10.33.36.13)
    client:
      upf:
        - address: 10.33.36.14 # UPF N4 address
  gtpc:
    server:
      - address: 10.33.33.13   # Must use 'address:', NOT 'dev:'
  gtpu:
    server:
      - address: 10.33.33.13   # Must use 'address:', NOT 'dev:'
  session:
    - subnet: 10.45.0.1/16     # gateway/prefix format
      dnn: internet
  dns:
    - 8.8.8.8
    - 8.8.4.4
  mtu: 1400
```

### 14.4 UPF Config Highlights

```yaml
upf:
  pfcp:
    server:
      - dev: eth1              # N4 interface (10.33.36.14)
  gtpu:
    server:
      - dev: eth0              # N3 interface (10.33.35.14)
  metrics:
    server:
      - address: 10.33.38.14   # Mgmt interface for Prometheus
        port: 9090
  session:
    - subnet: 10.45.0.1/16     # Must match SMF session config
```

> **Critical — ethN order:** Docker assigns interfaces in the order networks
> appear in the service's `networks:` block. For UPF: n3→eth0, n4→eth1,
> n6→eth2, mgmt→eth3.

### 14.5 UDR / PCF — MongoDB Connection

```yaml
db_uri: mongodb://mongodb:27017/open5gs   # Top-level, outside NF section
```

The `openverso/open5gs` entrypoint also reads `DB_URI` env var and overrides
the YAML value. Set both for reliability.

### 14.6 UERANSIM Environment Variables

**gNB:**

| Variable | Value | Purpose |
|----------|-------|---------|
| `MCC` | `999` | PLMN MCC |
| `MNC` | `70` | PLMN MNC |
| `TAC` | `1` | Tracking Area Code |
| `SST` | `1` | Slice Service Type |
| `SD` | `0xFFFFFF` | Slice Differentiator |
| `AMF_IP` | `10.33.34.12` | AMF N2 address |
| `N2_IFACE` | `eth0` | NGAP interface |
| `N3_IFACE` | `eth1` | GTP-U interface |

**UE:**

| Variable | Value | Purpose |
|----------|-------|---------|
| `KEY` | `465B5CE8...` | Auth key (K) |
| `OP` | `E8ED289D...` | OPc value |
| `OP_TYPE` | `OPC` | Operator variant |
| `APN` | `internet` | DNN |
| `GNB_IP` | `10.33.38.100` | gNB radio-link address |

### 14.7 FreeDiameter — Not Used

FreeDiameter is for 4G/Diameter interop. In Docker, it crashes SMF due to
hostname DNS resolution failure during certificate generation. The SMF config
in this lab intentionally **omits** `freeDiameter:`.


---

## 15. Networking Reference

### 15.1 Docker Networks

| Network | Subnet | Interface | Purpose |
|---------|--------|-----------|---------|
| `sp-labs-sbi` | `10.33.33.0/24` | SBI | Inter-NF HTTP/2 service mesh |
| `sp-labs-n2` | `10.33.34.0/24` | N2 | gNB ↔ AMF (NGAP/SCTP) |
| `sp-labs-n3` | `10.33.35.0/24` | N3 | gNB ↔ UPF (GTP-U user data) |
| `sp-labs-n4` | `10.33.36.0/24` | N4 | SMF ↔ UPF (PFCP session mgmt) |
| `sp-labs-n6` | `10.33.37.0/24` | N6 | UPF → Internet |
| `sp-labs-mgmt` | `10.33.38.0/24` | — | Management, monitoring |

### 15.2 Container IP Assignments

| Container | SBI (.33) | N2 (.34) | N3 (.35) | N4 (.36) | N6 (.37) | Mgmt (.38) |
|-----------|-----------|----------|----------|----------|----------|------------|
| mongodb | .2 | — | — | — | — | — |
| nrf | .10 | — | — | — | — | .10 |
| scp | .11 | — | — | — | — | — |
| amf | .12 | .12 | — | — | — | .12 |
| smf | .13 | — | — | .13 | — | .13 |
| upf | — | — | .14 | .14 | .14 | .14 |
| ausf | .15 | — | — | — | — | — |
| udm | .16 | — | — | — | — | — |
| udr | .17 | — | — | — | — | — |
| pcf | .18 | — | — | — | — | — |
| nssf | .19 | — | — | — | — | — |
| bsf | .20 | — | — | — | — | — |
| webui | .21 | — | — | — | — | .21 |
| gnb | — | .100 | .100 | — | — | .100 |
| ue | — | — | — | — | — | .101 |
| prometheus | .200 | — | — | — | — | .200 |
| grafana | — | — | — | — | — | .201 |
| node-exporter | — | — | — | — | — | .202 |

### 15.3 Docker ethN Interface Mapping

Docker assigns `ethN` in the order of `networks:` declaration per service:

| Container | eth0 | eth1 | eth2 | eth3 |
|-----------|------|------|------|------|
| **amf** | sbi (33.12) | n2 (34.12) | mgmt (38.12) | — |
| **smf** | sbi (33.13) | n4 (36.13) | mgmt (38.13) | — |
| **upf** | n3 (35.14) | n4 (36.14) | n6 (37.14) | mgmt (38.14) |
| **gnb** | n2 (34.100) | n3 (35.100) | mgmt (38.100) | — |

### 15.4 UE IP Pool

| Parameter | Value |
|-----------|-------|
| Subnet | `10.45.0.0/16` |
| Gateway | `10.45.0.1` |
| First UE IP | `10.45.0.2` |
| DNS Servers | `8.8.8.8`, `8.8.4.4` |

### 15.5 Host Port Mappings

| Port | Protocol | Service |
|------|----------|---------|
| 9999 | TCP | Open5GS WebUI |
| 38412 | SCTP | AMF NGAP |
| 9090 | TCP | Prometheus |
| 3000 | TCP | Grafana |
| 9100 | TCP | Node Exporter |
| 8888 | TCP | Sionna Jupyter |
| 3800 | TCP | O-RAN RIC E2 Mgr |

### 15.6 NAT / IP Forwarding

The bootstrap script configures host-level NAT for UE internet access:

```bash
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
iptables -A FORWARD -i ogstun -j ACCEPT
iptables -A FORWARD -o ogstun -m state --state RELATED,ESTABLISHED -j ACCEPT
```

If UE can't ping 8.8.8.8, re-run the above commands with `sudo`.


---

## 16. Troubleshooting

### 16.1 Container Won't Start / Crash Loop

```bash
docker inspect <container> --format='{{.State.ExitCode}}'
docker logs <container> --tail=50
```

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ogs_yaml_iter_value` assertion | `logger.file` is a mapping | Use scalar: `file: /path/to/log` |
| `could not resolve hostname` | FreeDiameter in SMF | Remove `freeDiameter:` section |
| `Connection refused mongodb` | MongoDB not ready | Ensure `depends_on` and `restart: unless-stopped` |
| UPF: `Could not create TUN device` | Missing TUN module | `sudo modprobe tun` |
| `open file limit` warnings | Low ulimits | Add `ulimits: nofile: soft: 65536` |

### 16.2 UE Registration Fails

```bash
docker logs gnb 2>&1 | grep -i "ng setup\|connect"
docker logs ue 2>&1 | grep -i "registration\|reject"
```

| Symptom | Cause | Fix |
|---------|-------|-----|
| `NGAP connection failed` | gNB can't reach AMF on N2 | Check `AMF_IP=10.33.34.12` |
| `5GMM_CAUSE_ILLEGAL_UE` | Subscriber not registered | Run `register-subscriber.sh` |
| `Authentication failure` | Key/OPc mismatch | Verify K/OPc in `.env` |
| No PDU session | SMF-UPF PFCP failure | Check SMF↔UPF N4 connectivity |

### 16.3 No Internet from UE

```bash
docker exec ue ip addr show uesimtun0       # Verify tunnel IP
sysctl net.ipv4.ip_forward                   # Must be 1
sudo iptables -t nat -L POSTROUTING -n       # Check NAT rules
docker exec ue ping -I uesimtun0 -c 2 8.8.8.8
```

### 16.4 WebUI Login Fails

| Symptom | Cause | Fix |
|---------|-------|-----|
| `admin`/`1423` rejected | Production mode | Set `NODE_ENV=development` |
| Connection refused :9999 | Container not running | Check `docker logs webui` |

### 16.5 Grafana Dashboard Empty

| Symptom | Cause | Fix |
|---------|-------|-----|
| "No data" on all panels | Datasource UID mismatch | Set `uid: prometheus` in datasources.yml |
| "No data" on 5G panels only | Prometheus can't reach NFs | Check `http://localhost:9090/targets` |
| Node panels work, 5G don't | Prometheus not on SBI network | Check monitoring compose networks |

### 16.6 Prometheus Targets Down

```bash
# Test from inside Prometheus container
docker exec prometheus wget -qO- http://10.33.33.12:9090/metrics | head -5
docker exec prometheus wget -qO- http://10.33.38.14:9090/metrics | head -5
docker exec prometheus ping -c 1 10.33.33.12
```

### 16.7 Network Debugging

```bash
docker network ls | grep sp-labs
docker network inspect sp-labs-sbi

# Capture traffic
docker exec amf tcpdump -i any -w /tmp/ngap.pcap port 38412
docker exec upf tcpdump -i any -w /tmp/gtp.pcap port 2152
docker cp amf:/tmp/ngap.pcap ./ngap.pcap
```

### 16.8 Full Reset

```bash
make destroy-all
docker network prune -f
docker volume prune -f
make deploy-5g
make deploy-monitoring
```


---

## 17. Lessons Learned & Gotchas

These are issues discovered during lab build-out, specific to the
`openverso/open5gs:2.7.0` and `openverso/ueransim:3.2.6` Docker images.

### 17.1 `logger.file` Must Be a Scalar

```yaml
# WRONG — causes ogs_yaml_iter_value assertion failure
logger:
  file:
    path: /opt/open5gs/var/log/open5gs/amf.log

# CORRECT
logger:
  file: /opt/open5gs/var/log/open5gs/amf.log
  level: info
```

### 17.2 FreeDiameter Crashes SMF in Docker

The `freeDiameter:` section triggers hostname resolution for certificate
generation. In Docker, the container hostname doesn't resolve, causing
immediate crash. **Solution:** Remove it — not needed for 5G SA.

### 17.3 Docker ethN Interface Order

Docker assigns `ethN` in the order networks appear in the service's
`networks:` block in `docker-compose.yml`. **Not alphabetical, not by subnet.**
Reordering `networks:` entries changes `ethN` and breaks `dev: ethN` configs.

### 17.4 SMF `gtpc`/`gtpu` Must Use `address:` Not `dev:`

```yaml
# WRONG — startup assertion failure
gtpc:
  server:
    - dev: eth0

# CORRECT
gtpc:
  server:
    - address: 10.33.33.13
```

### 17.5 Session Subnet Uses Gateway/Prefix Format

```yaml
# CORRECT — 10.45.0.1 is the gateway
session:
  - subnet: 10.45.0.1/16

# WRONG — network address, not gateway
session:
  - subnet: 10.45.0.0/16
```

### 17.6 `openverso` Entrypoint Overrides `db_uri`

The entrypoint reads `DB_URI` env var and writes it into the config. For NFs
needing MongoDB (UDR, PCF), set **both** YAML `db_uri:` and Docker `DB_URI=`.

### 17.7 WebUI Default Account Only in Dev Mode

The admin/1423 account is only auto-created when `NODE_ENV !== 'production'`.
Gradiant image defaults to production. **Fix:** `NODE_ENV=development`.

### 17.8 Grafana Datasource UID Must Match Dashboard JSON

Auto-generated UIDs won't match `"uid": "prometheus"` in dashboard JSON.
**Fix:** Explicitly set `uid: prometheus` in `datasources.yml`.

### 17.9 SCP Requires `global` Section

Without `global:`, SCP fails to parse the config:
```yaml
global:
  max:
    ue: 1024
```

### 17.10 UERANSIM Command Is `gnb`/`ue`, Not `nr-gnb`/`nr-ue`

The entrypoint maps `gnb` → `nr-gnb` after env setup and `envsubst`:
```yaml
command: gnb   # CORRECT
command: nr-gnb   # WRONG
```


---

## Appendix A — Make Targets

| Target | Description |
|--------|-------------|
| `make help` | Show all available targets |
| `make init` | Create `.env` from `.env.example` |
| `make preflight` | Run pre-flight validation |
| `make setup-ssh` | Set up SSH keys (multi-VM) |
| `make deploy-5g` | Deploy 5G lab + register subscriber |
| `make stop-5g` | Stop 5G lab |
| `make restart-5g` | Stop + start 5G lab |
| `make logs-5g` | Tail 5G lab logs |
| `make test-5g` | Run 5G E2E validation |
| `make deploy-6g` | Deploy 6G lab (auto-detects GPU) |
| `make stop-6g` | Stop 6G lab |
| `make logs-6g` | Tail 6G lab logs |
| `make test-6g` | Run 6G environment validation |
| `make deploy-monitoring` | Deploy Prometheus + Grafana |
| `make stop-monitoring` | Stop monitoring |
| `make deploy-all` | Deploy monitoring + 5G + 6G |
| `make stop-all` | Stop everything |
| `make destroy-all` | Stop everything + delete volumes |
| `make status` | Show status of all containers |

---

## Appendix B — Container Reference

### B.1 Docker Images

| Image | Tag | Source |
|-------|-----|--------|
| `openverso/open5gs` | `2.7.0` | Gradiant Open5GS (all 11 NFs) |
| `gradiant/open5gs-webui` | `2.7.1` | WebUI (Node.js) |
| `openverso/ueransim` | `3.2.6` | Gradiant UERANSIM (gNB + UE) |
| `mongo` | `6.0` | MongoDB |
| `prom/prometheus` | `v2.55.0` | Prometheus |
| `grafana/grafana` | `11.3.0` | Grafana |
| `prom/node-exporter` | `v1.8.2` | Node Exporter |

### B.2 Container Capabilities

| Container | `privileged` | `cap_add` | `devices` | Why |
|-----------|-------------|-----------|-----------|-----|
| `upf` | ✅ | `NET_ADMIN` | `/dev/net/tun` | Creates ogstun TUN, routes traffic |
| `gnb` | — | `NET_ADMIN` | — | Network interface management |
| `ue` | — | `NET_ADMIN` | `/dev/net/tun` | Creates uesimtun0 TUN device |

### B.3 Persistent Volumes

| Volume | Mount | Purpose |
|--------|-------|---------|
| `sp-labs-mongodb-data` | `/data/db` | Subscriber database |
| `sp-labs-prometheus-data` | `/prometheus` | 30-day metrics retention |
| `sp-labs-grafana-data` | `/var/lib/grafana` | Grafana state |

---

## Appendix C — Config File Reference

| File | NF | Key Settings |
|------|----|----|
| `open5gs/config/nrf.yaml` | NRF | PLMN serving list, SBI bind |
| `open5gs/config/scp.yaml` | SCP | SBI bind, NRF client URI |
| `open5gs/config/amf.yaml` | AMF | NGAP bind, GUAMI, TAI, PLMN, security, metrics |
| `open5gs/config/smf.yaml` | SMF | PFCP client→UPF, session subnet, DNS, metrics |
| `open5gs/config/upf.yaml` | UPF | PFCP bind, GTP-U bind, session subnet, metrics |
| `open5gs/config/udr.yaml` | UDR | `db_uri` for MongoDB |
| `open5gs/config/pcf.yaml` | PCF | `db_uri` for MongoDB, metrics |
| `open5gs/config/ausf.yaml` | AUSF | SBI bind |
| `open5gs/config/udm.yaml` | UDM | SBI bind |
| `open5gs/config/bsf.yaml` | BSF | SBI bind |
| `open5gs/config/nssf.yaml` | NSSF | SBI bind, NSI→NRF, S-NSSAI |
| `ueransim/config/gnb.yaml` | gNB | PLMN, TAC, AMF address, slices |
| `ueransim/config/ue.yaml` | UE | SUPI, auth keys, gNB search, sessions |
| `prometheus/prometheus.yml` | Prometheus | Scrape targets |
| `grafana/.../datasources.yml` | Grafana | Prometheus datasource (uid: prometheus) |
| `grafana/.../dashboards.yml` | Grafana | Dashboard file provider |
| `grafana/dashboards/5g-core-dashboard.json` | Grafana | 5G Core Overview dashboard |

---

> **Questions?** Open an issue in the repo or reach out to the SP Labs team.
>
> **Contributing:** Follow existing config patterns. Run `make test-5g`
> before pushing changes to ensure nothing is broken.

