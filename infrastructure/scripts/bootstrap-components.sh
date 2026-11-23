#!/usr/bin/env bash
# ==============================================================================
# SP-Labs Bootstrap — Component-specific setup
# Sourced by bootstrap.sh (inherits INSTALL_5G, INSTALL_6G, INSTALL_MONITOR)
# ==============================================================================

# --- 5G Lab: Pull images ---
if $INSTALL_5G; then
  log "Pulling 5G lab Docker images..."
  docker pull mongo:6.0
  docker pull openverso/open5gs:2.7.0
  docker pull openverso/ueransim:3.2.6
  log "5G images ready"
fi

# --- 6G Lab: GPU check + image builds ---
if $INSTALL_6G; then
  log "Preparing 6G lab..."

  if lspci | grep -qi nvidia; then
    log "NVIDIA GPU detected"
    if ! command -v nvidia-smi &>/dev/null; then
      warn "NVIDIA drivers not installed. Install them first:"
      warn "  sudo apt install nvidia-driver-535 && sudo reboot"
    fi
    if ! dpkg -l | grep -q nvidia-container-toolkit; then
      log "Installing NVIDIA Container Toolkit..."
      curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
      curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
      apt-get update -qq
      apt-get install -y -qq nvidia-container-toolkit
      nvidia-ctk runtime configure --runtime=docker
      systemctl restart docker
      log "NVIDIA Container Toolkit installed"
    fi
  else
    warn "No NVIDIA GPU detected — Sionna will use CPU-only mode"
    warn "  Use: docker compose --profile cpu up sionna-cpu"
  fi

  log "Building 6G lab images (ns-3 build takes ~20 min on first run)..."
  cd "${REPO_ROOT}/6g-lab"
  docker compose build ns3 || warn "ns-3 build deferred — run 'make deploy-6g' later"
  cd "${REPO_ROOT}"
  log "6G lab preparation complete"
fi

# --- Monitoring: Pull images ---
if $INSTALL_MONITOR; then
  log "Pulling monitoring stack images..."
  docker pull prom/prometheus:v2.55.0
  docker pull grafana/grafana:11.3.0
  docker pull prom/node-exporter:v1.8.2
  log "Monitoring images ready"
fi
