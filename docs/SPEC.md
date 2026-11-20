# SP-Labs Specification Document

| Field | Value |
|-------|-------|
| **Version** | 1.0 |
| **Date** | 2026-11-20 |
| **Status** | Active |
| **Owner** | SP Labs Team |

---

## 1. Purpose

This document is the authoritative specification for the SP-Labs telco lab
environment. It defines all infrastructure requirements, software components,
network addressing, and deployment procedures needed to build fully functional
5G and 6G lab environments from scratch.

Teams clone this repository to an Ubuntu jump host and execute the automated
bootstrap to provision the entire environment.

## 2. Scope

### In Scope (Phase 1)

| Area | Components |
|------|-----------|
| 5G SA Core | Open5GS — AMF, SMF, UPF, NRF, AUSF, UDM, UDR, PCF, NSSF, BSF, SCP |
| 5G RAN/UE | UERANSIM — gNodeB simulator + multi-UE simulator |
| 6G Research | NVIDIA Sionna (PHY/AI-ML), ns-3 (network sim), O-RAN Near-RT RIC |
| Monitoring | Prometheus, Grafana, Node Exporter |
| Automation | Docker Compose, Ansible, shell bootstrap scripts |

### Out of Scope (Future Phases)

- F5 BIG-IP VE / BIG-IP Next CNF (Phase 4)
- Kubernetes / K3s cloud-native deployment (Phase 5)
- CI/CD pipeline (Phase 6)
- Physical SDR hardware (USRP, BladeRF)
- 4G / LTE EPC components

## 3. Infrastructure Requirements

### 3.1 Deployment Models

| Model | Description | VMs | Use Case |
|-------|-------------|-----|----------|
| **Single-Host** | All components on one Ubuntu VM via Docker | 1 | Quick start, demos |
| **Multi-VM** | Dedicated VMs per function via Ansible/Vagrant | 6–10 | Realistic testing |

### 3.2 Single-Host Requirements (Recommended Starting Point)

| Resource | 5G Only | 5G + 6G | 5G + 6G + Monitoring |
|----------|---------|---------|----------------------|
| **OS** | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |
| **vCPUs** | 8 | 12 | 16 |
| **RAM** | 16 GB | 32 GB | 32 GB |
| **Disk** | 80 GB SSD | 120 GB SSD | 150 GB SSD |
| **GPU** | — | NVIDIA (8 GB+ VRAM) | NVIDIA (8 GB+ VRAM) |

### 3.3 Multi-VM Requirements

| VM | Role | vCPUs | RAM | Disk | GPU |
|----|------|-------|-----|------|-----|
| vm-5g-core | Open5GS 5G Core NFs + MongoDB | 4 | 8 GB | 50 GB | — |
| vm-ran-sim | UERANSIM gNB + UEs | 2 | 4 GB | 30 GB | — |
| vm-upf | Dedicated UPF (high-throughput) | 4 | 8 GB | 40 GB | — |
| vm-sionna | NVIDIA Sionna 6G PHY simulator | 8 | 32 GB | 100 GB | ✅ |
| vm-ns3 | ns-3 network simulator | 4 | 16 GB | 50 GB | — |
| vm-oran | O-RAN Near-RT RIC | 4 | 8 GB | 40 GB | — |
| vm-monitor | Prometheus + Grafana | 2 | 4 GB | 100 GB | — |

**Totals: 28 vCPUs | 80 GB RAM | 410 GB Disk | 1× NVIDIA GPU**

---

## 4. Software Versions

| Component | Version | Image / Source |
|-----------|---------|----------------|
| Open5GS | v2.7.2 | `openverso/open5gs:2.7.2` |
| MongoDB | 6.0 | `mongo:6.0` |
| UERANSIM | v3.2.6 | `openverso/ueransim:3.2.6` |
| NVIDIA Sionna | 0.19.1 | Custom Dockerfile (TensorFlow + Sionna) |
| ns-3 | 3.42 | Custom Dockerfile |
| O-RAN Near-RT RIC | latest | O-RAN SC containers |
| Prometheus | v2.55.0 | `prom/prometheus:v2.55.0` |
| Grafana | 11.3.0 | `grafana/grafana:11.3.0` |
| Node Exporter | v1.8.2 | `prom/node-exporter:v1.8.2` |
| Docker Engine | 24.0+ | Ubuntu apt repo |
| Docker Compose | v2.x | Bundled with Docker |

