#!/usr/bin/env bash
# ==============================================================================
# SP-Labs — Pre-Flight Remote VM Checks (sourced by preflight-check.sh)
# ==============================================================================

run_remote_checks() {
  echo -e "\n${YELLOW}[4/5] Remote VM Connectivity & Resources${NC}"

  # Collect VM IPs from inventory
  VM_ENTRIES=()
  if [[ -f "${INVENTORY}" ]]; then
    while IFS= read -r line; do
      if [[ "$line" =~ ^[^#].*ansible_host=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
        ip="${BASH_REMATCH[1]}"
        host=$(echo "$line" | awk '{print $1}')
        VM_ENTRIES+=("${host}:${ip}")
      fi
    done < "${INVENTORY}"
  fi

  if [[ ${#VM_ENTRIES[@]} -eq 0 ]]; then
    echo -e "  ${YELLOW}⚠${NC} No remote VMs in inventory (single-host mode)"
    ((WARN++))
    return
  fi

  # Minimum requirements per role
  declare -A MIN_C=( [vm-5g-core]=4 [vm-ran-sim]=2 [vm-sionna]=8 [vm-ns3]=4 [vm-oran]=4 [vm-monitor]=2 )
  declare -A MIN_R=( [vm-5g-core]=7 [vm-ran-sim]=3 [vm-sionna]=30 [vm-ns3]=14 [vm-oran]=7 [vm-monitor]=3 )

  for entry in "${VM_ENTRIES[@]}"; do
    host="${entry%%:*}"
    ip="${entry##*:}"

    # Ping
    check "${host} (${ip}) responds to ping" \
      "ping -c 1 -W 3 ${ip}"

    # SSH
    if [[ -f "${SSH_KEY}" ]]; then
      if ssh -i "${SSH_KEY}" -p "${SSH_PORT}" \
           -o StrictHostKeyChecking=no -o BatchMode=yes \
           -o ConnectTimeout=5 "${SSH_USER}@${ip}" "echo ok" &>/dev/null; then
        check "${host} SSH accessible" "true"

        # Get resources
        INFO=$(ssh -i "${SSH_KEY}" -p "${SSH_PORT}" \
          -o StrictHostKeyChecking=no -o BatchMode=yes \
          -o ConnectTimeout=5 "${SSH_USER}@${ip}" \
          "echo C:\$(nproc) R:\$(awk '/MemTotal/{print int(\$2/1024/1024)}' /proc/meminfo)" 2>/dev/null || echo "")

        if [[ -n "$INFO" ]]; then
          CPUS=$(echo "$INFO" | grep -oP 'C:\K\d+' || echo 0)
          RAM=$(echo "$INFO" | grep -oP 'R:\K\d+' || echo 0)
          MC="${MIN_C[$host]:-2}"
          MR="${MIN_R[$host]:-3}"

          if [[ $CPUS -ge $MC && $RAM -ge $MR ]]; then
            check "${host}: ${CPUS} vCPUs, ${RAM} GB RAM — meets minimum" "true"
          else
            echo -e "  ${RED}✗${NC} ${host}: ${CPUS} vCPUs, ${RAM} GB RAM (need ≥${MC} vCPUs, ≥${MR} GB)"
            ((FAIL++))
          fi

          # Check OS
          check_warn "${host} runs Ubuntu 22.04/24.04" \
            "ssh -i ${SSH_KEY} -p ${SSH_PORT} -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 ${SSH_USER}@${ip} 'grep -qE \"22\\.04|24\\.04\" /etc/os-release'"

          # Check sudo
          check "${host} has sudo access" \
            "ssh -i ${SSH_KEY} -p ${SSH_PORT} -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 ${SSH_USER}@${ip} 'sudo -n true'"
        fi
      else
        echo -e "  ${RED}✗${NC} ${host} SSH accessible"
        ((FAIL++))
      fi
    else
      echo -e "  ${YELLOW}⚠${NC} ${host} — skipped (no SSH key)"
      ((WARN++))
    fi
  done
}
