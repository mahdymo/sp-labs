# SP-Labs Networking Plan

## Docker Network Topology

All 5G interfaces are mapped to isolated Docker bridge networks to simulate
realistic telco network segmentation.

## Network Definitions

| Network Name | Subnet | Purpose | 5G Interface |
|-------------|--------|---------|--------------|
| `sbi` | 10.33.33.0/24 | Service-Based Interface (inter-NF) | SBI |
| `n2` | 10.33.34.0/24 | gNB ↔ AMF control plane | N2 (NGAP) |
| `n3` | 10.33.35.0/24 | gNB ↔ UPF user plane | N3 (GTP-U) |
| `n4` | 10.33.36.0/24 | SMF ↔ UPF session mgmt | N4 (PFCP) |
| `n6` | 10.33.37.0/24 | UPF ↔ Data Network | N6 (Gi/SGi) |
| `mgmt` | 10.33.38.0/24 | Management & monitoring | — |

## Container IP Assignments

### 5G Core (Open5GS)

| Container | sbi | n2 | n3 | n4 | n6 | mgmt |
|-----------|-----|----|----|----|----|------|
| mongodb | 10.33.33.2 | — | — | — | — | — |
| nrf | 10.33.33.10 | — | — | — | — | 10.33.38.10 |
| scp | 10.33.33.11 | — | — | — | — | — |
| amf | 10.33.33.12 | 10.33.34.12 | — | — | — | 10.33.38.12 |
| smf | 10.33.33.13 | — | — | 10.33.36.13 | — | 10.33.38.13 |
| upf | — | — | 10.33.35.14 | 10.33.36.14 | 10.33.37.14 | 10.33.38.14 |
| ausf | 10.33.33.15 | — | — | — | — | — |
| udm | 10.33.33.16 | — | — | — | — | — |
| udr | 10.33.33.17 | — | — | — | — | — |
| pcf | 10.33.33.18 | — | — | — | — | — |
| nssf | 10.33.33.19 | — | — | — | — | — |
| bsf | 10.33.33.20 | — | — | — | — | — |
| webui | 10.33.33.21 | — | — | — | — | 10.33.38.21 |

### UERANSIM

| Container | n2 | n3 | mgmt |
|-----------|----|----|------|
| gnb | 10.33.34.100 | 10.33.35.100 | 10.33.38.100 |
| ue | — | — | 10.33.38.101 |

### Monitoring

| Container | mgmt |
|-----------|------|
| prometheus | 10.33.38.200 |
| grafana | 10.33.38.201 |
| node-exporter | 10.33.38.202 |

## UE IP Pool

| Parameter | Value |
|-----------|-------|
| Pool Subnet | 10.45.0.0/16 |
| First UE IP | 10.45.0.2 |
| Gateway | 10.45.0.1 |
| DNS | 8.8.8.8, 8.8.4.4 |

## Port Mappings (Host Exposure)

| Service | Container Port | Host Port | Protocol |
|---------|---------------|-----------|----------|
| Open5GS WebUI | 9999 | 9999 | TCP |
| AMF NGAP | 38412 | 38412 | SCTP |
| UPF GTP-U | 2152 | — | UDP (internal) |
| Prometheus | 9090 | 9090 | TCP |
| Grafana | 3000 | 3000 | TCP |
| Node Exporter | 9100 | 9100 | TCP |
| Sionna Jupyter | 8888 | 8888 | TCP |

## Firewall / iptables

The bootstrap script configures:

```bash
# Enable IP forwarding (required for UPF NAT)
sysctl -w net.ipv4.ip_forward=1

# NAT for UE traffic exiting via UPF
iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
iptables -A FORWARD -i ogstun -o eth0 -j ACCEPT
iptables -A FORWARD -o ogstun -i eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
```
