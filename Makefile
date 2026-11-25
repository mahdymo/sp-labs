# ==============================================================================
# SP-Labs — Top-Level Makefile
# ==============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Load environment variables if .env exists
ifneq (,$(wildcard .env))
  include .env
  export
endif

# --- Colours ---
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
NC     := \033[0m

# ==============================================================================
# HELP
# ==============================================================================
.PHONY: help
help: ## Show this help
	@echo ""
	@echo "  SP-Labs — Service Provider 5G & 6G Lab"
	@echo "  ======================================="
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(NC) %s\n", $$1, $$2}'
	@echo ""

# ==============================================================================
# SETUP
# ==============================================================================
.PHONY: init
init: ## Copy .env.example to .env if not present
	@test -f .env || cp .env.example .env
	@echo -e "$(GREEN)[OK]$(NC) .env ready — edit it for your environment"

# ==============================================================================
# PRE-FLIGHT
# ==============================================================================
.PHONY: preflight
preflight: ## Run pre-flight validation checks
	@bash infrastructure/scripts/preflight-check.sh

.PHONY: setup-ssh
setup-ssh: ## Set up SSH keys for multi-VM deployment
	@bash infrastructure/scripts/setup-ssh-keys.sh

# ==============================================================================
# 5G LAB
# ==============================================================================
.PHONY: deploy-5g
deploy-5g: init ## Deploy 5G lab (Open5GS + UERANSIM)
	@echo -e "$(GREEN)[5G]$(NC) Starting 5G Core and RAN simulator..."
	docker compose -f 5g-lab/docker-compose.yml --env-file .env up -d
	@echo -e "$(GREEN)[5G]$(NC) Waiting for services to be healthy..."
	@sleep 15
	@echo -e "$(GREEN)[5G]$(NC) Registering subscribers (NUM_UES=${NUM_UES:-5})..."
	@bash infrastructure/scripts/register-subscribers.sh ${NUM_UES:-5} || true
	@echo -e "$(GREEN)[5G]$(NC) 5G Lab is UP"

.PHONY: stop-5g
stop-5g: ## Stop 5G lab
	docker compose -f 5g-lab/docker-compose.yml --env-file .env down

.PHONY: restart-5g
restart-5g: stop-5g deploy-5g ## Restart 5G lab

.PHONY: logs-5g
logs-5g: ## Tail 5G lab logs
	docker compose -f 5g-lab/docker-compose.yml logs -f --tail=100

.PHONY: test-5g
test-5g: ## Run 5G end-to-end test
	@bash infrastructure/scripts/test-5g.sh

.PHONY: generate-traffic
generate-traffic: ## Generate 5G traffic for Grafana dashboards (default: 5 min)
	@bash infrastructure/scripts/generate-traffic.sh $(TRAFFIC_DURATION)

# ==============================================================================
# MULTI-UE
# ==============================================================================
.PHONY: register-subs
register-subs: ## Register multiple subscribers in MongoDB (default: 10)
	@bash infrastructure/scripts/register-subscribers.sh $(NUM_SUBS)

.PHONY: register-multi-ue
register-multi-ue: ## Register subscribers for all UE profiles (basic/power/iot/enterprise)
	@bash infrastructure/scripts/register-multi-ue.sh $(NUM_UES)

.PHONY: deploy-multi-ue
deploy-multi-ue: register-multi-ue ## Deploy all UE profile containers + register subscribers
	@echo -e "$(GREEN)[5G]$(NC) Starting multi-UE profile containers..."
	docker compose -f 5g-lab/docker-compose.yml --env-file .env --profile multi-ue up -d
	@echo -e "$(GREEN)[5G]$(NC) Waiting for UE registration..."
	@sleep 20
	@echo -e "$(GREEN)[5G]$(NC) Multi-UE deployment complete"
	@docker compose -f 5g-lab/docker-compose.yml --env-file .env --profile multi-ue ps

.PHONY: stop-multi-ue
stop-multi-ue: ## Stop the profile UE containers (keeps base ue running)
	docker compose -f 5g-lab/docker-compose.yml --env-file .env --profile multi-ue stop ue-power ue-iot ue-enterprise

.PHONY: restart-ues
restart-ues: ## Restart all UE containers (base + profiles) to pick up new subscribers
	docker compose -f 5g-lab/docker-compose.yml --env-file .env restart ue
	docker compose -f 5g-lab/docker-compose.yml --env-file .env --profile multi-ue restart ue-power ue-iot ue-enterprise 2>/dev/null || true
	@echo -e "$(GREEN)[5G]$(NC) UEs restarted — waiting for registration..."
	@sleep 15
	@echo -e "$(GREEN)[5G]$(NC) UEs should be registered now"

.PHONY: generate-multi-traffic
generate-multi-traffic: ## Generate traffic from all UE profiles (default: 5 min)
	@bash infrastructure/scripts/generate-multi-traffic.sh $(TRAFFIC_DURATION)

.PHONY: ue-status
ue-status: ## Show status of all UE tunnels and registrations
	@echo ""
	@echo "==========================================="
	@echo "  SP-Labs — UE Status"
	@echo "==========================================="
	@for c in ue ue-power ue-iot ue-enterprise; do \
	  if docker inspect -f '{{.State.Running}}' $$c 2>/dev/null | grep -q true; then \
	    TUNS=$$(docker exec $$c ip -4 addr show 2>/dev/null | grep -c uesimtun || echo 0); \
	    echo "  ✓ $$c: running, $$TUNS tunnel(s)"; \
	    docker exec $$c ip -4 addr show 2>/dev/null | grep 'inet.*uesimtun' | \
	      sed 's/^/      /' || true; \
	  else \
	    echo "  ✗ $$c: not running"; \
	  fi; \
	done
	@echo ""
	@echo "  Subscribers in MongoDB:"
	@docker exec mongodb mongosh --quiet --eval \
	  "db=db.getSiblingDB('open5gs');print('    Total: '+db.subscribers.countDocuments())" 2>/dev/null || true
	@echo "==========================================="

# ==============================================================================
# BIG-IP INTEGRATION
# ==============================================================================
.PHONY: connect-bigip
connect-bigip: ## Configure N6 routing: UPF → BIG-IP (CGNAT/AFM/DNS)
	@bash infrastructure/scripts/configure-bigip-route.sh

.PHONY: disconnect-bigip
disconnect-bigip: ## Restore UPF default route to host (bypass BIG-IP)
	@echo -e "$(YELLOW)[BIG-IP]$(NC) Restoring host-based routing..."
	@docker exec upf ip route replace default via $$(docker exec upf ip route | grep -oP '10\.33\.37\.\d+' | head -1 || echo "10.33.37.1") 2>/dev/null || true
	@sudo iptables -t nat -C POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE 2>/dev/null || \
	  sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
	@echo -e "$(GREEN)[BIG-IP]$(NC) Host MASQUERADE restored — BIG-IP bypassed"

.PHONY: test-cgnat
test-cgnat: ## Test BIG-IP CGNAT/AFM/DNS integration
	@bash infrastructure/scripts/test-cgnat.sh

# ==============================================================================
# 6G LAB
# ==============================================================================
.PHONY: ensure-mgmt-network
ensure-mgmt-network: ## Ensure the mgmt Docker network exists
	@docker network inspect sp-labs-mgmt >/dev/null 2>&1 || \
	  docker network create --driver bridge --subnet 10.33.38.0/24 sp-labs-mgmt

.PHONY: deploy-6g
deploy-6g: init ensure-mgmt-network ## Deploy 6G lab (Sionna + ns-3 + O-RAN RIC)
	@echo -e "$(GREEN)[6G]$(NC) Starting 6G research environment..."
	@echo -e "$(GREEN)[6G]$(NC) Detecting GPU..."
	@if command -v nvidia-smi >/dev/null 2>&1; then \
	  echo -e "$(GREEN)[6G]$(NC) NVIDIA GPU detected — deploying with GPU profile"; \
	  docker compose -f 6g-lab/docker-compose.yml --env-file .env --profile gpu up -d; \
	else \
	  echo -e "$(YELLOW)[6G]$(NC) No GPU detected — deploying CPU-only profile"; \
	  docker compose -f 6g-lab/docker-compose.yml --env-file .env --profile cpu up -d; \
	fi
	@echo -e "$(GREEN)[6G]$(NC) 6G Lab is UP"

.PHONY: stop-6g
stop-6g: ## Stop 6G lab
	docker compose -f 6g-lab/docker-compose.yml --env-file .env down

.PHONY: logs-6g
logs-6g: ## Tail 6G lab logs
	docker compose -f 6g-lab/docker-compose.yml logs -f --tail=100

.PHONY: test-6g
test-6g: ## Run 6G environment test
	@bash infrastructure/scripts/test-6g.sh

# ==============================================================================
# MONITORING
# ==============================================================================
.PHONY: deploy-monitoring
deploy-monitoring: init ensure-mgmt-network ## Deploy monitoring stack
	@echo -e "$(GREEN)[MON]$(NC) Starting Prometheus + Grafana..."
	docker compose -f monitoring/docker-compose.yml --env-file .env up -d
	@echo -e "$(GREEN)[MON]$(NC) Monitoring is UP"

.PHONY: stop-monitoring
stop-monitoring: ## Stop monitoring stack
	docker compose -f monitoring/docker-compose.yml --env-file .env down

# ==============================================================================
# ALL
# ==============================================================================
.PHONY: deploy-all
deploy-all: deploy-monitoring deploy-5g deploy-6g ## Deploy everything

.PHONY: stop-all
stop-all: stop-6g stop-5g stop-monitoring ## Stop everything

.PHONY: destroy-all
destroy-all: ## Destroy everything including volumes
	docker compose -f 5g-lab/docker-compose.yml --env-file .env down -v
	docker compose -f 6g-lab/docker-compose.yml --env-file .env down -v
	docker compose -f monitoring/docker-compose.yml --env-file .env down -v
	@echo -e "$(RED)[DESTROYED]$(NC) All labs torn down"

.PHONY: status
status: ## Show status of all lab containers
	@echo -e "\n$(YELLOW)=== 5G Lab ===$(NC)"
	@docker compose -f 5g-lab/docker-compose.yml ps 2>/dev/null || echo "  Not deployed"
	@echo -e "\n$(YELLOW)=== 6G Lab ===$(NC)"
	@docker compose -f 6g-lab/docker-compose.yml ps 2>/dev/null || echo "  Not deployed"
	@echo -e "\n$(YELLOW)=== Monitoring ===$(NC)"
	@docker compose -f monitoring/docker-compose.yml ps 2>/dev/null || echo "  Not deployed"

# ==============================================================================
# DOCS
# ==============================================================================
.PHONY: portal
portal: ## Regenerate the interactive architecture portal (docs/portal/index.html)
	@echo -e "$(GREEN)[DOCS]$(NC) Generating architecture portal..."
	@cd docs/portal && node build.js
	@echo -e "$(GREEN)[DOCS]$(NC) Portal ready → docs/portal/index.html"
