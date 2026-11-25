# SP-Labs — Service Provider 5G & 6G Lab Environment

> **Single Source of Truth** for building automated 5G and 6G telco lab environments.
> Teams clone this repo to their jump host and run the bootstrap to stand up the full lab.

## Overview

| Lab | Components | Purpose |
|-----|-----------|---------|
| **5G Lab** | Open5GS (5G Core) + UERANSIM (RAN/UE Simulator) | End-to-end 5G SA network |
| **6G Lab** | NVIDIA Sionna, ns-3, O-RAN RIC | 6G research & AI/ML-driven RAN |
| **Monitoring** | Prometheus + Grafana | Observability for all lab components |

> **Note:** F5 BIG-IP / BIG-IP Next CNF integration points are reserved in the
> architecture and will be added in a future phase.

## Quick Start

### Prerequisites

- **Jump Host:** Ubuntu 22.04 LTS (or 24.04 LTS)
- **Docker:** 24.0+ with Docker Compose v2
- **Minimum Resources:** 8 vCPUs, 16 GB RAM, 100 GB disk (5G lab only)
- **For 6G Lab (Sionna):** NVIDIA GPU with CUDA 12.0+ drivers
- **For Multi-VM:** VM IPs, SSH keys, Ansible — see [PREREQUISITES.md](docs/PREREQUISITES.md)

> **📋 First time?** Read [docs/PREREQUISITES.md](docs/PREREQUISITES.md) for the full
> preparation guide — what to gather, SSH key setup, secrets management, and
> pre-flight validation.

### 1. Clone & Bootstrap

```bash
git clone https://github.com/<your-org>/sp-labs.git
cd sp-labs
chmod +x infrastructure/scripts/bootstrap.sh
sudo ./infrastructure/scripts/bootstrap.sh --full
```

### 2. Pre-Flight Check (Recommended)

```bash
./infrastructure/scripts/preflight-check.sh
```

### 3. Deploy

```bash
make deploy-5g          # 5G Lab only
make deploy-6g          # 6G Lab only
make deploy-monitoring  # Monitoring only
make deploy-all         # Everything
make status             # Check status
```

### 4. Verify

```bash
make test-5g    # UE registration + PDU session + ping
make test-6g    # 6G simulation environment check
```

## Lab Access

| Service | URL | Credentials |
|---------|-----|-------------|
| **Architecture Portal** | `http://<host>:8080` | — |
| Grafana | `http://<host>:3000` | admin / sp-labs-admin |
| Prometheus | `http://<host>:9090` | — |
| Open5GS WebUI | `http://<host>:9999` | admin / 1423 |

## Documentation

| Document | Description |
|----------|-------------|
| [LAB_GUIDE.md](docs/LAB_GUIDE.md) | **📘 Complete lab guide** — deploy, verify, operate, troubleshoot |
| [PREREQUISITES.md](docs/PREREQUISITES.md) | What to gather, SSH keys, secrets, pre-flight |
| [SPEC.md](docs/SPEC.md) | Full specification — VM requirements, versions, network plan |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Detailed architecture and data flows |
| [NETWORKING.md](docs/NETWORKING.md) | IP addressing, subnets, interface mapping |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and resolution steps |
| [Architecture Portal](docs/portal/index.html) | **🗺️ Interactive visual portal** — topology, flows, IPs, commands |

## Roadmap

- [x] Phase 1: 5G Core (Open5GS) + RAN Simulator (UERANSIM)
- [x] Phase 2: 6G Research (Sionna + ns-3 + O-RAN RIC)
- [x] Phase 3: Monitoring (Prometheus + Grafana)
- [ ] Phase 4: F5 BIG-IP VE / BIG-IP Next CNF integration
- [ ] Phase 5: Kubernetes (K3s/K8s) cloud-native deployment
- [ ] Phase 6: CI/CD pipeline for automated testing
