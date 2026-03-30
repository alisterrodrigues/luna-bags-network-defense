#!/bin/bash
# verify_fail2ban.sh — ping fail2ban, list jails, badbots ban test (Task 5)
# Usage: from lab/: ./task5_ids/verify_fail2ban.sh (after configure_fail2ban.sh)
# Depends on: docker, Apache on hostA, curl on router

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOSTA="hostA-10.9.0.5"
ROUTER="seed-router"
TARGET="10.9.0.5"
ROUTER_IP="10.9.0.11"

TESTS_PASSED=0
TESTS_TOTAL=0

echo "Checking containers..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if docker ps --format '{{.Names}}' | grep -qx "$ROUTER" && docker ps --format '{{.Names}}' | grep -qx "$HOSTA"; then
  echo -e "${GREEN}PASS${NC} up"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} docker compose up -d"
  echo -e "${YELLOW}[*] ${TESTS_PASSED}/${TESTS_TOTAL} tests passed${NC}"
  exit 1
fi

echo "Test 1: fail2ban ping on hostA..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if docker exec "$HOSTA" bash -c "fail2ban-client ping >/dev/null 2>&1"; then
  echo -e "${GREEN}PASS${NC} hostA ping"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} hostA ping"
fi

echo "Test 2: fail2ban ping on router..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if docker exec "$ROUTER" bash -c "fail2ban-client ping >/dev/null 2>&1"; then
  echo -e "${GREEN}PASS${NC} router ping"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} router ping"
fi

echo "Test 3: jails on hostA..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
ST_H=$(docker exec "$HOSTA" bash -c "fail2ban-client status 2>&1" || true)
echo -e "${YELLOW}[*] ${ST_H}${NC}"
LIST_LINE=$(echo "$ST_H" | sed -n 's/.*Jail list:[[:space:]]*//p' | tr -d '\r')
MISS_H=""
IFS=',' read -ra PARTS <<< "$LIST_LINE"
for j in sshd apache-auth apache-badbots apache-noscript; do
  ok=0
  for p in "${PARTS[@]}"; do
    pp=$(echo "$p" | tr -d '[:space:]')
    if [[ "$pp" == "$j" ]]; then ok=1; break; fi
  done
  if [[ "$ok" -eq 0 ]]; then MISS_H="${MISS_H} ${j}"; fi
done
if [[ -z "$MISS_H" ]]; then
  echo -e "${GREEN}PASS${NC} all jails on hostA"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} missing:${MISS_H}"
fi

echo "Test 4: jails on router..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
ST_R=$(docker exec "$ROUTER" bash -c "fail2ban-client status 2>&1" || true)
echo -e "${YELLOW}[*] ${ST_R}${NC}"
LIST_LINE=$(echo "$ST_R" | sed -n 's/.*Jail list:[[:space:]]*//p' | tr -d '\r')
MISS_R=""
IFS=',' read -ra PARTS <<< "$LIST_LINE"
for j in sshd apache-auth apache-badbots apache-noscript; do
  ok=0
  for p in "${PARTS[@]}"; do
    pp=$(echo "$p" | tr -d '[:space:]')
    if [[ "$pp" == "$j" ]]; then ok=1; break; fi
  done
  if [[ "$ok" -eq 0 ]]; then MISS_R="${MISS_R} ${j}"; fi
done
if [[ -z "$MISS_R" ]]; then
  echo -e "${GREEN}PASS${NC} all jails on router"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} missing:${MISS_R}"
fi

echo "Test 5: apache-badbots bans router IP (User-Agent nikto)..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
docker exec "$HOSTA" bash -c "fail2ban-client set apache-badbots unbanip ${ROUTER_IP} 2>/dev/null" || true
docker exec "$HOSTA" bash -c "fail2ban-client set apache-noscript unbanip ${ROUTER_IP} 2>/dev/null" || true
docker exec "$HOSTA" bash -c "fail2ban-client set apache-auth unbanip ${ROUTER_IP} 2>/dev/null" || true
if ! docker exec "$ROUTER" bash -c "command -v curl >/dev/null 2>&1 || { export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq curl >/dev/null 2>&1; }"; then
  echo -e "${RED}FAIL${NC} no curl on router"
else
  docker exec "$ROUTER" bash -c "curl -sS -o /dev/null --connect-timeout 10 -A nikto -k https://${TARGET}/ 2>/dev/null || curl -sS -o /dev/null --connect-timeout 10 -A nikto http://${TARGET}/" || true
fi
sleep 5
BAD_STATUS=$(docker exec "$HOSTA" bash -c "fail2ban-client status apache-badbots 2>&1" || true)
echo -e "${YELLOW}[*] ${BAD_STATUS}${NC}"
if echo "$BAD_STATUS" | grep -q "${ROUTER_IP}"; then
  echo -e "${GREEN}PASS${NC} ${ROUTER_IP} banned"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} expected ban for ${ROUTER_IP}"
fi

echo -e "${YELLOW}[*] Results: ${TESTS_PASSED}/${TESTS_TOTAL} tests passed${NC}"
if [[ "$TESTS_PASSED" -eq "$TESTS_TOTAL" ]]; then
  echo -e "${GREEN}[+] all tests passed${NC}"
  exit 0
fi
echo -e "${RED}[-] some tests failed${NC}"
exit 1
