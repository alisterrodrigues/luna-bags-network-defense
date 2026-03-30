#!/bin/bash
# comprehensive_scan.sh — nmap the lab subnets, save before/after, print clean comparison
# Usage: ./comprehensive_scan.sh before | after
# Depends on: docker, seed-router running

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SHARED="${SCRIPT_DIR}/../shared"
ROUTER="seed-router"
TARGETS="10.9.0.0/24 192.168.60.0/24"
PORTS="22,23,80,443,4444,51820"
BEFORE_FILE="${SHARED}/nmap_lab_before.grep"
AFTER_FILE="${SHARED}/nmap_lab_after.grep"

# Only show these lab hosts in the summary — ignore broadcast, gateway, docker bridge IPs
LAB_HOSTS=("10.9.0.5" "10.9.0.11" "192.168.60.5" "192.168.60.6" "192.168.60.7" "192.168.60.11")

mkdir -p "$SHARED"

MODE="${1:-}"

if [[ -z "$MODE" ]]; then
  echo "Usage: $0 before | after"
  exit 1
fi

run_scan() {
  local outfile="$1"
  # install nmap on router if needed
  docker exec "$ROUTER" bash -c '
    export DEBIAN_FRONTEND=noninteractive
    command -v nmap >/dev/null 2>&1 || apt-get install -y -qq nmap >/dev/null 2>&1
  ' >/dev/null 2>&1
  local tmp
  tmp=$(mktemp)
  if docker exec "$ROUTER" bash -c "nmap -Pn -sT -p '${PORTS}' -oG - ${TARGETS} 2>/dev/null" > "$tmp"; then
    cp "$tmp" "$outfile"
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

print_table() {
  local file="$1"
  local label="$2"
  echo -e "${CYAN}${label}${NC}"
  printf '%-16s | %-7s | %s\n' "Host" "Port" "State"
  echo "-----------------------------------"
  for host in "${LAB_HOSTS[@]}"; do
    local line
    line=$(grep "^Host: ${host} .*Ports:" "$file" 2>/dev/null | head -1)
    if [[ -z "$line" ]]; then
      printf '%-16s | %-7s | %s\n' "$host" "-" "no response"
      continue
    fi
    local ports_part
    ports_part=$(echo "$line" | sed 's/.*Ports: //')
    if [[ -z "$ports_part" ]] || [[ "$ports_part" == "$line" ]]; then
      printf '%-16s | %-7s | %s\n' "$host" "-" "no open ports"
      continue
    fi
    IFS=',' read -ra chunks <<< "$ports_part"
    for chunk in "${chunks[@]}"; do
      chunk=$(echo "$chunk" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [[ -z "$chunk" ]] && continue
      local port state
      port=$(echo "$chunk" | awk -F'/' '{print $1}')
      state=$(echo "$chunk" | awk -F'/' '{print $2}')
      # color code by state
      case "$state" in
        open)     printf '%-16s | %-7s | ' "$host" "$port"; echo -e "${GREEN}${state}${NC}" ;;
        filtered) printf '%-16s | %-7s | ' "$host" "$port"; echo -e "${YELLOW}${state}${NC}" ;;
        closed)   printf '%-16s | %-7s | ' "$host" "$port"; echo -e "${RED}${state}${NC}" ;;
        *)        printf '%-16s | %-7s | %s\n' "$host" "$port" "$state" ;;
      esac
    done
  done
  echo ""
}

if [[ "$MODE" == "before" ]]; then
  echo "Running baseline scan (before firewall rules)..."
  echo -e "${YELLOW}[*] scanning ports ${PORTS} on both subnets — this takes ~30s${NC}"
  if run_scan "$BEFORE_FILE"; then
    echo -e "${GREEN}[+] baseline saved to ${BEFORE_FILE}${NC}"
    echo ""
    print_table "$BEFORE_FILE" "=== BASELINE (before) ==="
    echo -e "${YELLOW}[*] run firewall_rules.sh then: $0 after${NC}"
  else
    echo -e "${RED}[-] scan failed${NC}"
    exit 1
  fi
  exit 0
fi

if [[ "$MODE" == "after" ]]; then
  if [[ ! -f "$BEFORE_FILE" ]]; then
    echo -e "${RED}[-] no baseline found — run: $0 before${NC}"
    exit 1
  fi
  echo "Running post-firewall scan..."
  echo -e "${YELLOW}[*] scanning ports ${PORTS} on both subnets — this takes ~30s${NC}"
  if ! run_scan "$AFTER_FILE"; then
    echo -e "${RED}[-] scan failed${NC}"
    exit 1
  fi
  echo -e "${GREEN}[+] after scan saved to ${AFTER_FILE}${NC}"
  echo ""

  print_table "$BEFORE_FILE" "=== BASELINE (before firewall) ==="
  print_table "$AFTER_FILE"  "=== RESULT   (after firewall)  ==="

  # state-change summary — only show hosts where something changed
  echo -e "${CYAN}=== Changes (open -> filtered/closed = firewall working) ===${NC}"
  local_changed=0
  for host in "${LAB_HOSTS[@]}"; do
    before_line=$(grep "^Host: ${host} .*Ports:" "$BEFORE_FILE" 2>/dev/null | head -1)
    after_line=$(grep "^Host: ${host} .*Ports:" "$AFTER_FILE" 2>/dev/null | head -1)
    [[ -z "$before_line" ]] && continue
    IFS=',' read -ra chunks <<< "$(echo "$before_line" | sed 's/.*Ports: //')"
    for chunk in "${chunks[@]}"; do
      chunk=$(echo "$chunk" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [[ -z "$chunk" ]] && continue
      port=$(echo "$chunk" | awk -F'/' '{print $1}')
      state_b=$(echo "$chunk" | awk -F'/' '{print $2}')
      # find same port in after
      state_a="not found"
      IFS=',' read -ra chunks2 <<< "$(echo "$after_line" | sed 's/.*Ports: //')"
      for c2 in "${chunks2[@]}"; do
        c2=$(echo "$c2" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        p2=$(echo "$c2" | awk -F'/' '{print $1}')
        if [[ "$p2" == "$port" ]]; then
          state_a=$(echo "$c2" | awk -F'/' '{print $2}')
          break
        fi
      done
      if [[ "$state_b" != "$state_a" ]]; then
        case "$state_a" in
          filtered|closed) printf '%-16s port %-7s %s -> ' "$host" "$port" "$state_b"; echo -e "${GREEN}${state_a}${NC}" ;;
          open)            printf '%-16s port %-7s %s -> ' "$host" "$port" "$state_b"; echo -e "${RED}${state_a}${NC}" ;;
          *)               printf '%-16s port %-7s %s -> %s\n' "$host" "$port" "$state_b" "$state_a" ;;
        esac
        local_changed=$((local_changed+1))
      fi
    done
  done
  if [[ "$local_changed" -eq 0 ]]; then
    echo "  no state changes detected between scans"
  fi
  echo ""
  echo -e "${YELLOW}[*] full scan output saved: ${BEFORE_FILE} and ${AFTER_FILE}${NC}"
  exit 0
fi

echo "Usage: $0 before | after"
exit 1
