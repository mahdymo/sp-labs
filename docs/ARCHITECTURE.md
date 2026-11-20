# SP-Labs Architecture

## 5G SA Architecture (3GPP Release 16+)

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
                                                    │             │
                                                    │ [Future:    │
                                                    │  F5 BIG-IP] │
                                                    └─────────────┘
```

## 5G Interface Reference

| Interface | Between | Protocol | Purpose |
|-----------|---------|----------|---------|
| N1 | UE ↔ AMF | NAS-5G | Registration, authentication |
| N2 | gNB ↔ AMF | NGAP/SCTP | RAN control plane |
| N3 | gNB ↔ UPF | GTP-U/UDP | User data tunnel |
| N4 | SMF ↔ UPF | PFCP/UDP | Session rules & reporting |
| N6 | UPF ↔ DN | IP | User traffic to data network |
| SBI | NF ↔ NF | HTTP/2 | Service-based interface |

## 6G Research Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    6G Research Stack                     │
│                                                         │
│  ┌─────────────────┐    ┌─────────────────────────────┐ │
│  │  NVIDIA Sionna  │    │      O-RAN Architecture     │ │
│  │  ─────────────  │    │                             │ │
│  │  • 6G PHY Sim   │    │  ┌──────────┐ ┌──────────┐ │ │
│  │  • MIMO/OFDM    │    │  │ Near-RT  │ │ Non-RT   │ │ │
│  │  • Ray Tracing  │    │  │   RIC    │ │   RIC    │ │ │
│  │  • AI/ML Chan.  │    │  │ (xApps)  │ │ (rApps)  │ │ │
│  │  • TensorFlow   │    │  └────┬─────┘ └──────────┘ │ │
│  │  • Jupyter NB   │    │       │ E2                  │ │
│  └─────────────────┘    │  ┌────┴─────┐              │ │
│                         │  │ E2 Node  │              │ │
│  ┌─────────────────┐    │  │ (Sim gNB)│              │ │
│  │    ns-3          │    │  └──────────┘              │ │
│  │  ─────────────  │    └─────────────────────────────┘ │
│  │  • NR Module    │                                    │
│  │  • THz Models   │                                    │
│  │  • mmWave       │                                    │
│  │  • RIS Sim      │                                    │
│  └─────────────────┘                                    │
└─────────────────────────────────────────────────────────┘
```

## Data Flows

### UE Registration Flow
1. UE → gNB: RRC Setup Request
2. gNB → AMF (N2/NGAP): Initial UE Message with NAS Registration Request
3. AMF → AUSF → UDM → UDR (SBI): Authentication vectors
4. AMF → UE: Authentication challenge/response
5. AMF → UDM (SBI): Registration confirmation
6. AMF → gNB → UE: Registration Accept

### PDU Session Establishment
1. UE → AMF (NAS): PDU Session Establishment Request
2. AMF → SMF (SBI): Create SM Context
3. SMF → PCF (SBI): Policy fetch
4. SMF → UPF (N4/PFCP): Session Establishment Request
5. UPF: Creates GTP-U tunnel, allocates UE IP from pool
6. SMF → AMF → gNB → UE: PDU Session Accept with tunnel info

### User Data Path
```
UE → gNB → [N3/GTP-U] → UPF → [N6] → Data Network (Internet)
```
