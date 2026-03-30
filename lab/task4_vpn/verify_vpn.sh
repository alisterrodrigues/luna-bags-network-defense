#!/bin/bash
# verify_vpn.sh — verify WireGuard VPN config and connectivity (Task 4)
# Usage: from lab/: ./task4_vpn/verify_vpn.sh
# Depends on: start_vpn.sh run first, wg0 up on both router and hostA

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

check_pass() { echo -e "${GREEN}PASS${NC} — $1"; PASS=$((PASS+1)); }
check_fail() { echo -e "${RED}FAIL${NC} — $1"; FAIL=$((FAIL+1)); }

TOTAL=6

echo "=== WireGuard VPN Verification ==="

# Test 1 — containers running
echo -e "${YELLOW}[*] Test 1: containers running${NC}"
if docker ps --format '{{.Names}}' | grep -qx 'seed-router' && \
   docker ps --format '{{.Names}}' | grep -qx 'hostA-10.9.0.5'; then
  check_pass "seed-router and hostA-10.9.0.5 are running"
else
  check_fail "Required containers not running"
fi

# Test 2 — wg0.conf exists on router
echo -e "${YELLOW}[*] Test 2: wg0.conf present on router${NC}"
if docker exec seed-router bash -c 'test -f /etc/wireguard/wg0.conf'; then
  check_pass "wg0.conf present on seed-router"
else
  check_fail "wg0.conf missing on seed-router"
fi

# Test 3 — wg0.conf exists on hostA
echo -e "${YELLOW}[*] Test 3: wg0.conf present on hostA${NC}"
if docker exec hostA-10.9.0.5 bash -c 'test -f /etc/wireguard/wg0.conf'; then
  check_pass "wg0.conf present on hostA-10.9.0.5"
else
  check_fail "wg0.conf missing on hostA-10.9.0.5"
fi

# Test 4 — route to internal network exists on hostA
echo -e "${YELLOW}[*] Test 4: route to 192.168.60.0/24 on hostA${NC}"
if docker exec hostA-10.9.0.5 bash -c 'ip route show | grep -q 192.168.60.0/24'; then
  ROUTE=$(docker exec hostA-10.9.0.5 bash -c 'ip route show | grep 192.168.60.0/24')
  check_pass "Route found: $ROUTE"
else
  check_fail "No route to 192.168.60.0/24 on hostA"
fi

# Tests 5-6 — ping internal hosts through VPN from hostA (check 2 of 3)
INT_HOSTS=("192.168.60.5" "192.168.60.6")
for host in "${INT_HOSTS[@]}"; do
  echo -e "${YELLOW}[*] Test: ping ${host} from hostA via VPN${NC}"
  RESULT=$(docker exec hostA-10.9.0.5 bash -c "ping -c 2 -W 3 ${host} 2>&1")
  if echo "$RESULT" | grep -q '0% packet loss'; then
    RTT=$(echo "$RESULT" | grep rtt | awk -F= '{print $2}' | tr -d ' ')
    check_pass "hostA can reach ${host} via VPN (rtt: $RTT)"
  else
    check_fail "hostA cannot reach ${host} via VPN"
  fi
done

TOTAL=$((PASS+FAIL))
echo ""
if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}[+] $PASS/$TOTAL tests passed — VPN is working${NC}"
else
  echo -e "${RED}[-] $PASS/$TOTAL tests passed — check wg0 status with: docker exec seed-router wg show${NC}"
  exit 1
fi
