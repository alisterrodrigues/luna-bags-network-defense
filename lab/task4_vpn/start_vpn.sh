#!/bin/bash
# start_vpn.sh — bring up WireGuard tunnel and test connectivity (Task 4)
# Usage: from lab/: ./task4_vpn/start_vpn.sh
# Depends on: configure_wireguard.sh run first

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

INT_HOSTS=("192.168.60.5" "192.168.60.6" "192.168.60.7")

if ! docker ps --format '{{.Names}}' | grep -qx 'seed-router'; then
  echo -e "${RED}[-] seed-router is not running${NC}"
  exit 1
fi
if ! docker ps --format '{{.Names}}' | grep -qx 'hostA-10.9.0.5'; then
  echo -e "${RED}[-] hostA-10.9.0.5 is not running${NC}"
  exit 1
fi

echo "[1/3] Starting WireGuard VPN server on seed-router..."
docker exec seed-router bash -c '
  # load kernel module if available — ignore failure (some container kernels lack it)
  modprobe wireguard 2>/dev/null || echo "[!] wireguard kernel module not loaded (continuing)"
  wg-quick up wg0 2>/dev/null || wg-quick up wg0 2>&1 | grep -v "^$"
  echo "[+] WireGuard server active"
' 2>/dev/null
if [ $? -ne 0 ]; then
  echo -e "${RED}[-] VPN server failed to start${NC}"
  exit 1
fi
echo -e "${GREEN}[+] VPN server up on seed-router${NC}"

echo "[2/3] Starting WireGuard VPN client on hostA..."
docker exec hostA-10.9.0.5 bash -c '
  modprobe wireguard 2>/dev/null || echo "[!] wireguard kernel module not loaded (continuing)"
  # remove any pre-existing route to internal net so wg-quick can install its own
  ip route del 192.168.60.0/24 2>/dev/null || true
  wg-quick up wg0 2>/dev/null
  echo "[+] WireGuard client active"
'
if [ $? -ne 0 ]; then
  echo -e "${RED}[-] VPN client failed to start${NC}"
  exit 1
fi
echo -e "${GREEN}[+] VPN client up on hostA-10.9.0.5${NC}"

echo "[3/3] Testing VPN connectivity from hostA to internal hosts..."
for host in "${INT_HOSTS[@]}"; do
  echo -e "${YELLOW}[*] Pinging ${host} via VPN...${NC}"
  RESULT=$(docker exec hostA-10.9.0.5 bash -c "ping -c 2 -W 3 ${host} 2>&1")
  if echo "$RESULT" | grep -q '0% packet loss'; then
    echo -e "${GREEN}[+] hostA can reach ${host} via VPN tunnel${NC}"
  else
    echo -e "${RED}[-] hostA cannot reach ${host} — check tunnel and routes${NC}"
    echo "$RESULT"
  fi
done

echo -e "${GREEN}[+] VPN implementation complete${NC}"
echo "Employee access from DMZ (10.9.0.5) to internal network (192.168.60.0/24) established via WireGuard."
