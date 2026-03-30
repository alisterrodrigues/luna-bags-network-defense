#!/bin/bash
# start_services.sh — start intentionally-insecure services on internal lab hosts
# This is the PRE-FIREWALL state: SSH, telnet, and a backdoor port are all open.
# After firewall_rules.sh runs, port 23 is rejected (Phase 1 host rules) and
# port 4444 is blocked in the router's FORWARD chain (Phase 2).
# Usage: run by docker-compose on host1/host2/host3 (container entrypoint)

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq openssh-server netcat-traditional iproute2 >/dev/null 2>&1

# --- Port 22: SSH ---
mkdir -p /run/sshd /root/.ssh
ssh-keygen -A >/dev/null 2>&1
# Allow root login for the lab (intentionally insecure pre-firewall state)
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null || true
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
/usr/sbin/sshd
echo -e "${GREEN}[+] sshd started (port 22)${NC}"

# --- Port 23: telnet listener (simulated insecure service) ---
# socat/inetd not needed — a persistent nc listener is enough for nmap to see "open"
while true; do nc -l -p 23 </dev/null >/dev/null 2>&1; done &
echo -e "${GREEN}[+] telnet listener started (port 23)${NC}"

# --- Port 4444: simulated command-and-control / backdoor port ---
while true; do nc -l -p 4444 </dev/null >/dev/null 2>&1; done &
echo -e "${GREEN}[+] backdoor listener started (port 4444)${NC}"

echo -e "${GREEN}[+] internal host services up — waiting for firewall task${NC}"
exec tail -f /dev/null
