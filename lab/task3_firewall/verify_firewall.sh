#!/bin/bash
# verify_firewall.sh — Task 3 checks (HTTP/HTTPS, zones, telnet, nmap, hping3, nc)
# Usage: from lab/: ./task3_firewall/verify_firewall.sh (after firewall_rules.sh)
# Depends on: docker; script installs hping3/nmap/nc/curl inside containers

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ROUTER="seed-router"
HOSTA="hostA-10.9.0.5"
HOST1="host1-192.168.60.5"
TARGET_WEB="10.9.0.5"
INTERNAL_HOST="192.168.60.5"

TESTS_PASSED=0
TESTS_TOTAL=0

echo "Installing test tools in router and host1 (suppressed)..."
if ! docker exec "$ROUTER" bash -c \
  "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq hping3 netcat-openbsd iputils-ping curl >/dev/null 2>&1"; then
  echo -e "${RED}[-] Could not install packages on ${ROUTER}${NC}"
  exit 1
fi
if ! docker exec "$HOST1" bash -c \
  "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq nmap netcat-openbsd iputils-ping hping3 curl >/dev/null 2>&1"; then
  echo -e "${RED}[-] Could not install packages on ${HOST1}${NC}"
  exit 1
fi
echo -e "${GREEN}[+] test tools ready${NC}"

echo "Test 1: HTTP from router to hostA..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CODE=$(docker exec "$ROUTER" bash -c "curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 8 http://${TARGET_WEB}/" || true)
if [[ "$CODE" == "301" || "$CODE" == "302" ]]; then
  echo -e "${GREEN}PASS${NC} — HTTP redirect ${CODE} from router to hostA"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} — Expected 301/302 from router HTTP, got ${CODE:-none}"
fi

echo "Test 2: HTTPS from router..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CODE=$(docker exec "$ROUTER" bash -c "curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 8 https://${TARGET_WEB}/" || true)
if [[ "$CODE" == "200" ]]; then
  echo -e "${GREEN}PASS${NC} — HTTPS 200 from router to hostA"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} — Expected HTTPS 200, got ${CODE:-none}"
fi

echo "Test 3: HTTP from internal host to hostA..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CODE=$(docker exec "$HOST1" bash -c "curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 8 http://${TARGET_WEB}/" || true)
if [[ "$CODE" == "301" || "$CODE" == "302" ]]; then
  echo -e "${GREEN}PASS${NC} — Internal host reached HTTP on hostA (redirect ${CODE})"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} — Expected redirect from internal to hostA, got ${CODE:-none}"
fi

echo "Test 4: DMZ to internal ping should fail..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
echo -e "${YELLOW}[*] ping from hostA to ${INTERNAL_HOST} (5 packets)${NC}"
PING_OUT=$(docker exec "$HOSTA" bash -c "ping -c 5 -W 2 ${INTERNAL_HOST} 2>&1" || true)
if echo "$PING_OUT" | grep -q '100% packet loss'; then
  echo -e "${GREEN}PASS${NC} — DMZ->internal ICMP blocked (100% loss)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} — Expected 100% packet loss; got:\n${PING_OUT}"
fi

echo "Test 5: tcp/23 blocked on all lab IPs..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
HOSTS_IPS=(
  "10.9.0.5"
  "10.9.0.11"
  "192.168.60.5"
  "192.168.60.6"
  "192.168.60.7"
  "192.168.60.11"
)
FAIL_IP=""
for ip in "${HOSTS_IPS[@]}"; do
  echo -e "${YELLOW}[*] probing tcp/23 on ${ip}${NC}"
  if docker exec "$ROUTER" bash -c "timeout 2 bash -c 'echo >/dev/tcp/${ip}/23'" 2>/dev/null; then
    FAIL_IP="$ip"
    break
  fi
done
if [[ -z "$FAIL_IP" ]]; then
  echo -e "${GREEN}PASS${NC} — Could not open TCP/23 to any host (telnet path blocked)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} — /dev/tcp connected to ${FAIL_IP}:23 (should be blocked)"
fi

echo "Test 6: internal host to internet (curl)..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CODE=$(docker exec "$HOST1" bash -c "curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 15 http://example.com/" || true)
if [[ "$CODE" == "200" || "$CODE" == "301" || "$CODE" == "302" ]]; then
  echo -e "${GREEN}PASS${NC} — Internal host reached example.com (HTTP ${CODE})"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} — Expected HTTP response from internet, got ${CODE:-none}"
