#!/bin/bash
# configure_fail2ban.sh — write jail.local on hostA and router, restart fail2ban
# Usage: from lab/: ./task5_ids/configure_fail2ban.sh (after install_fail2ban.sh)
# Depends on: docker, install_fail2ban.sh done

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOSTA="hostA-10.9.0.5"
ROUTER="seed-router"

JAIL_LOCAL_BODY='# Luna Bags fail2ban jails

[DEFAULT]
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port    = ssh
logpath = /var/log/auth.log
backend = auto
maxretry = 3
findtime = 60
bantime  = 300

[apache-auth]
enabled = true
port    = http,https
logpath = /var/log/apache2/error.log
maxretry = 5
findtime = 60
bantime  = 600

[apache-badbots]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/access.log
filter   = apache-badbots
maxretry = 1
findtime = 3600
bantime  = 86400

[apache-noscript]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/access.log
filter   = apache-noscript
maxretry = 5
findtime = 60
bantime  = 300
'

RESTART_PART='
# reload if already running, else start fresh
if fail2ban-client ping >/dev/null 2>&1; then
  fail2ban-client reload >/dev/null 2>&1 || true
else
  mkdir -p /run/fail2ban
  fail2ban-server -x >/dev/null 2>&1 || true
  sleep 2
fi
if ! fail2ban-client ping >/dev/null 2>&1; then
  echo "[-] fail2ban not up after restart"
  exit 1
fi
exit 0
'

echo "Writing jail.local on ${HOSTA}..."
if ! docker ps --format '{{.Names}}' | grep -qx "$HOSTA"; then
  echo -e "${RED}[-] ${HOSTA} not running${NC}"
  exit 1
fi
if ! docker exec "$HOSTA" env JAIL_LOCAL_BODY="$JAIL_LOCAL_BODY" bash -c '
printf "%s\n" "$JAIL_LOCAL_BODY" > /etc/fail2ban/jail.local
chmod 644 /etc/fail2ban/jail.local
# extend badbots to include nikto scanner
cat > /etc/fail2ban/filter.d/apache-badbots.local << "FILTEREOF"
[Definition]
badbotscustom = nikto|EmailCollector|WebEMailExtrac|TrackBack/1\.02|sogou music spider|(?:Mozilla/\d+\.\d+ )?Jorgee
FILTEREOF
mkdir -p /var/log/apache2
touch /var/log/apache2/access.log /var/log/apache2/error.log 2>/dev/null || true
touch /var/log/auth.log 2>/dev/null || true
'"$RESTART_PART"; then
  echo -e "${RED}[-] hostA configure failed${NC}"
  exit 1
fi
echo -e "${GREEN}[+] hostA done${NC}"

echo "Writing jail.local on ${ROUTER}..."
if ! docker ps --format '{{.Names}}' | grep -qx "$ROUTER"; then
  echo -e "${RED}[-] ${ROUTER} not running${NC}"
  exit 1
fi
if ! docker exec "$ROUTER" env JAIL_LOCAL_BODY="$JAIL_LOCAL_BODY" bash -c '
printf "%s\n" "$JAIL_LOCAL_BODY" > /etc/fail2ban/jail.local
chmod 644 /etc/fail2ban/jail.local
cat > /etc/fail2ban/filter.d/apache-badbots.local << "FILTEREOF"
[Definition]
badbotscustom = nikto|EmailCollector|WebEMailExtrac|TrackBack/1\.02|sogou music spider|(?:Mozilla/\d+\.\d+ )?Jorgee
FILTEREOF
mkdir -p /var/log/apache2
touch /var/log/apache2/access.log /var/log/apache2/error.log
chmod 644 /var/log/apache2/access.log /var/log/apache2/error.log
touch /var/log/auth.log 2>/dev/null || true
'"$RESTART_PART"; then
  echo -e "${RED}[-] router configure failed${NC}"
  exit 1
fi
echo -e "${GREEN}[+] router done${NC}"

echo -e "${YELLOW}[*] fail2ban restarted on both${NC}"
echo -e "${GREEN}[+] done${NC}"
exit 0
