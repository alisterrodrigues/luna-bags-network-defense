#!/bin/bash
# install_wireguard.sh — install WireGuard on seed-router and hostA (Task 4)
# Usage: from lab/: ./task4_vpn/install_wireguard.sh
# Depends on: stack running (docker compose up -d)

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

if ! docker ps --format '{{.Names}}' | grep -qx 'seed-router'; then
  echo -e "${RED}[-] seed-router is not running${NC}"
  exit 1
fi
if ! docker ps --format '{{.Names}}' | grep -qx 'hostA-10.9.0.5'; then
  echo -e "${RED}[-] hostA-10.9.0.5 is not running${NC}"
  exit 1
fi

echo "[1/2] Installing WireGuard on seed-router..."
docker exec seed-router bash -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null 2>&1
  apt-get install -y -qq wireguard wireguard-tools iproute2 >/dev/null 2>&1
  # enable ip forwarding so the router can route VPN traffic to the internal network
  echo 1 > /proc/sys/net/ipv4/ip_forward
  echo "[+] WireGuard installed on router"
'
if [ $? -ne 0 ]; then
  echo -e "${RED}[-] WireGuard install failed on seed-router${NC}"
  exit 1
fi
echo -e "${GREEN}[+] WireGuard ready on seed-router${NC}"

echo "[2/2] Installing WireGuard on hostA..."
docker exec hostA-10.9.0.5 bash -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null 2>&1
  apt-get install -y -qq wireguard wireguard-tools iproute2 >/dev/null 2>&1
  echo "[+] WireGuard installed on hostA"
'
if [ $? -ne 0 ]; then
  echo -e "${RED}[-] WireGuard install failed on hostA-10.9.0.5${NC}"
  exit 1
fi
echo -e "${GREEN}[+] WireGuard ready on hostA-10.9.0.5${NC}"

echo -e "${GREEN}[+] Done — run configure_wireguard.sh next${NC}"