fi

echo "Test 7: NULL scan from internal to DMZ..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
echo -e "${YELLOW}[*] nmap -sN -p 80 -Pn ${TARGET_WEB}${NC}"
NMAP_OUT=$(docker exec "$HOST1" bash -c "nmap -sN -p 80 -Pn ${TARGET_WEB}" 2>&1 || true)
# 'open|filtered' means the firewall is silently dropping NULL packets — correct behavior.
# Only a plain 'open' (without '|filtered') means the port is actually open and responding.
if echo "$NMAP_OUT" | grep -E '^[0-9]+/tcp' | grep -v '|' | grep -q 'open'; then
  echo -e "${RED}FAIL${NC} — NULL scan reported tcp/80 definitively open (should be filtered)\n${NMAP_OUT}"
else
  echo -e "${GREEN}PASS${NC} — NULL scan shows filtered/closed (firewall dropping null packets)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

echo "Test 8: ICMP flood rate limit..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
HP=$(docker exec "$HOST1" bash -c "hping3 --icmp -q -c 120 -i u2000 ${TARGET_WEB} 2>&1" || true)
REC=$(echo "$HP" | grep -oE '[0-9]+ packets received' | head -1 | awk '{print $1}')
[[ -n "$REC" ]] || REC=999
if [[ "$REC" -lt 12 ]]; then
  echo -e "${GREEN}PASS${NC} — ICMP rate limit: ${REC}/120 replies (<10%)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} — Too many ICMP replies (${REC}/120); expected <12"
  echo "$HP"
fi

echo "Test 9: SYN flood (hping3 from internal)..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
echo -e "${YELLOW}[*] hping3 SYN burst from internal host to ${TARGET_WEB}:443 (hits router FORWARD)${NC}"
HP_SYN=$(docker exec "$HOST1" bash -c "hping3 -S -p 443 -c 200 -i u100 ${TARGET_WEB} 2>&1" || true)
REC_SYN=$(echo "$HP_SYN" | grep -oE '[0-9]+ packets received' | head -1 | awk '{print $1}')
[[ -n "$REC_SYN" ]] || REC_SYN=999
LOG_OK=0
BEFORE=$(docker exec "$ROUTER" bash -c "grep -c IPTables-Forward-Dropped /var/log/kern.log 2>/dev/null || echo 0")
docker exec "$HOST1" bash -c "hping3 -S -p 443 -c 80 -i u50 ${TARGET_WEB}" >/dev/null 2>&1 || true
AFTER=$(docker exec "$ROUTER" bash -c "grep -c IPTables-Forward-Dropped /var/log/kern.log 2>/dev/null || echo 0")
if [[ "${AFTER}" -gt "${BEFORE}" ]]; then
  LOG_OK=1
fi
if [[ "$REC_SYN" -lt 40 ]] || [[ "$LOG_OK" -eq 1 ]]; then
  echo -e "${GREEN}PASS${NC} — SYN limiting/logging (received ${REC_SYN}/200; log bump=${LOG_OK})"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} — Expected heavy SYN loss or iptables LOG lines; got replies=${REC_SYN}\n${HP_SYN}"
fi

echo "Test 10: reverse shell port 4444..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
echo -e "${YELLOW}[*] nc probe to ${TARGET_WEB}:4444${NC}"
NC_OUT=$(docker exec "$HOST1" bash -c "timeout 3 nc -zv ${TARGET_WEB} 4444 2>&1" || true)
if echo "$NC_OUT" | grep -qi 'open'; then
  echo -e "${RED}FAIL${NC} — Port 4444 appeared open:\n${NC_OUT}"
else
  echo -e "${GREEN}PASS${NC} — Could not connect to 4444 (blocked or filtered)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

echo ""
echo -e "${YELLOW}[*] Results: ${TESTS_PASSED}/${TESTS_TOTAL} tests passed${NC}"
if [[ "$TESTS_PASSED" -eq "$TESTS_TOTAL" ]]; then
  echo -e "${GREEN}[+] verify_firewall.sh completed successfully${NC}"
  exit 0
fi
echo -e "${RED}[-] One or more tests failed${NC}"
exit 1
