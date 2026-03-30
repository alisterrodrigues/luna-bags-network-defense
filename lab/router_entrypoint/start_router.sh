#!/bin/bash
# start_router.sh — install tools, turn on IP forwarding, keep seed-router alive
# Usage: run by docker-compose on seed-router
# Depends on: Ubuntu 22.04, apt

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Installing curl, openssl, iproute2, iptables, ping, etc..."
export DEBIAN_FRONTEND=noninteractive
if ! apt-get update -qq; then
  echo -e "${RED}[-] apt-get update failed${NC}"
  exit 1
fi
if ! apt-get install -y -qq curl openssl iproute2 iptables iputils-ping ca-certificates procps net-tools; then
  echo -e "${RED}[-] apt-get install failed${NC}"
  exit 1
fi
echo -e "${GREEN}[+] packages installed${NC}"

echo "Enabling IPv4 forwarding..."
if ! sysctl -w net.ipv4.ip_forward=1 >/dev/null; then
  echo -e "${RED}[-] sysctl failed${NC}"
  exit 1
fi
echo -e "${GREEN}[+] net.ipv4.ip_forward=1${NC}"

echo -e "${YELLOW}[*] router idle (tail -f /dev/null)${NC}"
echo -e "${GREEN}[+] entrypoint done${NC}"
exec tail -f /dev/null
