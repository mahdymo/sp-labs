#!/usr/bin/env bash
# ==============================================================================
# SP-Labs — BIG-IP tmsh Configuration Script
#
# Run this DIRECTLY ON the BIG-IP CLI (bash shell, then tmsh).
# It configures BIG-IP as a Gi-LAN service node providing:
#   - CGNAT (carrier-grade NAT with SNAT pool)
#   - AFM (Advanced Firewall Manager with Gi-LAN policy)
#   - DNS transparent proxy for subscriber queries
#   - Telemetry Streaming for Prometheus metrics
#
# Prerequisites:
#   - BIG-IP VE 15.1+ with LTM, AFM, and DNS modules provisioned
#   - Management IP configured and SSH accessible
#   - Internal VLAN connected to Docker host (10.1.10.0/24 transit)
#   - External VLAN connected to internet uplink
#
# Usage:
#   ssh admin@<bigip-mgmt-ip>
#   bash
#   # paste sections below into tmsh, or:
#   tmsh -c "$(cat configure-bigip-tmsh.sh)"
#
# Variables — adjust to your environment:
#   INTERNAL_VLAN_TAG  : VLAN tag for internal (subscriber-side) interface
#   EXTERNAL_VLAN_TAG  : VLAN tag for external (internet-side) interface
#   INTERNAL_IFACE     : Physical interface for internal VLAN (e.g., 1.1)
#   EXTERNAL_IFACE     : Physical interface for external VLAN (e.g., 1.2)
#   BIGIP_INTERNAL_IP  : Self-IP on internal VLAN (transit to Docker host)
#   BIGIP_EXTERNAL_IP  : Self-IP on external VLAN (internet-facing)
#   HOST_N6_GW         : Docker host IP on N6 bridge (return route target)
# ==============================================================================

cat << 'TMSH_CONFIG'
# ==============================================================================
# PHASE 1: Network — VLANs, Self-IPs, Routes
# ==============================================================================

# --- Internal VLAN (subscriber-side, toward Docker host / UPF) ---
create net vlan vlan_internal { tag 10 interfaces add { 1.1 { untagged } } }

# --- External VLAN (internet-side) ---
create net vlan vlan_external { tag 20 interfaces add { 1.2 { untagged } } }

# --- Self-IPs ---
create net self self_internal {
  address 10.1.10.200/24
  vlan vlan_internal
  allow-service { default }
}
create net self self_external {
  address 198.51.100.200/24
  vlan vlan_external
  allow-service { default }
}

# --- Return routes to UE pool and lab N6 subnet via Docker host ---
create net route ue_pool    { network 10.45.0.0/16  gw 10.33.37.1 }
create net route lab_n6     { network 10.33.37.0/24  gw 10.33.37.1 }
create net route default_gw { network default        gw 198.51.100.1 }

# ==============================================================================
# PHASE 2: CGNAT — SNAT Pool + Wildcard Virtual Server
# ==============================================================================

# --- SNAT pool for CGNAT (adjust IPs to your external allocation) ---
create ltm snatpool snatpool_cgnat {
  members add { 198.51.100.10 198.51.100.11 198.51.100.12 198.51.100.13 }
}

# --- FastL4 wildcard VS that SNATs all subscriber traffic ---
create ltm profile fastl4 fastl4_cgnat {
  defaults-from fastL4
  idle-timeout 300
  loose-close enabled
  loose-initialization enabled
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

# ==============================================================================
# PHASE 3: AFM — Gi-LAN Firewall Policy
# ==============================================================================

# --- Address lists ---
create security firewall address-list addr_ue_pool {
  addresses add { 10.45.0.0/16 }
}
create security firewall address-list addr_dns_servers {
  addresses add { 8.8.8.8 8.8.4.4 1.1.1.1 }
}

# --- Port lists ---
create security firewall port-list ports_web { ports add { 80 443 } }
create security firewall port-list ports_dns { ports add { 53 } }

# --- Gi-LAN firewall policy (5 rules) ---
create security firewall policy policy_gi_lan {
  rules add {
    rule_allow_dns {
      action accept
      ip-protocol tcp-udp
      source { address-lists add { addr_ue_pool } }
      destination { port-lists add { ports_dns } }
      place-before first
    }
    rule_allow_web {
      action accept
      ip-protocol tcp
      source { address-lists add { addr_ue_pool } }
      destination { port-lists add { ports_web } }
    }
    rule_allow_icmp {
      action accept
      ip-protocol icmp
      source { address-lists add { addr_ue_pool } }
    }
    rule_allow_ntp {
      action accept
      ip-protocol udp
      source { address-lists add { addr_ue_pool } }
      destination { ports add { 123 } }
    }
    rule_deny_all {
      action drop
      log yes
      source { address-lists add { addr_ue_pool } }
      place-after last
    }
  }
}

# Attach AFM policy to CGNAT VS
modify ltm virtual vs_cgnat { fw-enforced-policy policy_gi_lan }


# ==============================================================================
# PHASE 4: DNS — Transparent Subscriber DNS Proxy
# ==============================================================================

create ltm profile dns dns_subscribers {
  defaults-from dns
  enable-dns-express no
  enable-dnssec no
  enable-logging yes
  use-local-bind no
}
create ltm pool pool_dns_upstream {
  members add {
    8.8.8.8:53 { address 8.8.8.8 }
    8.8.4.4:53 { address 8.8.4.4 }
  }
  monitor gateway_icmp
}
create ltm virtual vs_dns_udp {
  destination 10.1.10.200:53
  ip-protocol udp
  source 10.45.0.0/16
  profiles add { dns_subscribers udp }
  pool pool_dns_upstream
  source-address-translation { type automap }
  vlans add { vlan_internal }
  vlans-enabled
}
create ltm virtual vs_dns_tcp {
  destination 10.1.10.200:53
  ip-protocol tcp
  source 10.45.0.0/16
  profiles add { dns_subscribers tcp }
  pool pool_dns_upstream
  source-address-translation { type automap }
  vlans add { vlan_internal }
  vlans-enabled
}


# ==============================================================================
# PHASE 5: Telemetry Streaming (Prometheus)
# ==============================================================================
# Install TS RPM first, then POST declaration to
# /mgmt/shared/telemetry/declare with Prometheus_Pull_Consumer config.
# See docs/LAB_GUIDE.md §19.5 for the full JSON declaration.

# ==============================================================================
# PHASE 6: Save
# ==============================================================================
save sys config

TMSH_CONFIG

echo ""
echo "============================================================"
echo "  Copy the tmsh commands above and paste into BIG-IP CLI:"
echo "    ssh admin@<bigip-mgmt-ip>"
echo "    tmsh"
echo "    <paste commands>"
echo ""
echo "  Then on the Docker host:"
echo "    make connect-bigip"
echo "    make test-cgnat"
echo "============================================================"

