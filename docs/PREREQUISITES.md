# SP-Labs Prerequisites & Preparation Guide

> **Read this document before running anything.**
> It tells you exactly what information to gather, what to provision,
> and how to configure the jump host so it can reach your lab VMs.

---

## Table of Contents

1. [Deployment Models](#1-deployment-models)
2. [Single-Host Deployment (Quick Start)](#2-single-host-deployment)
3. [Multi-VM Deployment (Production-Like)](#3-multi-vm-deployment)
4. [Information You Need to Gather](#4-information-you-need-to-gather)
5. [Jump Host Setup](#5-jump-host-setup)
6. [SSH Key Setup](#6-ssh-key-setup)
7. [Secrets Management](#7-secrets-management)
8. [Inventory Configuration](#8-inventory-configuration)
9. [Pre-Flight Validation](#9-pre-flight-validation)
10. [Deployment Workflow Summary](#10-deployment-workflow-summary)

---

## 1. Deployment Models

SP-Labs supports two deployment models. Choose based on your use case:

| Model | Jump Host Runs… | Target VMs | Best For |
|-------|-----------------|------------|----------|
| **Single-Host** | Docker Compose directly on the jump host | None (all-in-one) | Quick demos, single developer |
| **Multi-VM** | Ansible from the jump host to provision remote VMs | 6–7 VMs | Realistic testing, team labs |

### Decision Tree

```
Do you have multiple VMs/bare-metal servers?
├── NO  → Single-Host deployment (Section 2)
│         Only the jump host matters. Run bootstrap.sh + make deploy-*.
│
└── YES → Multi-VM deployment (Section 3)
          You need: VM IPs, SSH keys, and credentials.
          The jump host becomes the Ansible control node.
```

---

## 2. Single-Host Deployment

**You do NOT need VM IPs or SSH keys.** Everything runs locally via Docker.

### What You Need

| Item | Requirement |
|------|-------------|
| **OS** | Ubuntu 22.04 LTS or 24.04 LTS |
| **Hardware** | See table below |
| **Network** | Internet access (to pull Docker images) |
| **Permissions** | `sudo` access |

### Hardware Requirements

| Deployment | vCPUs | RAM | Disk | GPU |
|------------|-------|-----|------|-----|
| 5G Lab only | 8 | 16 GB | 80 GB SSD | — |
| 5G + Monitoring | 8 | 16 GB | 100 GB SSD | — |
| 5G + 6G + Monitoring | 16 | 32 GB | 150 GB SSD | NVIDIA 8 GB+ VRAM |

### Steps

```bash
git clone https://github.com/<your-org>/sp-labs.git && cd sp-labs
sudo ./infrastructure/scripts/bootstrap.sh --full
make deploy-5g           # or make deploy-all
make test-5g
```

**That's it.** No inventory, no SSH keys, no Ansible needed.

---

## 3. Multi-VM Deployment

**You DO need VM IPs, SSH access, and credentials.**
The jump host uses Ansible to SSH into each VM and provision it.

### Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                        JUMP HOST (Control Node)                      │
│   sp-labs repo   →   Ansible   →   SSH   →   Target VMs             │
└──────────────────────────────────────────────────────────────────────┘
        │  SSH (port 22)
        ▼
   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
   │ vm-5g-core  │  │ vm-ran-sim  │  │ vm-sionna   │
   │ 192.168.1.10│  │ 192.168.1.20│  │ 192.168.1.40│
   └─────────────┘  └─────────────┘  └─────────────┘
   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
   │ vm-ns3      │  │ vm-oran     │  │ vm-monitor  │
   │ 192.168.1.50│  │ 192.168.1.60│  │ 192.168.1.70│
   └─────────────┘  └─────────────┘  └─────────────┘
```

### VM Requirements

| VM Name | Role | vCPUs | RAM | Disk | GPU | Required |
|---------|------|-------|-----|------|-----|----------|
| `vm-5g-core` | Open5GS 5G Core + MongoDB | 4 | 8 GB | 50 GB | — | ✅ Yes |
| `vm-ran-sim` | UERANSIM gNB + UEs | 2 | 4 GB | 30 GB | — | ✅ Yes |
| `vm-sionna` | NVIDIA Sionna 6G PHY | 8 | 32 GB | 100 GB | ✅ | Optional |
| `vm-ns3` | ns-3 network simulator | 4 | 16 GB | 50 GB | — | Optional |
| `vm-oran` | O-RAN Near-RT RIC | 4 | 8 GB | 40 GB | — | Optional |
| `vm-monitor` | Prometheus + Grafana | 2 | 4 GB | 100 GB | — | Recommended |

**VM OS:** Ubuntu 22.04 LTS (all VMs, including the jump host)

---

## 4. Information You Need to Gather

Before configuring multi-VM deployment, collect this from your infra team:

### 4.1 Per-VM Information

| Field | vm-5g-core | vm-ran-sim | vm-sionna | vm-ns3 | vm-oran | vm-monitor |
|-------|-----------|-----------|----------|-------|--------|-----------|
| **IP Address** | ___.___.___.__ | ___.___.___.__ | ___.___.___.__ | ___.___.___.__ | ___.___.___.__ | ___.___.___.__ |
| **SSH Port** | 22 | 22 | 22 | 22 | 22 | 22 |
| **SSH Username** | ubuntu | ubuntu | ubuntu | ubuntu | ubuntu | ubuntu |
| **Auth Method** | key / password | key / password | key / password | key / password | key / password | key / password |
| **sudo access** | yes / no | yes / no | yes / no | yes / no | yes / no | yes / no |

### 4.2 Network Information

| Field | Value | Notes |
|-------|-------|-------|
| **Jump host IP** | ___.___.___.__ | The machine where you clone sp-labs |
| **VM subnet** | ___.___.___.0/24 | Subnet where VMs live |
| **Gateway** | ___.___.___.__ | Default gateway for the VM subnet |
| **DNS servers** | ___.___.___.__ | For VMs to resolve package repos |
| **Internet access** | Direct / Proxy / Air-gapped | VMs need internet for Docker pulls |
| **HTTP proxy** (if any) | http://proxy:port | Set in `.env` for Docker |

### 4.3 Credentials & Secrets

| Secret | Where It Goes | Default |
|--------|---------------|---------|
| SSH private key path | `ansible.cfg` / inventory | `~/.ssh/sp-labs-key` |
| SSH key passphrase | `ssh-agent` (do NOT put in files) | — |
| Grafana admin password | `.env` → `GRAFANA_ADMIN_PASSWORD` | `sp-labs-admin` |
| MongoDB (no auth in lab) | — | No password by default |
| O-RAN SC registry creds | Docker login (if using O-RAN images) | — |
| Subscriber key (K) | `.env` → `SUBSCRIBER_KEY` | `465B5CE8...` |
| Subscriber OPc | `.env` → `SUBSCRIBER_OPC` | `E8ED289D...` |

---

## 5. Jump Host Setup

The jump host is where you clone `sp-labs` and run Ansible from.

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ansible sshpass python3-pip git make jq
ansible --version    # Should show 2.14+
git clone https://github.com/<your-org>/sp-labs.git && cd sp-labs
cp .env.example .env && nano .env   # Set VM IPs + credentials
```

**Key `.env` variables for multi-VM** (see `.env.example` for full list):

```bash
VM_5G_CORE_IP=192.168.1.10
VM_RAN_SIM_IP=192.168.1.20
VM_SIONNA_IP=192.168.1.40
VM_NS3_IP=192.168.1.50
VM_ORAN_IP=192.168.1.60
VM_MONITOR_IP=192.168.1.70
ANSIBLE_USER=ubuntu
ANSIBLE_SSH_KEY=~/.ssh/sp-labs-key
```

---

## 6. SSH Key Setup

Ansible needs password-less SSH access to every target VM.

**Option A — Automated (recommended):**

```bash
chmod +x infrastructure/scripts/setup-ssh-keys.sh
./infrastructure/scripts/setup-ssh-keys.sh
```

**Option B — Manual:**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/sp-labs-key -C "sp-labs-ansible" -N ""
ssh-copy-id -i ~/.ssh/sp-labs-key ubuntu@192.168.1.10   # repeat per VM
ssh -i ~/.ssh/sp-labs-key ubuntu@192.168.1.10 "hostname" # verify
```

**Option C — Existing key:** Point `ANSIBLE_SSH_KEY=~/.ssh/id_rsa` in `.env`.

**Option D — Vagrant:** SSH keys are auto-managed by `vagrant up`.

---

## 7. Secrets Management

**Lab (default):** Secrets go in `.env` (git-ignored).

**Production-like (Ansible Vault):**

```bash
echo "your-vault-password" > infrastructure/ansible/.vault-pass
chmod 600 infrastructure/ansible/.vault-pass
ansible-vault create infrastructure/ansible/group_vars/vault.yml \
  --vault-password-file infrastructure/ansible/.vault-pass
```

| Item | Location | In Git? |
|------|----------|---------|
| `.env` | Repo root | ❌ gitignored |
| `.vault-pass` | `ansible/` | ❌ gitignored |
| SSH private keys | `~/.ssh/` | ❌ Never |
| `vault.yml` | `ansible/group_vars/` | ✅ Encrypted |

---

## 8. Inventory Configuration

**Single-Host:** Default inventory uses `localhost` — no changes needed.

**Multi-VM:** Edit `infrastructure/ansible/inventory.ini` — uncomment the
multi-VM sections, set actual IPs, and update group children. See inline
comments in the inventory file for guidance.

**Partial deployment:** Comment out VMs you don't have; Ansible skips them.

---

## 9. Pre-Flight Validation

**Always run before deploying:**

```bash
chmod +x infrastructure/scripts/preflight-check.sh
./infrastructure/scripts/preflight-check.sh
```

Validates: tools, SSH connectivity, sudo, OS version, resources, internet,
kernel modules, port conflicts, and GPU availability.

---

## 10. Deployment Workflow Summary

| Model | Steps |
|-------|-------|
| **Single-Host** | `bootstrap.sh --full` → `make deploy-5g` → `make test-5g` |
| **Multi-VM** | Provision VMs → fill `.env` + `inventory.ini` → `setup-ssh-keys.sh` → `preflight-check.sh` → `ansible-playbook site.yml` |
| **Vagrant** | `vagrant up` → `vagrant ssh vm-5g-core` → `make deploy-5g` |

---

## Checklist

- [ ] Jump host: Ubuntu 22.04+, `sudo`, `git`, `make`, `ansible`, `ssh`
- [ ] Repo cloned and `.env` created from `.env.example`
- [ ] **(Multi-VM)** VM IPs collected → `inventory.ini`
- [ ] **(Multi-VM)** SSH keys set up → `setup-ssh-keys.sh`
- [ ] **(Multi-VM)** Pre-flight passes → `preflight-check.sh`
- [ ] **(6G/Sionna)** NVIDIA GPU with drivers installed
- [ ] Internet access available for Docker image pulls

