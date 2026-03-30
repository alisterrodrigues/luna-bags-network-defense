#!/bin/bash
# install_fail2ban.sh — install Fail2Ban on hostA and seed-router (Task 5)
# Usage: from lab/: ./task5_ids/install_fail2ban.sh
# Depends on: docker, both containers up

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOSTA="hostA-10.9.0.5"
ROUTER="seed-router"

FB_INNER='
export DEBIAN_FRONTEND=noninteractive
if ! command -v fail2ban-client >/dev/null 2>&1; then
  apt-get update -qq >/dev/null 2>&1
  if ! apt-get install -y -qq fail2ban >/dev/null 2>&1; then
    echo "[-] apt install fail2ban failed"
    exit 1
  fi
else
  echo "[*] fail2ban already installed"
fi
# create log files fail2ban expects — must exist before server starts or config load fails
mkdir -p /run/fail2ban /var/log/apache2
touch /var/log/auth.log /var/log/apache2/access.log /var/log/apache2/error.log 2>/dev/null || true
if ! fail2ban-client ping >/dev/null 2>&1; then
  fail2ban-server -x >/dev/null 2>&1 || true
  sleep 2
fi
if fail2ban-client ping >/dev/null 2>&1; then
  echo "[+] fail2ban ping OK"
  exit 0
fi
echo "[-] fail2ban not responding"
exit 1
'

echo "Installing Fail2Ban on ${HOSTA}..."
if ! docker ps --format '{{.Names}}' | grep -qx "$HOSTA"; then
  echo -e "${RED}[-] ${HOSTA} not running${NC}"
  exit 1
fi
if docker exec "$HOSTA" bash -c "$FB_INNER"; then
  echo -e "${GREEN}[+] hostA ok${NC}"
else
  echo -e "${RED}[-] hostA failed${NC}"
  exit 1
fi

echo "Installing Fail2Ban on ${ROUTER}..."
if ! docker ps --format '{{.Names}}' | grep -qx "$ROUTER"; then
  echo -e "${RED}[-] ${ROUTER} not running${NC}"
  exit 1
fi
if docker exec "$ROUTER" bash -c "$FB_INNER"; then
  echo -e "${GREEN}[+] router ok${NC}"
else
  echo -e "${RED}[-] router failed${NC}"
  exit 1
fi

echo -e "${YELLOW}[*] next: configure_fail2ban.sh then verify_fail2ban.sh${NC}"
echo -e "${GREEN}[+] done${NC}"
exit 0
