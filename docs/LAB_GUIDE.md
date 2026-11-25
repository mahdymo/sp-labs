# SP-Labs — Complete Lab Guide

> **Audience:** Engineers deploying, operating, and troubleshooting the SP-Labs
> 5G & 6G telco lab environment.
>
> **Last updated:** 2026-11-25 · **Spec version:** 1.4

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Architecture Overview](#2-architecture-overview)
3. [5G Fundamentals — A Beginner's Guide](#3-5g-fundamentals--a-beginners-guide)
4. [Prerequisites](#4-prerequisites)
5. [Repository Layout](#5-repository-layout)
6. [Environment Configuration](#6-environment-configuration)
7. [Deploying the 5G Lab](#7-deploying-the-5g-lab)
8. [Deploying the Monitoring Stack](#8-deploying-the-monitoring-stack)
9. [Deploying the 6G Lab](#9-deploying-the-6g-lab)
10. [End-to-End Verification](#10-end-to-end-verification)
11. [Web Interfaces](#11-web-interfaces)
12. [Subscriber Management](#12-subscriber-management)
13. [Monitoring & Dashboards](#13-monitoring--dashboards)
14. [Day-to-Day Operations](#14-day-to-day-operations)
15. [Configuration Deep-Dive](#15-configuration-deep-dive)
16. [Networking Reference](#16-networking-reference)
17. [Troubleshooting](#17-troubleshooting)
18. [Lessons Learned & Gotchas](#18-lessons-learned--gotchas)
19. [Connecting an External F5 BIG-IP](#19-connecting-an-external-f5-big-ip)
20. [Appendix A — Make Targets](#appendix-a--make-targets)
21. [Appendix B — Container Reference](#appendix-b--container-reference)
22. [Appendix C — Config File Reference](#appendix-c--config-file-reference)

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

## 3. 5G Fundamentals — A Beginner's Guide

> **Who is this for?** If you're new to service provider (SP) / telco
> networking and want to understand what every component in this lab does, how
> they connect, and why they exist — this section is for you. It maps every
> 3GPP concept to its real container and IP address in SP-Labs.

### 3.1 What Is a Service Provider Network?

A **Service Provider** (SP) — also called a **carrier** or **telco** — is a
company that sells connectivity: mobile voice/data (AT&T, Vodafone, NTT),
fixed broadband (Comcast, BT), or both. Their networks have a fundamentally
different architecture than enterprise IT networks:

| Concern | Enterprise IT | Service Provider |
|---------|--------------|-----------------|
| Scale | 100s–10,000s of users | Millions of subscribers |
| Identity | Active Directory / LDAP | SIM card (IMSI), cryptographic keys |
| Addressing | Private RFC 1918 IPs | Pooled private IPs → CGNAT → public IPs |
| Security model | Perimeter firewall | Per-subscriber authentication, encryption on air |
| Traffic engineering | QoS on LAN/WAN | Network slicing, GTP tunnels, bearer QoS |
| Regulation | Minimal | Lawful intercept, number portability, E911 |
| Revenue model | IT is a cost center | The network IS the product |

The 5G core network you deploy in this lab is the **brain** of the SP network.
Every phone call, text, and byte of data your phone sends is orchestrated by
components exactly like the ones running as Docker containers here.

### 3.2 The Evolution: 2G → 3G → 4G → 5G

Understanding the progression helps explain why 5G is designed the way it is:

```
2G (GSM, 1991)        Voice-centric, circuit-switched
  │                   • MSC, HLR, VLR — dedicated hardware boxes
  │                   • Data added later as GPRS (2.5G): 50-100 kbps
  ▼
3G (UMTS, 2001)       Faster data (up to 42 Mbps with HSPA+)
  │                   • Still mostly circuit-switched voice
  │                   • SGSN/GGSN for packet data
  ▼
4G (LTE, 2009)        All-IP, no more circuit-switching
  │                   • MME, HSS, SGW, PGW — dedicated per-function boxes
  │                   • Protocols: GTP (data tunnels), Diameter (signaling)
  │                   • VoLTE: voice finally goes IP
  ▼
5G (NR, 2019)         Cloud-native, service-based, sliceable
                      • Network Functions (NFs) replace boxes
                      • HTTP/2 replaces Diameter for signaling
                      • Control plane / User plane fully separated (CUPS)
                      • Network slicing: virtual networks within one physical network
```

**Key 5G design principles:**
1. **Service-Based Architecture (SBA)** — NFs talk over HTTP/2 APIs, like
   microservices. Any NF can discover and call any other via a registry (NRF).
2. **Control / User Plane Separation (CUPS)** — The brain (control plane:
   AMF, SMF) is separated from the muscle (user plane: UPF). They can scale
   independently.
3. **Stateless design** — State is stored in databases (UDR), not in the NFs
   themselves. NFs can be restarted without losing subscriber context.
4. **Cloud-native** — NFs are designed to run as containers or VMs, not on
   proprietary hardware. That's why we can run a full 5G core in Docker.

### 3.3 The Two Planes: Control vs. User

Every packet in a mobile network follows one of two paths:

```
┌─────────────────────────────────────────────────────────────────────┐
│                       CONTROL PLANE                                 │
│  "Who are you? Are you allowed? What session do you need?"          │
│                                                                     │
│  Protocols: HTTP/2 (SBI), NGAP (N2), PFCP (N4)                    │
│  NFs: AMF, SMF, NRF, SCP, AUSF, UDM, UDR, PCF, NSSF, BSF        │
│                                                                     │
│  Think: air traffic control — coordinates everything, touches       │
│         no actual passenger data                                    │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                        USER PLANE                                   │
│  "Here are your actual packets — YouTube, email, browsing"          │
│                                                                     │
│  Protocols: GTP-U (N3), IP (N6)                                    │
│  NFs: UPF (and gNB on the RAN side)                                │
│                                                                     │
│  Think: the highway — carries the actual cargo, doesn't make        │
│         decisions about who can drive                               │
└─────────────────────────────────────────────────────────────────────┘
```

In this lab, the control plane is the SBI network (`10.33.33.0/24`) and the
user plane is N3 (`10.33.35.0/24`) + N6 (`10.33.37.0/24`).

### 3.4 Every Network Function Explained

Here is every NF in the 5G core, what it does in plain English, its
real-world analogy, and exactly where it runs in this lab.

#### 3.4.1 NRF — NF Repository Function

```
Container: nrf                    IP: 10.33.33.10 (SBI)
Config:    open5gs/config/nrf.yaml
```

**What it does:** The NRF is the **phone book** of the 5G core. When an NF
starts up, it registers itself with the NRF: "I'm an AMF, I'm at this
address, I serve this PLMN." When another NF needs a service, it asks the
NRF: "Where can I find an AUSF?" The NRF replies with the address.

**Real-world analogy:** DNS + Consul/Eureka service registry. It's the same
pattern as microservice discovery in cloud-native apps.

**Why it matters:** Without NRF, no NF can find any other NF. If NRF is down,
the entire core is blind. That's why it starts first (after MongoDB).

#### 3.4.2 SCP — Service Communication Proxy

```
Container: scp                    IP: 10.33.33.11 (SBI)
Config:    open5gs/config/scp.yaml
```

**What it does:** The SCP is a **message bus / service mesh proxy**. Instead
of every NF talking directly to every other NF (N×N connections), all messages
go through SCP. The SCP looks up destinations in NRF and forwards the
request.

**Real-world analogy:** An API gateway or service mesh sidecar (like Envoy or
Istio). It decouples NFs from each other.

**Why it matters:** In this lab, all NFs (AMF, SMF, AUSF, etc.) point their
`scp:` client config at `http://10.33.33.11:7777`. The SCP then routes the
request to the right NF. This simplifies config: each NF only needs to know
one address (SCP), not the address of every other NF.

#### 3.4.3 AMF — Access and Mobility Management Function

```
Container: amf                    IPs: 10.33.33.12 (SBI), 10.33.34.12 (N2)
Config:    open5gs/config/amf.yaml
```

**What it does:** The AMF is the **front door** of the 5G core. It handles:
- **Registration** — When your phone powers on, it contacts the nearest
  cell tower (gNB), which connects to the AMF via the N2 interface. The AMF
  decides whether to accept the phone onto the network.
- **Authentication** — The AMF triggers the auth procedure by calling AUSF
  (via SCP → SBI). If the phone's SIM card has valid credentials, it's let in.
- **Mobility** — When you move between cell towers (handover), the AMF
  coordinates the transition.
- **NAS Security** — The AMF encrypts the control-plane signaling between
  phone and core (NAS = Non-Access Stratum).

**Real-world analogy:** The hotel front desk. You check in (register), show
your ID (authenticate), and if you move rooms (handover), the front desk
updates your location.

**Key config in this lab:**
- `guami` — Globally Unique AMF ID (identifies this AMF worldwide)
- `tai` — Tracking Area Identity (the geographic area this AMF covers)
- `plmn_support` — Which PLMN (operator code) and slices this AMF serves
- `s_nssai: sst: 1` — Supports eMBB (enhanced Mobile Broadband) slice

#### 3.4.4 SMF — Session Management Function

```
Container: smf                    IPs: 10.33.33.13 (SBI), 10.33.36.13 (N4)
Config:    open5gs/config/smf.yaml
```

**What it does:** The SMF manages **data sessions** (PDU sessions). When your
phone wants to access the internet:
1. The AMF forwards the session request to the SMF.
2. The SMF selects a UPF and creates a GTP tunnel by sending PFCP messages
   over the N4 interface.
3. The SMF assigns your phone an IP address from the pool (`10.45.0.0/16`).
4. The SMF applies QoS rules (bandwidth limits, priority) from the PCF.

**Real-world analogy:** The hotel's IT department. When you ask for Wi-Fi
(PDU session), they assign you an IP, set your bandwidth limit, and wire
the connection through the access point (UPF).

**Key config in this lab:**
- `pfcp.client.upf` — Points to UPF at `10.33.36.14` (N4 network)
- `session.subnet: 10.45.0.1/16` — The IP pool for UE devices
- `dns: 8.8.8.8` — DNS servers given to UEs

#### 3.4.5 UPF — User Plane Function

```
Container: upf                    IPs: 10.33.35.14 (N3), 10.33.36.14 (N4),
                                       10.33.37.14 (N6), 10.33.38.14 (mgmt)
Config:    open5gs/config/upf.yaml
```

**What it does:** The UPF is the **data highway**. It's the only NF that
touches actual user data (YouTube packets, web browsing, etc.). It:
1. Receives encrypted GTP-U tunneled data from the gNB on the **N3**
   interface.
2. Decapsulates the GTP tunnel (strips the outer headers).
3. Forwards the raw IP packets to the internet via the **N6** interface
   (through a TUN device called `ogstun`).
4. Does the reverse for downlink traffic (internet → UE).

**Real-world analogy:** A highway interchange. Cars (packets) come in
through one on-ramp (N3/GTP tunnel from the radio), get their toll tags
read (GTP decapsulation), and exit onto the interstate (N6/internet).

**Why it needs special privileges:** The UPF creates a Linux TUN device
(`ogstun`), manipulates routes, and forwards IP traffic. That's why the
container needs `privileged: true`, `NET_ADMIN` capability, and
`/dev/net/tun`.

**Key interfaces:**
- **N3** (`10.33.35.14`) — Receives user data from gNB via GTP-U tunnels
- **N4** (`10.33.36.14`) — Receives session rules from SMF via PFCP
- **N6** (`10.33.37.14`) — Sends/receives user traffic to/from internet
- **ogstun** (`10.45.0.1`) — The TUN device that acts as the gateway for
  all UE IP traffic

#### 3.4.6 AUSF — Authentication Server Function

```
Container: ausf                   IP: 10.33.33.15 (SBI)
```

**What it does:** The AUSF handles **5G-AKA authentication**. When a phone
registers, the AMF asks the AUSF to verify the subscriber's identity. The
AUSF fetches the subscriber's secret key (K) and OPc from UDM/UDR, runs the
5G-AKA algorithm, generates challenges, and verifies the phone's response.

**Real-world analogy:** The ID verification booth. You present your passport
(SIM card response), and the booth checks it against the database to confirm
you're really who you claim to be.

#### 3.4.7 UDM — Unified Data Management

```
Container: udm                    IP: 10.33.33.16 (SBI)
```

**What it does:** The UDM manages **subscriber profiles** and **access
authorization**. It decides whether a subscriber is allowed on this network,
what services they're entitled to, and what their subscription data is. The
UDM doesn't store data itself — it uses the UDR as its backend database.

**Real-world analogy:** The HR department. They manage employee records
(subscriber profiles) and authorize access, but the actual files are in the
filing cabinet (UDR). **4G equivalent:** HSS (Home Subscriber Server).

#### 3.4.8 UDR — Unified Data Repository

```
Container: udr                    IP: 10.33.33.17 (SBI)
Config:    open5gs/config/udr.yaml
```

**What it does:** The UDR is the **database backend**. It stores subscriber
data, policy data, and application data in MongoDB. The UDM and PCF both
read and write through the UDR.

**Key config:** `db_uri: mongodb://mongodb:27017/open5gs` — connects to the
MongoDB container where subscriber records live.

#### 3.4.9 PCF — Policy Control Function

```
Container: pcf                    IP: 10.33.33.18 (SBI)
Config:    open5gs/config/pcf.yaml
```

**What it does:** The PCF sets **rules** for how subscribers use the network:
bandwidth limits (AMBR), QoS flows, usage monitoring (data caps), and access
control. When the SMF creates a PDU session, it asks the PCF: "What policies
apply to this subscriber?"

**Real-world analogy:** The building's rules committee. "Gold members get
1 Gbps, Silver gets 100 Mbps, all users are capped at 50 GB/month."

#### 3.4.10 NSSF — Network Slice Selection Function

```
Container: nssf                   IP: 10.33.33.19 (SBI)
```

**What it does:** The NSSF helps the AMF select the right **network slice**
for a subscriber. A slice is identified by S-NSSAI:

| Slice Type (SST) | Name | Use Case |
|-------------------|------|----------|
| 1 | eMBB | Enhanced Mobile Broadband (video, browsing) |
| 2 | URLLC | Ultra-Reliable Low-Latency (autonomous cars, remote surgery) |
| 3 | MIoT | Massive IoT (sensors, smart meters) |

**In this lab:** SST=1 (eMBB) with SD=0xFFFFFF (no specific differentiator).

#### 3.4.11 BSF — Binding Support Function

```
Container: bsf                    IP: 10.33.33.20 (SBI)
```

**What it does:** The BSF keeps track of which PCF is managing policies for
which subscriber session. With a single PCF instance in this lab, the BSF is
not critically active but is deployed for architectural completeness.

### 3.5 The Radio Access Network (RAN)

The RAN is the **wireless** part of the network — everything between the phone
and the core.

#### 3.5.1 gNB — gNodeB (5G Base Station)

```
Container: gnb                    IPs: 10.33.34.100 (N2), 10.33.35.100 (N3),
                                       10.33.38.100 (mgmt/radio)
```

**What it does:** In the real world, the gNB is a **cell tower** — the
physical radio equipment that communicates with phones over the air. In this
lab, UERANSIM simulates a gNB in software.

The gNB has two key connections to the core:
- **N2** (to AMF) — Control plane: carries NGAP messages for registration,
  handover, paging, session setup. Protocol: SCTP, port 38412.
- **N3** (to UPF) — User plane: carries GTP-U tunneled user data. Protocol:
  UDP, port 2152.

**Real-world analogy:** A Wi-Fi access point, but cellular. It bridges the
air interface (radio) to the wired backhaul (core network).

#### 3.5.2 UE — User Equipment

```
Container: ue                     IP: 10.33.38.101 (mgmt)
                                  Tunnel: 10.45.0.x (uesimtun0, assigned by SMF)
```

**What it does:** The UE is your **phone** (or any 5G device). In this lab,
UERANSIM simulates a phone with a virtual SIM card. It registers with the
network, authenticates, establishes a PDU session, and creates a TUN device
(`uesimtun0`) that you can ping and curl through — just like real mobile data.

**Key identity fields in this lab:**

| Field | Value | Meaning |
|-------|-------|---------|
| IMSI | `999700000000001` | International Mobile Subscriber Identity — unique worldwide |
| SUPI | `imsi-999700000000001` | Subscription Permanent Identifier (5G term for IMSI) |
| MCC | `999` | Mobile Country Code (999 = test/private network) |
| MNC | `70` | Mobile Network Code (70 = test operator) |
| Key (K) | `465B5CE8...` | 128-bit secret key (also stored in SIM and UDR) |
| OPc | `E8ED289D...` | Operator variant key (derived from K + OP) |

### 3.6 The Database Layer

```
Container: mongodb                IP: 10.33.33.2 (SBI)
Volume:    sp-labs-mongodb-data → /data/db
```

MongoDB stores all persistent data: subscriber profiles (IMSI, keys, allowed
slices, APN/DNN, QoS), policy rules, and NRF registrations. In 4G, this role
was split between HSS (subscriber) and PCRF (policy). In 5G, everything goes
into a unified data store accessed through UDR.

### 3.7 The Interfaces — How Everything Connects

In 3GPP, every connection between components is a named **interface** with a
specific protocol. Here's how they map to Docker networks in this lab:

```
                                    SBI Network (10.33.33.0/24)
                              ┌──────────────────────────────────────┐
                              │  HTTP/2, port 7777                   │
                              │                                      │
                              │  NRF(.10) SCP(.11) AMF(.12)         │
                              │  SMF(.13) AUSF(.15) UDM(.16)        │
                              │  UDR(.17) PCF(.18) NSSF(.19)        │
                              │  BSF(.20) MongoDB(.2)               │
  ┌──────────┐                └───┬──────────────────────┬───────────┘
  │   gNB    │                    │                      │
  │          │   N2 Network       │                      │   N4 Network
  │  .34.100 ├────────────────────┤ AMF .34.12           │   (10.33.36.0/24)
  │          │  (10.33.34.0/24)   │ NGAP/SCTP:38412      │   PFCP/UDP:8805
  │          │                    │                      │
  │  .35.100 ├──────────┐        │                SMF .36.13
  └──────────┘          │        │                      │
              N3 Network│        │                UPF .36.14
         (10.33.35.0/24)│        │                      │
          GTP-U/UDP:2152│        │                      │
                        │        │                      │
                   UPF .35.14    │                      │
                        │        │                      │
                   UPF .37.14    │                      │
                        │   N6 Network                  │
                        │  (10.33.37.0/24)              │
                        └──► Internet                   │
                                                        │
                              Mgmt Network (10.33.38.0/24)
                              ┌──────────────────────────┐
                              │  Prometheus (.200)        │
                              │  Grafana (.201)           │
                              │  NRF(.10) AMF(.12)       │
                              │  SMF(.13) UPF(.14)       │
                              │  gNB(.100) UE(.101)      │
                              └──────────────────────────┘
```

| Interface | Docker Network | Subnet | Protocol | Port | Purpose |
|-----------|---------------|--------|----------|------|---------|
| **SBI** | `sp-labs-sbi` | `10.33.33.0/24` | HTTP/2 | 7777 | NF-to-NF signaling |
| **N2** | `sp-labs-n2` | `10.33.34.0/24` | NGAP/SCTP | 38412 | gNB ↔ AMF control plane |
| **N3** | `sp-labs-n3` | `10.33.35.0/24` | GTP-U/UDP | 2152 | gNB ↔ UPF user data tunnel |
| **N4** | `sp-labs-n4` | `10.33.36.0/24` | PFCP/UDP | 8805 | SMF ↔ UPF session management |
| **N6** | `sp-labs-n6` | `10.33.37.0/24` | IP | — | UPF ↔ internet (data network) |
| **Mgmt** | `sp-labs-mgmt` | `10.33.38.0/24` | — | — | Management, monitoring |

**Why separate networks?** In production, these would be physically separate
network segments with different security zones and routing. Separate Docker
bridge networks simulate this isolation.

### 3.8 Follow the Packet — Complete Call Flow

Here's what happens step-by-step when a UE powers on, registers, and opens
YouTube — mapped to this lab's containers and IPs.

#### Phase 1: Registration ("Hello, I want to join your network")

```
Step 1: UE → gNB (radio/air interface, simulated on mgmt 10.33.38.x)
        UE sends RRC Setup Request + NAS Registration Request.

Step 2: gNB → AMF (N2: 10.33.34.100 → 10.33.34.12, NGAP/SCTP:38412)
        gNB forwards the NAS message to AMF in an NGAP Initial UE Message.

Step 3: AMF → SCP → AUSF (SBI: 10.33.33.12 → .11 → .15, HTTP/2:7777)
        AMF requests authentication. AUSF gets keys from UDM/UDR/MongoDB.

Step 4: AMF → gNB → UE (N2 → radio)
        AMF sends auth challenge. UE responds with proof it has the right
        key (from SIM / config). AUSF verifies.

Step 5: AMF → SCP → UDM (SBI)
        AMF confirms registration. UDM updates status in UDR/MongoDB.

Step 6: AMF → gNB → UE (N2 → radio)
        AMF sends "Registration Accept". The phone is now on the network.
```

#### Phase 2: PDU Session ("I want internet access")

```
Step 7:  UE → gNB → AMF (radio → N2)
         UE sends PDU Session Establishment Request (DNN: "internet").

Step 8:  AMF → SCP → SMF (SBI: .12 → .11 → .13)
         AMF asks SMF to create a session.

Step 9:  SMF → SCP → PCF (SBI: .13 → .11 → .18)
         SMF asks PCF: "What policies apply?" PCF responds with QoS rules.

Step 10: SMF → UPF (N4: 10.33.36.13 → 10.33.36.14, PFCP:8805)
         SMF tells UPF: "Create a GTP tunnel for this UE, assign IP
         10.45.0.2, apply these QoS rules."

Step 11: SMF → AMF → gNB → UE (SBI → N2 → radio)
         AMF sends PDU Session Accept with tunnel info.
         UE creates the TUN interface (uesimtun0) with IP 10.45.0.2.
```

#### Phase 3: User Data ("Watch this YouTube video")

```
Step 12: UE sends IP packet (src: 10.45.0.2, dst: 142.250.x.x/YouTube)
         → into uesimtun0 TUN device.

Step 13: gNB encapsulates in GTP-U tunnel
         (N3: 10.33.35.100 → 10.33.35.14, UDP:2152)

Step 14: UPF receives on N3, decapsulates GTP → raw IP packet.
         Routes it out N6 (10.33.37.14) through ogstun → internet.

Step 15: Internet response comes back → UPF re-encapsulates in GTP-U
         → gNB → UE receives the YouTube video.
```

### 3.9 Subscriber Identity — SIM Cards in Software

In the physical world, your phone has a **SIM card** containing a secret
cryptographic key. In this lab, those secrets are stored in two places:

| Where | What | Values in This Lab |
|-------|------|-------------------|
| **UE config** (UERANSIM env vars) | The "SIM card" | K=`465B5CE8...`, OPc=`E8ED289D...` |
| **MongoDB** (via register-subscriber.sh) | The "operator's database" | Same K and OPc, indexed by IMSI |

**How authentication works (5G-AKA):**
1. AMF asks AUSF for an auth vector.
2. AUSF asks UDM → UDR → MongoDB for the key.
3. AUSF generates a random challenge and computes the expected response.
4. AMF sends the challenge to the UE.
5. The UE's "SIM" uses its copy of the key to compute a response.
6. If response matches → authenticated. If not → rejected.

**The key MUST match.** If the K or OPc in the UERANSIM UE config doesn't
match what's in MongoDB, authentication fails with
`5GMM_CAUSE_ILLEGAL_UE`. This is by far the most common beginner issue.

### 3.10 Network Slicing — Virtual Networks Within a Network

Network slicing lets one physical 5G network act as multiple isolated virtual
networks. Each slice has its own QoS guarantees, security policies, and
potentially its own UPF instances.

A slice is identified by **S-NSSAI**:
- **SST** (Slice/Service Type): 1=eMBB, 2=URLLC, 3=MIoT
- **SD** (Slice Differentiator): further subdivides within an SST

**In this lab:** `SST=1, SD=0xFFFFFF` (default eMBB, no differentiation).
This is configured consistently across AMF, gNB, and UE.

### 3.11 Where F5 BIG-IP Fits in Service Provider Networks

In production, additional **value-added services** sit at the network edge:

```
UE → gNB → UPF ──N6──► [ F5 BIG-IP ] ──► Internet
                         │
                         ├── CGNAT (private → public IP translation)
                         ├── DNS security (filtering, DDoS protection)
                         ├── TCP optimization (for mobile clients)
                         ├── DDoS mitigation
                         └── URL filtering / parental controls
```

The BIG-IP sits on the **N6 / Gi-LAN** interface — the point where user
traffic exits the mobile core. **Why CGNAT?** Mobile networks assign private
IPs to UEs (`10.45.0.0/16` in this lab). These must be translated to public
IPs before reaching the internet — that's Carrier-Grade NAT at scale.

See §19 for detailed instructions on connecting a BIG-IP to this lab.

### 3.12 The Monitoring Stack — Observability

| Component | Container | Role |
|-----------|-----------|------|
| **Prometheus** | `prometheus` (10.33.38.200) | Scrapes metrics from NFs every 5s |
| **Grafana** | `grafana` (10.33.38.201) | Dashboards and visualization |
| **Node Exporter** | `node-exporter` (10.33.38.202) | Host OS metrics (CPU, RAM, disk) |

Monitors AMF (gNBs connected, UE registrations), SMF (PDU sessions), UPF
(GTP packets/sec), and host infrastructure — the same observability pattern
used in production SP networks, at lab scale.

### 3.13 Quick Reference — Component Map

| Component | Container | Networks | Real-World Equivalent |
|-----------|-----------|----------|----------------------|
| MongoDB | `mongodb` | SBI | Subscriber database (HSS backend) |
| NRF | `nrf` | SBI, Mgmt | Service registry (Consul, DNS) |
| SCP | `scp` | SBI | Service mesh proxy (Envoy, Istio) |
| AMF | `amf` | SBI, N2, Mgmt | Mobility manager (MME in 4G) |
| SMF | `smf` | SBI, N4, Mgmt | Session manager (PGW-C in 4G) |
| UPF | `upf` | N3, N4, N6, Mgmt | Data forwarder (PGW-U + SGW in 4G) |
| AUSF | `ausf` | SBI | Authentication server |
| UDM | `udm` | SBI | Profile manager (HSS in 4G) |
| UDR | `udr` | SBI | Database access layer |
| PCF | `pcf` | SBI | Policy engine (PCRF in 4G) |
| NSSF | `nssf` | SBI | Slice selector |
| BSF | `bsf` | SBI | PCF session binder |
| WebUI | `webui` | SBI, Mgmt | Admin portal |
| gNB | `gnb` | N2, N3, Mgmt | Cell tower (eNodeB in 4G) |
| UE | `ue` | Mgmt | Your phone |

---

## 4. Prerequisites

### 4.1 Hardware Requirements

| Deployment | vCPUs | RAM | Disk | GPU |
|------------|-------|-----|------|-----|
| 5G Lab only | 8 | 16 GB | 80 GB SSD | — |
| 5G + Monitoring | 8 | 16 GB | 100 GB SSD | — |
| 5G + 6G + Monitoring | 16 | 32 GB | 150 GB SSD | NVIDIA 8 GB+ VRAM |

### 4.2 Software Requirements

| Software | Version | Notes |
|----------|---------|-------|
| **OS** | Ubuntu 22.04 LTS or 24.04 LTS | Tested on 22.04 |
| **Docker Engine** | 24.0+ | Installed by bootstrap |
| **Docker Compose** | v2.x | Bundled with Docker 24+ |
| **Git** | Any | To clone the repo |
| **make** | Any | For Makefile targets |
| **NVIDIA Drivers** | 535+ | Only for 6G/Sionna |
| **NVIDIA Container Toolkit** | Latest | Only for 6G/Sionna |

### 4.3 Network Requirements

- **Internet access** to pull Docker images from Docker Hub
- Ports **9999** (WebUI), **3000** (Grafana), **9090** (Prometheus) must be
  free on the host (or firewall-opened for remote access)
- No conflicting Docker networks in the `10.33.33.0/24` – `10.33.38.0/24`
  or `10.33.60.0/24` range

---

## 5. Repository Layout

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
│   │   ├── test-5g.sh               # E2E 6-phase validation
│   │   ├── generate-traffic.sh      # Sustained traffic for Grafana
│   │   └── register-subscriber.sh   # MongoDB subscriber insert
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

## 6. Environment Configuration

### 6.1 Create Your .env File

```bash
cp .env.example .env
```

The `.env` file is **git-ignored** and holds all tunable parameters. Defaults
work out of the box — edit only if you need to customize.

### 6.2 Key Variables

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

## 7. Deploying the 5G Lab

### 7.1 Quick Deploy (Recommended)

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
4. Runs `register-subscribers.sh` to insert `NUM_SUBS` subscribers into MongoDB (default 10)
5. Reports "5G Lab is UP"

> The base `ue` container starts with UERANSIM's `-n` flag set to `NUM_UES`
> (default 5), spawning 5 simulated UEs from a single container. Each UE
> gets its own `uesimtunX` TUN interface and auto-incrementing IMSI.

### 7.2 What Gets Started (15 Containers)

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

### 7.3 Startup Order & Dependencies

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

### 7.4 Manual Deploy (Without Make)

```bash
cd 5g-lab
docker compose up -d
sleep 15
bash ../infrastructure/scripts/register-subscriber.sh
docker compose ps
```

### 7.5 Verifying Deployment

```bash
# All 15 containers should show "Up"
docker compose -f 5g-lab/docker-compose.yml ps

# Check key NF logs
docker logs amf --tail=20   # Look for: NG Setup Response
docker logs gnb --tail=20   # Look for: Connected to AMF
docker logs ue  --tail=20   # Look for: Registration complete, PDU session
```

### 7.6 Deploying Multi-UE Profiles

The base deployment starts a single `ue` container with 5 UEs. For realistic
SP traffic testing, you can deploy **three additional UE containers**, each
representing a different subscriber profile:

```bash
# Step 1 — Register subscribers for all 4 profiles (20 total)
make register-multi-ue

# Step 2 — Start the profile UE containers
make deploy-multi-ue

# Step 3 — Verify all UEs are connected
make ue-status
```

The `deploy-multi-ue` target:
1. Runs `register-multi-ue.sh` to insert subscribers across 4 IMSI ranges
2. Runs `docker compose --profile multi-ue up -d` to start the profile containers
3. Waits for the new UEs to register with the core

> **Opt-in activation:** The profile UE containers use Docker Compose's
> `profiles: ["multi-ue"]` feature, so they never start during a normal
> `make deploy-5g`. You explicitly bring them up with `make deploy-multi-ue`.

### 7.7 Multi-UE Container Map

With all profiles deployed, the lab runs **18 containers** (15 base + 3 profile UEs):

| Container | Image | IP Address | IMSI Range | Profile |
|-----------|-------|-----------|------------|---------|
| `ue` | `openverso/ueransim:3.2.6` | `10.33.38.101` | `001`–`005` | Basic (default) |
| `ue-power` | `openverso/ueransim:3.2.6` | `10.33.38.102` | `021`–`025` | Power user |
| `ue-iot` | `openverso/ueransim:3.2.6` | `10.33.38.103` | `031`–`035` | IoT device |
| `ue-enterprise` | `openverso/ueransim:3.2.6` | `10.33.38.104` | `041`–`045` | Enterprise |

Each container runs `nr-ue -n 5`, spawning 5 UEs with auto-incrementing IMSIs.
The `-i` flag sets the starting IMSI offset for each group, ensuring
non-overlapping ranges across all containers.

**IMSI layout** (MCC=999, MNC=70):
```
Container        IMSI Range                           Count
─────────        ──────────                           ─────
ue               999700000000001 – 999700000000005      5
ue-power         999700000000021 – 999700000000025      5
ue-iot           999700000000031 – 999700000000035      5
ue-enterprise    999700000000041 – 999700000000045      5
                                                     ────
                                                Total: 20
```

> **Why gaps between ranges?** The 15-IMSI gaps (006–020, 026–030, etc.)
> allow increasing `NUM_UES` up to 15 per container without collisions.

### 7.8 Stopping Multi-UE Containers

```bash
# Stop only the profile UE containers (keeps base ue + entire core running)
make stop-multi-ue

# Restart ALL UE containers (base + profiles) — useful after re-registration
make restart-ues
```


---

## 8. Deploying the Monitoring Stack

### 8.1 Deploy

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

### 8.2 What Gets Started (3 Containers)

| Container | Image | Port | Purpose |
|-----------|-------|------|---------|
| `prometheus` | `prom/prometheus:v2.55.0` | 9090 | Metrics collection & storage |
| `grafana` | `grafana/grafana:11.3.0` | 3000 | Dashboards & visualization |
| `node-exporter` | `prom/node-exporter:v1.8.2` | 9100 | Host OS metrics |

> **Important:** Deploy the 5G lab **before** the monitoring stack. The
> monitoring compose references `sp-labs-sbi` and `sp-labs-mgmt` as
> `external: true` — they must exist first.

---

## 9. Deploying the 6G Lab

### 9.1 Deploy

```bash
make deploy-6g
```

This auto-detects GPU availability:
- **GPU detected:** `docker compose --profile gpu up -d` → `sionna` container
- **No GPU:** `docker compose --profile cpu up -d` → `sionna-cpu` container

### 9.2 What Gets Started

| Container | Port | Purpose |
|-----------|------|---------|
| `sionna` or `sionna-cpu` | 8888 | GPU/CPU Sionna PHY simulator (Jupyter) |
| `ns3` | — | ns-3 network simulator (batch) |
| `oran-ric-db` | — | O-RAN RIC database (Redis) |
| `oran-ric-e2term` | — | E2 termination |
| `oran-ric-e2mgr` | 3800 | E2 manager |

> The ns-3 Dockerfile **builds from source** (~20 min on first run).

---

## 10. End-to-End Verification

### 10.1 Automated Test

```bash
make test-5g
```

This runs `infrastructure/scripts/test-5g.sh` which validates six phases:

| Phase | Tests |
|-------|-------|
| **1/6 — Container Health** | All 15 containers running |
| **2/6 — Network Connectivity** | gNB↔AMF (N2), gNB↔UPF (N3), SMF↔UPF (N4), NRF (SBI) |
| **3/6 — UE Registration** | NGAP connection, registration accept, PDU session |
| **4/6 — Data Path** | UE has uesimtun0 with 10.45.x.x IP, can ping 8.8.8.8 |
| **5/6 — Traffic Burst** | 50 pings + 200-pkt ping flood through UPF tunnel (populates Grafana) |
| **6/6 — Prometheus Metrics** | Prometheus reachable, AMF `gnb` gauge present, UPF `sessionnbr` present |

**Expected output:**
```
===========================================
  SP-Labs — 5G End-to-End Validation
===========================================

[1/6] Container Health
  ✓ Container 'mongodb' is running
  ✓ Container 'nrf' is running
  ... (15 containers)

[2/6] Network Connectivity
  ✓ gNB can reach AMF on N2 (10.33.34.12)
  ✓ gNB can reach UPF on N3 (10.33.35.14)
  ✓ SMF can reach UPF on N4 (10.33.36.14)
  ✓ NRF is reachable on SBI

[3/6] UE Registration & PDU Session
  ✓ AMF has NGAP connection from gNB
  ✓ UE registration accepted
  ✓ PDU session established

[4/6] Data Path Validation
  ✓ UE has TUN interface with IP
  ✓ UE can ping 8.8.8.8 via UPF tunnel
  ✓ UE can resolve DNS via UPF tunnel

[5/6] Traffic Burst (populates Grafana dashboard)
  Sending 50 pings through UPF tunnel...
  ✓ Traffic burst sent through UPF (50 pings + 200 flood)

[6/6] Prometheus Metrics Check
  ✓ Prometheus is reachable
  ✓ AMF metrics in Prometheus (gnb gauge)
  ✓ UPF metrics in Prometheus (sessionnbr)

===========================================
  ALL 24 TESTS PASSED
===========================================

  💡 For sustained traffic & full Grafana graphs, run:
     make generate-traffic
```

### 10.2 Manual Verification

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

### 10.3 6G Lab Verification

```bash
make test-6g
```

### 10.4 Multi-UE Verification

After deploying multi-UE profiles (§7.6), verify that all subscriber groups
registered and established PDU sessions:

#### Quick Status

```bash
make ue-status
```

**Expected output:**
```
===========================================
  SP-Labs — UE Status
===========================================

[ue] 5 tunnels active
  uesimtun0: 10.45.0.2
  uesimtun1: 10.45.0.3
  uesimtun2: 10.45.0.4
  uesimtun3: 10.45.0.5
  uesimtun4: 10.45.0.6

[ue-power] 5 tunnels active
  uesimtun0: 10.45.0.7
  ...

[ue-iot] 5 tunnels active
  ...

[ue-enterprise] 5 tunnels active
  ...

MongoDB subscribers: 20
AMF sessions (Prometheus): 20
```

#### Manual Verification per Container

```bash
# Check that each UE container has 5 TUN interfaces
for c in ue ue-power ue-iot ue-enterprise; do
  echo "--- $c ---"
  docker exec "$c" ip -4 addr show 2>/dev/null | grep uesimtun
done

# Verify subscriber count in MongoDB
docker exec mongodb mongosh --quiet --eval "
  db = db.getSiblingDB('open5gs');
  print('Total subscribers: ' + db.subscribers.countDocuments());
"

# Check AMF sees all 20 UE registrations
docker logs amf 2>&1 | grep -c "Registration accept"

# Verify each profile can reach the internet
docker exec ue           ping -I uesimtun0 -c 1 8.8.8.8
docker exec ue-power     ping -I uesimtun0 -c 1 8.8.8.8
docker exec ue-iot       ping -I uesimtun0 -c 1 8.8.8.8
docker exec ue-enterprise ping -I uesimtun0 -c 1 8.8.8.8
```

#### Prometheus Metric Validation

With all 20 UEs registered, Prometheus should report:

| Metric | Expected Value |
|--------|---------------|
| `gnb` | `1` (single gNodeB) |
| `ran_ue` | `20` |
| `amf_session` | `20` |
| `ues_active` | `20` |
| `fivegs_upffunction_upf_sessionnbr` | `20` |

```bash
# Quick check via Prometheus API
for m in gnb ran_ue amf_session ues_active fivegs_upffunction_upf_sessionnbr; do
  val=$(curl -sf "http://localhost:9090/api/v1/query?query=${m}" | \
    grep -oP '"value":\[\d+\.?\d*,"(\d+)"' | grep -oP '"\d+"' | tr -d '"' | head -1)
  echo "$m = ${val:-(no data)}"
done
```

#### Troubleshooting Multi-UE Registration

If fewer than 20 UEs appear:

| Symptom | Cause | Fix |
|---------|-------|-----|
| Container running but 0 tunnels | Subscribers not registered for that IMSI range | `make register-multi-ue` then `make restart-ues` |
| Some UEs register, others don't | Race condition — AMF overwhelmed | Wait 30s, check again; increase `REGISTER_WAIT` |
| "Authentication failure" in UE logs | K/OPc mismatch in MongoDB | Verify: `docker exec mongodb mongosh --quiet --eval "db.getSiblingDB('open5gs').subscribers.findOne({imsi:'999700000000021'}).security"` |
| Container not starting | Profile not activated | Use `make deploy-multi-ue` (not `make deploy-5g`) |


---

## 11. Web Interfaces

| Service | URL | Credentials | Purpose |
|---------|-----|-------------|---------|
| **Open5GS WebUI** | `http://<HOST>:9999` | `admin` / `1423` | Subscriber management |
| **Grafana** | `http://<HOST>:3000` | `admin` / `sp-labs-admin` | Monitoring dashboards |
| **Prometheus** | `http://<HOST>:9090` | — (no auth) | Metrics & targets |
| **Sionna Jupyter** | `http://<HOST>:8888` | Token from `docker logs sionna` | 6G PHY research |

> Replace `<HOST>` with your server's IP address or hostname.

### 11.1 Open5GS WebUI

The `gradiant/open5gs-webui:2.7.1` image runs a Next.js application connected
to MongoDB. The default admin account (`admin`/`1423`) is **auto-created on
first startup** because we set `NODE_ENV=development` in the container.

**To add a subscriber via WebUI:**
1. Navigate to `http://<HOST>:9999`
2. Log in with `admin` / `1423`
3. Click **Subscriber** → **+** (Add)
4. Fill in IMSI, K, OPc, APN, SST
5. Click **Save**

### 11.2 Grafana

1. Navigate to `http://<HOST>:3000`
2. Log in with `admin` / `sp-labs-admin`
3. Go to **Dashboards** → **SP-Labs** folder → **SP-Labs — 5G Core Overview**

The dashboard is auto-provisioned from
`monitoring/grafana/dashboards/5g-core-dashboard.json`.

---

## 12. Subscriber Management

### 12.1 Default Test Subscriber

| Field | Value |
|-------|-------|
| IMSI | `999700000000001` |
| Key (K) | `465B5CE8B199B49FAA5F0A2EE238A6BC` |
| OPc | `E8ED289DEBA952E4283B54E88E6183CA` |
| AMF | `8000` |
| SST | `1` (eMBB) |
| DNN/APN | `internet` |
| AMBR | 1 Gbps up / 1 Gbps down |

### 12.2 Register via Script (Recommended)

```bash
bash infrastructure/scripts/register-subscriber.sh
```

This inserts (or replaces) the subscriber directly into MongoDB. The script
reads IMSI/Key/OPc from `.env` variables.

### 12.3 Register via MongoDB CLI

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

### 12.4 List / Delete Subscribers

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

### 12.5 Bulk Registration

For testing with more than one subscriber, use the bulk registration script:

```bash
# Register 10 subscribers (default)
make register-subs

# Register 20 subscribers
make register-subs NUM_SUBS=20
```

The script (`infrastructure/scripts/register-subscribers.sh`) inserts `N`
subscribers with consecutive IMSIs starting from `999700000000001`. All
subscribers share the same K/OPc (lab simplification) and use the `internet`
APN with SST=1.

The `--profiles` flag distributes subscribers across 4 QoS tiers:

| Profile | QoS Index | DL AMBR | UL AMBR | Simulates |
|---------|-----------|---------|---------|-----------|
| **Basic** | 9 | 1 Gbps | 500 Mbps | Standard mobile broadband |
| **Power** | 8 | 5 Gbps | 2 Gbps | Heavy data user / tethering |
| **IoT** | 9 | 1 Mbps | 1 Mbps | Low-bandwidth sensor device |
| **Enterprise** | 7 | 2 Gbps | 1 Gbps | Business-critical application |

> **Why SST=1 for all profiles?** The lab's NSSF is configured with a single
> S-NSSAI (SST=1, SD=0xFFFFFF). Using SST=3 for IoT would require NSSF
> reconfiguration. QoS differentiation is achieved through AMBR values and
> QoS Index (5QI) instead — this is realistic, as many operators use a
> single slice with per-subscriber QoS policies.

### 12.6 Multi-UE Subscriber Profiles

For the full multi-UE deployment (§7.6), use the dedicated registration script
that creates subscribers across all 4 UE container groups:

```bash
make register-multi-ue
```

This creates **4 non-overlapping IMSI blocks**, one per container:

| Profile | Container | Start IMSI | End IMSI | AMBR (DL/UL) | 5QI |
|---------|-----------|------------|----------|-------------|-----|
| Basic | `ue` | `...0001` | `...0005` | 1G / 500M | 9 |
| Power | `ue-power` | `...0021` | `...0025` | 5G / 2G | 8 |
| IoT | `ue-iot` | `...0031` | `...0035` | 1M / 1M | 9 |
| Enterprise | `ue-enterprise` | `...0041` | `...0045` | 2G / 1G | 7 |

**Key details:**
- All profiles use the same K and OPc values (lab environment)
- All use `internet` APN with SST=1
- IMSI ranges are spaced 20 apart to allow scaling `NUM_UES` up to 15
- The script clears **all** existing subscribers before inserting (clean slate)

**Custom count per group:**
```bash
# 10 UEs per profile = 40 total
bash infrastructure/scripts/register-multi-ue.sh 10
```

After registration, restart the UE containers to pick up the new subscribers:
```bash
make restart-ues
```

### 12.7 Verifying Registered Subscribers

```bash
# Count total subscribers
docker exec mongodb mongosh --quiet --eval "
  db = db.getSiblingDB('open5gs');
  print('Total: ' + db.subscribers.countDocuments());
"

# List all subscriber IMSIs, sorted
docker exec mongodb mongosh --quiet --eval "
  db = db.getSiblingDB('open5gs');
  db.subscribers.find({},{imsi:1,_id:0}).sort({imsi:1}).forEach(
    function(r){ print('  ' + r.imsi); }
  );
"

# Inspect a specific subscriber's QoS settings
docker exec mongodb mongosh --quiet --eval "
  db = db.getSiblingDB('open5gs');
  printjson(db.subscribers.findOne(
    {imsi:'999700000000021'},
    {imsi:1, ambr:1, 'slice.session.qos':1, _id:0}
  ));
"
```


---

## 13. Monitoring & Dashboards

### 13.1 Prometheus Targets

5G NF jobs scrape every **5 seconds** (global default is 15s) for responsive
real-time graphs.

| Job | Target | Network | Scrape | Monitors |
|-----|--------|---------|--------|----------|
| `prometheus` | `localhost:9090` | — | 15s | Prometheus self-metrics |
| `node-exporter` | `node-exporter:9100` | mgmt | 15s | Host CPU, memory, disk, network |
| `open5gs-amf` | `10.33.33.12:9090` | SBI | **5s** | AMF registrations, sessions, gNB count |
| `open5gs-smf` | `10.33.33.13:9090` | SBI | **5s** | SMF PDU sessions, bearers, N4 |
| `open5gs-upf` | `10.33.38.14:9090` | mgmt | **5s** | UPF throughput (GTP N3 packets), sessions |

**Verify targets are up:**
```bash
curl -s http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

### 13.2 Open5GS Metric Names (v2.7.0)

These are the **actual** Prometheus metrics exposed by Open5GS 2.7.0 (verified
from source: `src/amf/metrics.c`, `src/smf/metrics.c`, `src/upf/metrics.c`):

**AMF Metrics:**

| Metric | Type | Description |
|--------|------|-------------|
| `gnb` | Gauge | Connected gNodeBs |
| `ran_ue` | Gauge | RAN UE connections |
| `amf_session` | Gauge | Active AMF sessions |
| `fivegs_amffunction_rm_reginitreq` | Counter | Initial registration requests |
| `fivegs_amffunction_rm_reginitsucc` | Counter | Initial registration successes |
| `fivegs_amffunction_rm_regperiodreq` | Counter | Periodic registration requests |
| `fivegs_amffunction_rm_regperiodsucc` | Counter | Periodic registration successes |
| `fivegs_amffunction_rm_regmobreq` | Counter | Mobility registration requests |
| `fivegs_amffunction_rm_regmobsucc` | Counter | Mobility registration successes |
| `fivegs_amffunction_mm_paging5g` | Counter | 5G paging events |

**SMF Metrics:**

| Metric | Type | Description |
|--------|------|-------------|
| `ues_active` | Gauge | Active UEs with sessions |
| `bearers_active` | Gauge | Active bearers |
| `gtp_peers_active` | Gauge | Active GTP peers |
| `fivegs_smffunction_sm_n4sessionestabreq` | Counter | N4 session establishment requests |

**UPF Metrics:**

| Metric | Type | Description |
|--------|------|-------------|
| `fivegs_upffunction_upf_sessionnbr` | Gauge | Active UPF sessions |
| `fivegs_ep_n3_gtp_indatapktn3upf` | Counter | GTP N3 inbound data packets |
| `fivegs_ep_n3_gtp_outdatapktn3upf` | Counter | GTP N3 outbound data packets |

### 13.3 Grafana Dashboard — 5G Core Overview

Navigate to **Dashboards → SP-Labs → SP-Labs — 5G Core Overview**.

The dashboard contains **27 panels** organized into 5 collapsible sections:

**📡 Registration & Sessions** — 6 stat panels showing `gnb`, `ran_ue`,
`amf_session`, `ues_active`, `bearers_active`, `fivegs_upffunction_upf_sessionnbr`.
Panels turn green when value ≥ 1.

**📊 AMF — Registration Procedures** — 4 timeseries panels: registration
request vs success rates, cumulative counters, RAN UEs & sessions over time,
5G paging events.

**📦 SMF — PDU Session Management** — 2 timeseries panels: N4 session
establishment rate, active sessions & bearers & GTP peers over time.

**🚀 UPF — User Plane & Throughput** — 4 timeseries panels: N3 GTP packet
rate (inbound/outbound pkt/s), cumulative N3 GTP packet counters, N4 session
establishment, UPF active session count.

**🖥️ Host — Infrastructure** — 6 panels: CPU %, memory gauge, network
traffic (RX/TX), system load averages, disk usage gauge, stacked memory
breakdown.

### 13.4 Generating Traffic for Dashboards

Dashboard panels only show data when traffic flows through the 5G core.
Use the built-in traffic generator:

```bash
# Quick burst (run during E2E test)
make test-5g

# Sustained traffic — default 5 minutes
make generate-traffic

# Custom duration — 10 minutes
make generate-traffic TRAFFIC_DURATION=10
```

The traffic generator (`infrastructure/scripts/generate-traffic.sh`) runs
4 parallel streams through the UERANSIM UE tunnel:

| Phase | Traffic Type | Pattern |
|-------|-------------|---------|
| 1. ICMP | 3 ping streams (8.8.8.8, 1.1.1.1, 8.8.4.4) | 0.5–1s intervals, 1400B payloads |
| 2. DNS | HTTP GET to 1.1.1.1 | Every 3 seconds |
| 3. HTTP | wget downloads from 1.1.1.1, 8.8.8.8 | Every 5 seconds |
| 4. Burst | 100-packet ping flood | Every 30 seconds |

The script shows live progress and prints a **final metrics snapshot** from
Prometheus when complete.

### 13.5 Multi-UE Traffic Generation

When multi-UE profiles are deployed (§7.6), use the differentiated traffic
generator to simulate realistic SP network patterns:

```bash
# Default 5 minutes
make generate-multi-traffic

# Custom duration — 15 minutes
make generate-multi-traffic TRAFFIC_DURATION=15
```

The script (`infrastructure/scripts/generate-multi-traffic.sh`) automatically
discovers all running UE containers and their active TUN interfaces, then
launches per-profile traffic patterns:

| Container | Profile | Traffic Pattern | Characteristics |
|-----------|---------|----------------|-----------------|
| `ue` | Basic | Pings (0.5–1s) + periodic HTTP | Moderate — typical smartphone user |
| `ue-power` | Power | 1400B pings (0.2s), HTTP floods, 200-pkt bursts | Heavy — streaming/tethering user |
| `ue-iot` | IoT | 64B pings (10s), HTTP every 30s | Minimal — sensor heartbeat |
| `ue-enterprise` | Enterprise | Steady 1/s pings, HTTP every 3–4s | Consistent — business application |

**How it works:**

1. **Discovery** — Scans `ue`, `ue-power`, `ue-iot`, `ue-enterprise` containers
   for active `uesimtunX` interfaces with assigned IPs
2. **Launch** — Spawns background traffic generators for each discovered tunnel,
   matching the traffic pattern to the container name
3. **Monitor** — Shows live progress every 15 seconds: active generator count,
   health check on the first UE, time remaining
4. **Report** — At completion, queries Prometheus for a final metrics snapshot

**Example output:**
```
===========================================
  SP-Labs — Multi-UE Traffic Generator
===========================================
  Duration: 5 minutes
  Started:  2026-11-24 14:30:00

[DISCOVERY] Scanning for active UE containers...
  ✓ ue: 5 tunnel(s) — IPs: 10.45.0.2 10.45.0.3 10.45.0.4 10.45.0.5 10.45.0.6
  ✓ ue-power: 5 tunnel(s) — IPs: 10.45.0.7 10.45.0.8 ...
  ✓ ue-iot: 5 tunnel(s) — IPs: 10.45.0.12 10.45.0.13 ...
  ✓ ue-enterprise: 5 tunnel(s) — IPs: 10.45.0.17 10.45.0.18 ...

  Total: 4 containers, 20 tunnels

[LAUNCHING] Starting traffic generators...
  ▶ ue/uesimtun0 (10.45.0.2): basic — pings + HTTP
  ▶ ue-power/uesimtun0 (10.45.0.7): power — large pkts + floods
  ▶ ue-iot/uesimtun0 (10.45.0.12): iot — tiny heartbeats
  ▶ ue-enterprise/uesimtun0 (10.45.0.17): enterprise — steady mixed
  ...

[RUNNING] 48 background generators active for 5m

  [14:30:15] ✓ 48/48 generators active — 4m 45s left
  [14:30:30] ✓ 48/48 generators active — 4m 30s left
  ...

[RESULTS] Final metric snapshot from Prometheus...
  gnb = 1
  ran_ue = 20
  amf_session = 20
  ues_active = 20
  fivegs_upffunction_upf_sessionnbr = 20
  fivegs_ep_n3_gtp_indatapktn3upf = 145832
  fivegs_ep_n3_gtp_outdatapktn3upf = 139247

===========================================
  Multi-UE traffic generation complete!
  Containers: 4  Tunnels: 20  Duration: 5m
  Ended: 2026-11-24 14:35:00
===========================================
```

**What to look for in Grafana:**

After running multi-UE traffic, the **SP-Labs — 5G Core Overview** dashboard
shows differentiated patterns across its panels:

| Panel | What You'll See |
|-------|----------------|
| **RAN UEs** | Stat jumps from 5 → 20 when multi-UE is deployed |
| **UPF Sessions** | 20 active sessions |
| **N3 GTP Packet Rate** | Stepped increases — IoT (flat, low), basic (moderate), enterprise (steady), power (spiky, high) |
| **N3 GTP Cumulative** | Power UEs contribute the steepest slope; IoT barely visible |
| **Host Network Traffic** | TX/RX rates reflect aggregate traffic from all profiles |

> **Tip:** Set Grafana's time range to "Last 15 minutes" and auto-refresh
> to 5s during traffic generation for the best real-time visibility.

### 13.6 Adding Custom Dashboards

Place JSON files in `monitoring/grafana/dashboards/` and restart Grafana.
Ensure the datasource UID in your JSON matches `"uid": "prometheus"`.

```bash
docker restart grafana
```

### 13.7 Inspecting Raw Metrics

```bash
# Check what metrics AMF exposes
docker exec prometheus wget -qO- http://10.33.33.12:9090/metrics | head -30

# Check what metrics SMF exposes
docker exec prometheus wget -qO- http://10.33.33.13:9090/metrics | head -30

# Check what metrics UPF exposes
docker exec prometheus wget -qO- http://10.33.38.14:9090/metrics | head -30

# Query a specific metric via Prometheus API
curl -s 'http://localhost:9090/api/v1/query?query=gnb' | jq '.data.result'
```

---

## 14. Day-to-Day Operations

### 14.1 Starting / Stopping

```bash
make deploy-5g           # Start 5G lab (15 containers + register subscribers)
make deploy-monitoring   # Start monitoring
make deploy-6g           # Start 6G lab
make deploy-all          # Start everything

make deploy-multi-ue     # Start multi-UE profile containers (ue-power, ue-iot, ue-enterprise)
make stop-multi-ue       # Stop profile UE containers (keeps base ue + core running)
make restart-ues         # Restart ALL UE containers (base + profiles)

make stop-5g             # Stop 5G lab (stops all UE containers too)
make stop-monitoring     # Stop monitoring
make stop-6g             # Stop 6G lab
make stop-all            # Stop everything

make restart-5g          # Stop + start 5G lab
make destroy-all         # Stop everything + delete volumes (data loss!)
```

### 14.2 Viewing Logs

```bash
make logs-5g                              # All 5G containers
docker logs amf -f --tail=50              # Specific container
docker logs amf 2>&1 | grep -i "error"    # Search for errors
```

### 14.3 Checking Status

```bash
make status      # Shows all three labs
make ue-status   # UE-specific: tunnels per container, subscriber count, Prometheus metrics
```

### 14.4 Restarting a Single NF

```bash
docker restart amf    # Restart just AMF
docker restart ue     # Restart base UE container (e.g., after re-registering subscriber)
```

To restart all UE containers (base + multi-UE profiles) after subscriber
re-registration:

```bash
make restart-ues    # Restarts: ue, ue-power, ue-iot, ue-enterprise
```

### 14.5 Updating Configurations

After editing any config file under `5g-lab/open5gs/config/`:

```bash
docker restart <nf-name>    # Pick up the changed config
```


---

## 15. Configuration Deep-Dive

### 15.1 Open5GS Config Structure

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

### 15.2 AMF Config Highlights

```yaml
amf:
  sbi:
    server:
      - address: 10.33.33.12   # SBI network — explicit IP, NOT dev:
        port: 7777
    client:
      scp:
        - uri: http://10.33.33.11:7777
  ngap:
    server:
      - address: 10.33.34.12   # N2 network
  metrics:
    server:
      - address: 10.33.33.12   # Prometheus scrapes via SBI
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

### 15.3 SMF Config Highlights

```yaml
smf:
  sbi:
    server:
      - address: 10.33.33.13   # SBI network — explicit IP
        port: 7777
    client:
      scp:
        - uri: http://10.33.33.11:7777
  pfcp:
    server:
      - address: 10.33.36.13   # N4 network
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

### 15.4 UPF Config Highlights

```yaml
upf:
  pfcp:
    server:
      - address: 10.33.36.14   # N4 network
  gtpu:
    server:
      - address: 10.33.35.14   # N3 network
  metrics:
    server:
      - address: 10.33.38.14   # Mgmt interface for Prometheus
        port: 9090
  session:
    - subnet: 10.45.0.1/16     # Must match SMF session config
```

> **Critical — always use `address:`, never `dev:`** Docker's `ethN` interface
> ordering is **non-deterministic** across `docker compose down/up` cycles. It
> may follow network creation order, lexicographic order of network names, or
> Docker-internal ID order. Using explicit IP addresses eliminates this class
> of bugs entirely.

### 15.5 UDR / PCF — MongoDB Connection

```yaml
db_uri: mongodb://mongodb:27017/open5gs   # Top-level, outside NF section
```

The `openverso/open5gs` entrypoint also reads `DB_URI` env var and overrides
the YAML value. Set both for reliability.

### 15.6 UERANSIM Environment Variables

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

### 15.7 FreeDiameter — Not Used

FreeDiameter is for 4G/Diameter interop. In Docker, it crashes SMF due to
hostname DNS resolution failure during certificate generation. The SMF config
in this lab intentionally **omits** `freeDiameter:`.


---

## 16. Networking Reference

### 16.1 Docker Networks

| Network | Subnet | Interface | Purpose |
|---------|--------|-----------|---------|
| `sp-labs-sbi` | `10.33.33.0/24` | SBI | Inter-NF HTTP/2 service mesh |
| `sp-labs-n2` | `10.33.34.0/24` | N2 | gNB ↔ AMF (NGAP/SCTP) |
| `sp-labs-n3` | `10.33.35.0/24` | N3 | gNB ↔ UPF (GTP-U user data) |
| `sp-labs-n4` | `10.33.36.0/24` | N4 | SMF ↔ UPF (PFCP session mgmt) |
| `sp-labs-n6` | `10.33.37.0/24` | N6 | UPF → Internet |
| `sp-labs-mgmt` | `10.33.38.0/24` | — | Management, monitoring |

### 16.2 Container IP Assignments

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

### 16.3 Why We Use `address:` Instead of `dev:` in Open5GS Configs

> **Critical:** Docker's `ethN` assignment order is **non-deterministic** for
> multi-network containers. It can change between `docker compose down/up`
> cycles depending on network creation order, Docker engine internals, or
> platform. **Never use `dev: ethN`** in Open5GS configs — always use
> `address: <explicit-IP>` to guarantee the NF binds to the correct network.

### 16.4 UE IP Pool

| Parameter | Value |
|-----------|-------|
| Subnet | `10.45.0.0/16` |
| Gateway | `10.45.0.1` |
| First UE IP | `10.45.0.2` |
| DNS Servers | `8.8.8.8`, `8.8.4.4` |

### 16.5 Host Port Mappings

| Port | Protocol | Service |
|------|----------|---------|
| 9999 | TCP | Open5GS WebUI |
| 38412 | SCTP | AMF NGAP |
| 9090 | TCP | Prometheus |
| 3000 | TCP | Grafana |
| 9100 | TCP | Node Exporter |
| 8888 | TCP | Sionna Jupyter |
| 3800 | TCP | O-RAN RIC E2 Mgr |

### 16.6 NAT / IP Forwarding

The bootstrap script configures host-level NAT for UE internet access:

```bash
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
iptables -A FORWARD -i ogstun -j ACCEPT
iptables -A FORWARD -o ogstun -m state --state RELATED,ESTABLISHED -j ACCEPT
```

If UE can't ping 8.8.8.8, re-run the above commands with `sudo`.


---

## 17. Troubleshooting

### 17.1 Container Won't Start / Crash Loop

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

### 17.2 UE Registration Fails

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

### 17.3 No Internet from UE

```bash
docker exec ue ip addr show uesimtun0       # Verify tunnel IP
sysctl net.ipv4.ip_forward                   # Must be 1
sudo iptables -t nat -L POSTROUTING -n       # Check NAT rules
docker exec ue ping -I uesimtun0 -c 2 8.8.8.8
```

### 17.4 WebUI Login Fails

| Symptom | Cause | Fix |
|---------|-------|-----|
| `admin`/`1423` rejected | Production mode | Set `NODE_ENV=development` |
| Connection refused :9999 | Container not running | Check `docker logs webui` |

### 17.5 Grafana Dashboard Empty

| Symptom | Cause | Fix |
|---------|-------|-----|
| "No data" on all panels | Datasource UID mismatch | Set `uid: prometheus` in datasources.yml |
| "No data" on 5G panels only | Prometheus can't reach NFs | Check `http://localhost:9090/targets` |
| "No data" on 5G panels only | No traffic generated yet | Run `make generate-traffic` |
| Node panels work, 5G don't | Prometheus not on SBI network | Check monitoring compose networks |
| Stat panels show 0 / red | No UE registered or tunnel down | Run `make test-5g` to verify UE status |

### 17.6 Prometheus Targets Down

```bash
# Test from inside Prometheus container
docker exec prometheus wget -qO- http://10.33.33.12:9090/metrics | head -5
docker exec prometheus wget -qO- http://10.33.38.14:9090/metrics | head -5
docker exec prometheus ping -c 1 10.33.33.12
```

### 17.7 Network Debugging

```bash
docker network ls | grep sp-labs
docker network inspect sp-labs-sbi

# Capture traffic
docker exec amf tcpdump -i any -w /tmp/ngap.pcap port 38412
docker exec upf tcpdump -i any -w /tmp/gtp.pcap port 2152
docker cp amf:/tmp/ngap.pcap ./ngap.pcap
```

### 17.8 Full Reset

```bash
make destroy-all
docker network prune -f
docker volume prune -f
make deploy-5g
make deploy-monitoring
```


---

## 18. Lessons Learned & Gotchas

These are issues discovered during lab build-out, specific to the
`openverso/open5gs:2.7.0` and `openverso/ueransim:3.2.6` Docker images.

### 18.1 `logger.file` Must Be a Scalar

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

### 18.2 FreeDiameter Crashes SMF in Docker

The `freeDiameter:` section triggers hostname resolution for certificate
generation. In Docker, the container hostname doesn't resolve, causing
immediate crash. **Solution:** Remove it — not needed for 5G SA.

### 18.3 Docker ethN Interface Order Is Non-Deterministic

Docker's `ethN` assignment for multi-network containers is **not deterministic**.
It may follow network creation order, lexicographic name order, or Docker-
internal ID order — and it can **change between `docker compose down/up`
cycles**. This was confirmed empirically: the same compose file produced
different ethN mappings after recreation.

**Solution:** Never use `dev: ethN` in Open5GS configs. Always use explicit
`address:` with the IP from docker-compose.yml. See §16.3.

### 18.4 All Open5GS Bind Directives Must Use `address:` Not `dev:`

```yaml
# WRONG — ethN order is non-deterministic
sbi:
  server:
    - dev: eth0
      port: 7777

# CORRECT — explicit IP from docker-compose.yml
sbi:
  server:
    - address: 10.33.33.12
      port: 7777
```

This applies to `sbi.server`, `ngap.server`, `pfcp.server`, `gtpu.server`,
`metrics.server`, and any other bind directive. The only exception is
`gtpc`/`gtpu` in SMF which **require** `address:` (see below).

### 18.5 SMF `gtpc`/`gtpu` Assertion Failure with `dev:`

```yaml
# WRONG — startup assertion failure (SMF-specific bug)
gtpc:
  server:
    - dev: eth0

# CORRECT
gtpc:
  server:
    - address: 10.33.33.13
```

### 18.6 Session Subnet Uses Gateway/Prefix Format

```yaml
# CORRECT — 10.45.0.1 is the gateway
session:
  - subnet: 10.45.0.1/16

# WRONG — network address, not gateway
session:
  - subnet: 10.45.0.0/16
```

### 18.7 `openverso` Entrypoint Overrides `db_uri`

The entrypoint reads `DB_URI` env var and writes it into the config. For NFs
needing MongoDB (UDR, PCF), set **both** YAML `db_uri:` and Docker `DB_URI=`.

### 18.8 WebUI Default Account Only in Dev Mode

The admin/1423 account is only auto-created when `NODE_ENV !== 'production'`.
Gradiant image defaults to production. **Fix:** `NODE_ENV=development`.

### 18.9 Grafana Datasource UID Must Match Dashboard JSON

Auto-generated UIDs won't match `"uid": "prometheus"` in dashboard JSON.
**Fix:** Explicitly set `uid: prometheus` in `datasources.yml`.

### 18.10 SCP Requires `global` Section

Without `global:`, SCP fails to parse the config:
```yaml
global:
  max:
    ue: 1024
```

### 18.11 UERANSIM Command Is `gnb`/`ue`, Not `nr-gnb`/`nr-ue`

The entrypoint maps `gnb` → `nr-gnb` after env setup and `envsubst`:
```yaml
command: gnb   # CORRECT
command: nr-gnb   # WRONG
```


---

## 19. Connecting an External F5 BIG-IP

This section explains how to integrate an external F5 BIG-IP (hardware
appliance, BIG-IP VE, or BIG-IP Next) into the SP-Labs 5G architecture.
This lays the foundation for advanced lab exercises: Gi-LAN services, CGNAT,
traffic steering, API protection, GTP visibility, and more.

### 19.1 BIG-IP Placement Options

In a real service-provider 5G deployment, BIG-IP sits at one or more of
these network insertion points:

```
                                                     ┌─────────────┐
  ┌──────────┐    ┌──────────┐    ┌──────────┐       │  F5 BIG-IP  │
  │    UE    ├───►│   gNB    ├─N3─┤   UPF    ├──N6──►│  (Gi-LAN)   │──► Internet
  └──────────┘    └────┬─────┘    └────┬─────┘       │             │
                       │N2             │N4            └──────┬──────┘
                  ┌────┴─────┐   ┌────┴─────┐               │
                  │   AMF    │   │   SMF    │          ┌────┴──────┐
                  └────┬─────┘   └──────────┘          │ BIG-IP as │
                       │SBI                            │ SBI Proxy │
                  ┌────┴─────┐                         └───────────┘
                  │ NRF/SCP  │
                  └──────────┘
```

| Placement | Network | Use Cases |
|-----------|---------|-----------|
| **N6 / Gi-LAN** (most common) | `sp-labs-n6` (10.33.37.0/24) | CGNAT, DNS proxy, TCP optimization, SSL visibility, URL filtering |
| **N3 / N9 steering** | `sp-labs-n3` (10.33.35.0/24) | GTP firewall, traffic classification, subscriber-aware steering |
| **SBI proxy** | `sp-labs-sbi` (10.33.33.0/24) | API gateway for NF HTTP/2, rate limiting, NRF load balancing |
| **N4 signaling proxy** | `sp-labs-n4` (10.33.36.0/24) | PFCP proxy, session-aware policy enforcement |
| **Management** | `sp-labs-mgmt` (10.33.38.0/24) | BIG-IP management, iControl REST, telemetry export |

### 19.2 Network Connectivity — N6 / Gi-LAN Insertion

The primary insertion point is **N6 (Gi-LAN)** — BIG-IP sits between the UPF
and the internet, processing all subscriber data traffic. A `10.1.10.0/24`
transit network bridges the Docker host to BIG-IP.

```
  ┌────────────────── Docker Host ──────────────────┐
  │                                                  │
  │  ┌────┐  N3  ┌─────┐  N6  ┌──────────┐          │  10.1.10.0/24    ┌──────────┐
  │  │ UE ├─────►│ UPF ├─────►│ N6 Bridge├──────────────────────────────► BIG-IP   │──► Internet
  │  └────┘      └─────┘      │ br-xxxx  │  transit  │                  │10.1.10.200│
  │               10.33.37.14 │10.33.37.1│           │                  └──────────┘
  │                           └──────────┘           │
  └──────────────────────────────────────────────────┘
```

**Automated setup (recommended):**

```bash
# 1. Configure BIG-IP first (see §19.4)
# 2. Redirect UPF traffic through BIG-IP
make connect-bigip                    # Uses .env defaults
# or override:
BIGIP_N6_IP=10.1.10.200 make connect-bigip
```

The `connect-bigip` target runs `configure-bigip-route.sh` which:
1. Verifies UPF is running and BIG-IP is reachable
2. Identifies the N6 Docker bridge interface
3. Adds the host gateway IP (`10.33.37.1`) to the bridge
4. Configures iptables forwarding rules
5. **Removes** the host's MASQUERADE rule for the UE pool (BIG-IP CGNAT replaces it)
6. Sets the UPF default route to BIG-IP (`10.1.10.200`)

**Manual setup (if preferred):**

```bash
# Find N6 bridge
N6_BRIDGE="br-$(docker network inspect sp-labs-n6 --format '{{.Id}}' | cut -c1-12)"
# Add host gateway on bridge
sudo ip addr add 10.33.37.1/24 dev $N6_BRIDGE
# Remove old MASQUERADE
sudo iptables -t nat -D POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
# Set UPF default route
docker exec upf ip route replace 10.1.10.0/24 via 10.33.37.1
docker exec upf ip route replace default via 10.1.10.200
```

**BIG-IP return routes (configure on BIG-IP via tmsh):**

```
create net route ue_pool  network 10.45.0.0/16  gw 10.33.37.1
create net route lab_n6   network 10.33.37.0/24  gw 10.33.37.1
```

**IP assignments:**

| Interface | IP Address | Purpose |
|-----------|-----------|---------|
| BIG-IP Internal (transit) | `10.1.10.200/24` | Receives traffic from UPF |
| BIG-IP External | `198.51.100.200/24` (adjust) | Sends traffic to internet |
| BIG-IP Management | `10.33.38.250` | iControl REST, GUI, SSH |
| Docker host on N6 bridge | `10.33.37.1` | Gateway for BIG-IP return traffic |

**To disconnect BIG-IP and restore direct internet access:**

```bash
make disconnect-bigip    # Restores host MASQUERADE, resets UPF route
```

### 19.3 Network Connectivity — SBI API Gateway

For HTTP/2 SBI traffic inspection or API protection:

```bash
# BIG-IP acts as reverse proxy in front of NRF or SCP:
#   NFs → BIG-IP VIP (10.33.33.250:7777) → NRF (10.33.33.10:7777)
#
# Update NF configs to point scp/nrf URI to BIG-IP VIP:
#   scp:
#     client:
#       nrf:
#         - uri: http://10.33.33.250:7777
```

### 19.4 BIG-IP Configuration — CGNAT, AFM & DNS

A complete tmsh configuration script is provided at
`infrastructure/scripts/configure-bigip-tmsh.sh`. Run it on BIG-IP or copy
the tmsh commands from its output.

The script configures BIG-IP in 6 phases:

| Phase | What It Creates |
|-------|----------------|
| 1. Network | `vlan_internal`, `vlan_external`, self-IPs, return routes |
| 2. CGNAT | `snatpool_cgnat` (4 IPs), `vs_cgnat` (wildcard FastL4) |
| 3. AFM | `policy_gi_lan` (5 rules: DNS, HTTP/S, ICMP, NTP, deny-all) |
| 4. DNS | `vs_dns_udp` + `vs_dns_tcp` on `10.1.10.200:53` |
| 5. Telemetry | Prometheus pull consumer via TS extension |
| 6. Save | `save sys config` |

**Quick start:**

```bash
# On BIG-IP CLI:
ssh admin@<bigip-mgmt-ip>
bash
# Review the script:
cat infrastructure/scripts/configure-bigip-tmsh.sh
# Then in tmsh, paste the commands from Phases 1-6

# On Docker host:
make connect-bigip
make test-cgnat
```

**CGNAT — Wildcard VS with SNAT pool:**

```
# tmsh
create ltm snatpool snatpool_cgnat {
  members add { 198.51.100.10 198.51.100.11 198.51.100.12 198.51.100.13 }
}
create ltm virtual vs_cgnat {
  destination 0.0.0.0:0
  mask 0.0.0.0
  ip-protocol any
  source 10.45.0.0/16
  profiles add { fastl4_cgnat }
  source-address-translation { type snatpool pool snatpool_cgnat }
  vlans add { vlan_internal }
  vlans-enabled
  translate-address disabled
  translate-port disabled
}
```

**AFM — Gi-LAN Firewall Policy (5 rules):**

| # | Rule | Protocol | Action |
|---|------|----------|--------|
| 1 | `rule_allow_dns` | TCP/UDP port 53 | Accept |
| 2 | `rule_allow_web` | TCP ports 80, 443 | Accept |
| 3 | `rule_allow_icmp` | ICMP | Accept |
| 4 | `rule_allow_ntp` | UDP port 123 | Accept |
| 5 | `rule_deny_all` | Any | Drop + log |

```
# Attach to CGNAT VS:
modify ltm virtual vs_cgnat { fw-enforced-policy policy_gi_lan }
```

**DNS — Subscriber DNS Proxy:**

```
# VS listens on BIG-IP internal IP, proxies to upstream DNS
create ltm virtual vs_dns_udp {
  destination 10.1.10.200:53
  ip-protocol udp
  source 10.45.0.0/16
  profiles add { dns_subscribers udp }
  pool pool_dns_upstream
  source-address-translation { type automap }
}
```

To route UE DNS through BIG-IP, edit `smf.yaml` and change the first DNS
entry from `8.8.8.8` to `10.1.10.200`, then restart: `make restart-5g`.

**SBI API Gateway (HTTP/2 reverse proxy — advanced):**

```
create ltm pool pool_nrf members add { 10.33.33.10:7777 }
create ltm virtual vs_sbi_gateway {
    destination 10.33.33.250:7777
    pool pool_nrf
    profiles add { http2 tcp }
}
```

### 19.5 Telemetry Integration

A commented-out `bigip-gi-lan` scrape job is already in
`monitoring/prometheus/prometheus.yml`. To enable it:

1. Install the **F5 Telemetry Streaming** (TS) RPM on BIG-IP
2. POST the Prometheus pull consumer declaration (see `configure-bigip-tmsh.sh` Phase 5)
3. Uncomment the `bigip-gi-lan` job in `prometheus.yml`:

```yaml
  - job_name: 'bigip-gi-lan'
    scrape_interval: 30s
    metrics_path: '/mgmt/shared/telemetry/pullconsumer/Prometheus_Pull'
    basic_auth:
      username: 'admin'
      password: 'admin'
    tls_config:
      insecure_skip_verify: true
    static_configs:
      - targets: ['10.1.10.200:443']
        labels:
          component: 'bigip'
          role: 'gi-lan'
```

4. Restart monitoring: `make stop-monitoring && make deploy-monitoring`

**Useful BIG-IP metrics in Prometheus:**

| Metric | Description |
|--------|-------------|
| `f5_virtualServer_clientside_curConns` | Active connections through vs_cgnat |
| `f5_virtualServer_clientside_bitsIn` | Throughput into CGNAT VS |
| `f5_snatPool_serverside_curConns` | Active SNAT translations |
| `f5_pool_activeMemberCnt` | DNS upstream pool health |

Alternatives to Telemetry Streaming:
- **prometheus-bigip-exporter** — community Prometheus exporter (iControl REST)
- **BIG-IP AVR** — built-in analytics module

### 19.6 Verifying the Integration

Run the automated test suite:

```bash
make test-cgnat
```

This runs `test-cgnat.sh` which checks 6 phases:

| Phase | What It Verifies |
|-------|-----------------|
| 1. UPF Routing | Default route points at BIG-IP |
| 2. BIG-IP Reachability | Host and UPF can reach BIG-IP |
| 3. UE Connectivity | UEs can ping through BIG-IP CGNAT |
| 4. DNS Resolution | UEs can resolve domains (via BIG-IP if configured) |
| 5. SNAT Verification | UE public IP differs from private (CGNAT active) |
| 6. AFM Validation | Allowed traffic passes; deny counters on BIG-IP |

**Manual verification:**

```bash
# Check UPF route
docker exec upf ip route show default
# → default via 10.1.10.200

# Ping from UE through BIG-IP
docker exec ue ping -I uesimtun0 -c 3 8.8.8.8

# Check SNAT translation (public IP should NOT be 10.45.x.x)
docker exec ue curl -sf --interface uesimtun0 https://ifconfig.me

# On BIG-IP — check CGNAT stats
# tmsh show ltm virtual vs_cgnat
# tmsh show ltm snatpool snatpool_cgnat
# tmsh show security firewall policy policy_gi_lan
```

### 19.7 Future Lab Exercises

The BIG-IP integration enables these planned lab modules:

| Lab | Placement | Skills Practiced |
|-----|-----------|------------------|
| **Lab A: Gi-LAN CGNAT** | N6 inline | SNAT pools, logging, port-block allocation |
| **Lab B: Subscriber-Aware Steering** | N3 GTP | iRules GTP parsing, per-IMSI policy |
| **Lab C: DNS Security** | N6 inline | DNS profile, DDoS mitigation, DoH proxy |
| **Lab D: SBI API Protection** | SBI proxy | HTTP/2 reverse proxy, JWT validation, rate limiting |
| **Lab E: TCP Optimization** | N6 inline | FastL4/Full-proxy profiles, congestion control |
| **Lab F: SSL Visibility** | N6 inline | SSL Orchestrator, decrypt/inspect/re-encrypt |
| **Lab G: N4 PFCP Visibility** | N4 inline | PFCP protocol awareness, session logging |
| **Lab H: Edge / MEC Steering** | N6/N9 | Local breakout, MEC traffic steering via iRules |
| **Lab I: 5G Slice Policy** | SBI + N6 | Per-slice (SST/SD) BIG-IP policy via PCF API |
| **Lab J: Observability** | Mgmt | Telemetry Streaming → Prometheus → Grafana |

### 19.8 IP Address Reservation for BIG-IP

Reserved addresses across SP-Labs networks (not used by any container):

| Network | Reserved IP | BIG-IP Interface |
|---------|------------|-----------------|
| `sp-labs-n6` (10.33.37.0/24) | `10.33.37.200` | Internal (data) |
| `sp-labs-n3` (10.33.35.0/24) | `10.33.35.200` | GTP inspection |
| `sp-labs-sbi` (10.33.33.0/24) | `10.33.33.250` | SBI API proxy |
| `sp-labs-n4` (10.33.36.0/24) | `10.33.36.250` | PFCP proxy |
| `sp-labs-mgmt` (10.33.38.0/24) | `10.33.38.250` | Management (GUI, SSH, iControl) |

> **Note:** These IPs are intentionally left unused in the current deployment
> to avoid conflicts when BIG-IP is introduced.

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
| `make test-5g` | Run 5G E2E validation (6 phases) |
| `make generate-traffic` | Generate sustained 5G traffic for Grafana (default 5 min) |
| `make register-subs` | Register N subscribers in MongoDB (default 10) |
| `make register-multi-ue` | Register subscribers for all UE profiles (basic/power/iot/enterprise) |
| `make deploy-multi-ue` | Deploy profile UE containers + register subscribers |
| `make stop-multi-ue` | Stop profile UE containers (keeps base `ue` running) |
| `make restart-ues` | Restart all UE containers to pick up new subscribers |
| `make generate-multi-traffic` | Generate differentiated traffic from all UE profiles |
| `make ue-status` | Show status of all UE tunnels and subscriber count |
| `make connect-bigip` | Configure N6 routing: UPF → BIG-IP (CGNAT/AFM/DNS) |
| `make disconnect-bigip` | Restore UPF default route to host (bypass BIG-IP) |
| `make test-cgnat` | Test BIG-IP CGNAT/AFM/DNS integration (6-phase) |
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
| `ue-power` | — | `NET_ADMIN` | `/dev/net/tun` | Power user UEs (profile: multi-ue) |
| `ue-iot` | — | `NET_ADMIN` | `/dev/net/tun` | IoT device UEs (profile: multi-ue) |
| `ue-enterprise` | — | `NET_ADMIN` | `/dev/net/tun` | Enterprise UEs (profile: multi-ue) |

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
| `grafana/dashboards/5g-core-dashboard.json` | Grafana | 5G Core Overview dashboard (27 panels) |
| `scripts/test-5g.sh` | Test | 6-phase E2E validation + traffic burst |
| `scripts/generate-traffic.sh` | Test | Sustained 4-phase traffic generator for Grafana |
| `scripts/register-subscribers.sh` | Subscriber | Bulk MongoDB registration with QoS profiles |
| `scripts/register-multi-ue.sh` | Subscriber | Register subscribers for all 4 UE profile groups |
| `scripts/generate-multi-traffic.sh` | Test | Differentiated per-profile traffic generator |
| `scripts/configure-bigip-route.sh` | BIG-IP | Host-side N6 route setup (UPF → BIG-IP) |
| `scripts/test-cgnat.sh` | BIG-IP | 6-phase CGNAT/AFM/DNS integration test |
| `scripts/configure-bigip-tmsh.sh` | BIG-IP | tmsh commands for BIG-IP VLANs/VS/AFM/DNS |

---

> **Questions?** Open an issue in the repo or reach out to the SP Labs team.
>
> **Contributing:** Follow existing config patterns. Run `make test-5g`
> before pushing changes to ensure nothing is broken.

