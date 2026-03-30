#!/bin/bash
# verify_waf.sh — ModSecurity/CRS checks from seed-router (Task 6)
# Usage: from lab/: ./task6_waf/verify_waf.sh (after configure_modsecurity.sh)
# Depends on: docker, curl on router, ModSecurity enforcing on hostA

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ROUTER="seed-router"
HOSTA="hostA-10.9.0.5"
BASE_HTTP="http://10.9.0.5"

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

echo "Ensuring curl on router..."
if ! docker exec "$ROUTER" bash -c "command -v curl >/dev/null 2>&1 || { export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq curl >/dev/null 2>&1; }"; then
  echo -e "${RED}[-] need curl${NC}"
  exit 1
fi

echo "Test 1: normal GET -> 200..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CODE=$(docker exec "$ROUTER" bash -c "curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 15 '${BASE_HTTP}/'" || true)
if [[ "$CODE" == "200" ]]; then
  echo -e "${GREEN}PASS${NC} ${CODE}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} expected 200 got ${CODE:-none}"
fi

echo "Test 2: SQLi -> 403..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CODE=$(docker exec "$ROUTER" bash -c "curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 15 '${BASE_HTTP}/?id=1%27%20OR%20%271%27%3D%271'" || true)
if [[ "$CODE" == "403" ]]; then
  echo -e "${GREEN}PASS${NC} ${CODE}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} expected 403 got ${CODE:-none}"
fi

echo "Test 3: XSS -> 403..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CODE=$(docker exec "$ROUTER" bash -c "curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 15 '${BASE_HTTP}/?q=%3Cscript%3Ealert(1)%3C/script%3E'" || true)
if [[ "$CODE" == "403" ]]; then
  echo -e "${GREEN}PASS${NC} ${CODE}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} expected 403 got ${CODE:-none}"
fi

echo "Test 4: path traversal -> 403..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CODE=$(docker exec "$ROUTER" bash -c "curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 15 --path-as-is '${BASE_HTTP}/../../../../etc/passwd'" || true)
if [[ "$CODE" == "403" ]]; then
  echo -e "${GREEN}PASS${NC} ${CODE}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} expected 403 got ${CODE:-none}"
fi

echo "Test 5: User-Agent nikto -> 403..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CODE=$(docker exec "$ROUTER" bash -c "curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 15 -A nikto '${BASE_HTTP}/'" || true)
if [[ "$CODE" == "403" ]]; then
  echo -e "${GREEN}PASS${NC} ${CODE}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} expected 403 got ${CODE:-none}"
fi

echo "Test 6: RCE query -> 403..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CODE=$(docker exec "$ROUTER" bash -c "curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 15 '${BASE_HTTP}/?cmd=;cat%20/etc/passwd'" || true)
if [[ "$CODE" == "403" ]]; then
  echo -e "${GREEN}PASS${NC} ${CODE}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} expected 403 got ${CODE:-none}"
fi

echo "Test 7: modsec_audit.log non-empty..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
SZ=$(docker exec "$HOSTA" bash -c "if [[ -f /var/log/apache2/modsec_audit.log ]]; then wc -c < /var/log/apache2/modsec_audit.log; else echo 0; fi" | tr -d '[:space:]' || echo 0)
if [[ "${SZ:-0}" -gt 0 ]]; then
  echo -e "${GREEN}PASS${NC} ${SZ} bytes"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} empty or missing"
fi

echo -e "${YELLOW}[*] Results: ${TESTS_PASSED}/${TESTS_TOTAL} tests passed${NC}"
if [[ "$TESTS_PASSED" -eq "$TESTS_TOTAL" ]]; then
  echo -e "${GREEN}[+] all tests passed${NC}"
  exit 0
fi
echo -e "${RED}[-] some tests failed${NC}"
exit 1