## 5. 5G Network Architecture

### 5.1 Network Functions

| NF | 3GPP Role | Protocol | Port |
|----|-----------|----------|------|
| AMF | Access & Mobility Management | NGAP (N2), HTTP/2 (SBI) | 38412, 7777 |
| SMF | Session Management | PFCP (N4), HTTP/2 (SBI) | 8805, 7777 |
| UPF | User Plane Function | GTP-U (N3), PFCP (N4) | 2152, 8805 |
| NRF | NF Repository | HTTP/2 (SBI) | 7777 |
| AUSF | Authentication Server | HTTP/2 (SBI) | 7777 |
| UDM | Unified Data Management | HTTP/2 (SBI) | 7777 |
| UDR | Unified Data Repository | HTTP/2 (SBI) | 7777 |
| PCF | Policy Control | HTTP/2 (SBI) | 7777 |
| NSSF | Network Slice Selection | HTTP/2 (SBI) | 7777 |
| BSF | Binding Support | HTTP/2 (SBI) | 7777 |
| SCP | Service Communication Proxy | HTTP/2 (SBI) | 7777 |

### 5.2 PLMN & Subscriber Defaults

| Parameter | Value |
|-----------|-------|
| MCC | 999 |
| MNC | 70 |
| TAC | 1 |
| SST (Slice Type) | 1 (eMBB) |
| SD (Slice Differentiator) | 0x000001 |
| DNN / APN | internet |
| UE IP Pool | 10.45.0.0/16 |
| Test IMSI | 999700000000001 |
| Auth Key (K) | 465B5CE8B199B49FAA5F0A2EE238A6BC |
| Auth OPc | E8ED289DEBA952E4283B54E88E6183CA |

## 6. 6G Research Components

### 6.1 NVIDIA Sionna
- **Purpose:** GPU-accelerated link-level simulation for 6G PHY research
- **Capabilities:** MIMO, OFDM, LDPC/Polar codes, ray tracing, AI/ML channel est.
- **Requires:** NVIDIA GPU with CUDA 12.0+, NVIDIA Container Toolkit
- **Access:** Jupyter notebook on port 8888

### 6.2 ns-3 Network Simulator
- **Purpose:** Network-level simulation with NR (5G) module, extensible for 6G
- **Capabilities:** THz channel models, RIS, network slicing, mmWave
- **Access:** CLI-based simulation; results exported as pcap/CSV

### 6.3 O-RAN Near-RT RIC
- **Purpose:** RAN Intelligent Controller for AI/ML-driven RAN management
- **Capabilities:** xApps, E2 interface, A1 policy, 6G-relevant AI/ML inference
- **Access:** Dashboard on port 32080

## 7. Monitoring

| Component | Purpose | Port |
|-----------|---------|------|
| Prometheus | Metrics collection & storage | 9090 |
| Grafana | Dashboards & visualization | 3000 |
| Node Exporter | Host-level metrics | 9100 |

## 8. Security Considerations

| Area | Approach |
|------|----------|
| Credentials | Stored in `.env` (git-ignored); `.env.example` has defaults |
| Network isolation | Each 5G interface on its own Docker bridge network |
| Container privileges | UPF runs with `NET_ADMIN` capability for TUN interface |
| Exposure | Lab traffic on internal Docker networks; only mgmt ports exposed |
| Future | TLS on SBI interfaces, certificate management (Phase 4+) |

## 9. Acceptance Criteria

The lab is considered successfully deployed when:

1. All Docker containers are running and healthy
2. UERANSIM UE successfully registers with Open5GS AMF
3. PDU session is established (UE receives IP from 10.45.0.0/16 pool)
4. UE can ping external addresses through the UPF
5. Grafana dashboards show live metrics
6. Sionna Jupyter notebook is accessible (6G lab)
7. ns-3 container can execute a sample NR simulation (6G lab)

