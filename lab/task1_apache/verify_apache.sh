#!/bin/bash
# verify_apache.sh — check Apache redirect, HTTPS, headers, listing probe (Task 1)
# Usage: from lab/: ./task1_apache/verify_apache.sh (stack must be up)
# Depends on: docker, seed-router and hostA-10.9.0.5 running

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ROUTER="seed-router"
HOSTA="hostA-10.9.0.5"
TARGET="10.9.0.5"

TESTS_PASSED=0
TESTS_TOTAL=0

echo "Checking seed-router and hostA are running..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if docker ps --format '{{.Names}}' | grep -qx "$ROUTER" && docker ps --format '{{.Names}}' | grep -qx "$HOSTA"; then
  echo -e "${GREEN}PASS${NC} containers up"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} start stack: docker compose up -d (from lab/)"
  echo -e "${YELLOW}[*] ${TESTS_PASSED}/${TESTS_TOTAL} tests passed${NC}"
  exit 1
fi

echo "Test 1: HTTP from router should redirect..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
echo -e "${YELLOW}[*] curl http://${TARGET}/${NC}"
CODE=$(docker exec "$ROUTER" bash -c "curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 http://${TARGET}/" || true)
if [[ "$CODE" == "301" || "$CODE" == "302" ]]; then
  echo -e "${GREEN}PASS${NC} redirect ${CODE}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} expected 301/302 got ${CODE:-none}"
fi

echo "Test 2: HTTPS from router..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CODE=$(docker exec "$ROUTER" bash -c "curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 https://${TARGET}/" || true)
if [[ "$CODE" == "200" ]]; then
  echo -e "${GREEN}PASS${NC} HTTPS 200"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} expected 200 got ${CODE:-none}"
fi

echo "Test 3: Location header points to HTTPS..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
LOC=$(docker exec "$ROUTER" bash -c "curl -sS -I --connect-timeout 5 http://${TARGET}/ | sed -n 's/^[Ll]ocation:[[:space:]]*//p' | tr -d '\r' | head -1" || true)
if [[ "$LOC" == https://${TARGET}/* || "$LOC" == https://${TARGET} ]]; then
  echo -e "${GREEN}PASS${NC} Location ok (${LOC})"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} bad Location: '${LOC:-empty}'"
fi

echo "Test 4: apache2 running on hostA..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if docker exec "$HOSTA" bash -c 'pgrep -c apache2 >/dev/null 2>&1'; then
  echo -e "${GREEN}PASS${NC} apache2 present"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} no apache2 on ${HOSTA}"
fi

echo "Test 5: Server header should not show version number..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
HDR=$(docker exec "$ROUTER" bash -c "curl -k -sS -I --connect-timeout 5 https://${TARGET}/ | sed -n 's/^[Ss]erver:[[:space:]]*//p' | tr -d '\r' | head -1" || true)
if echo "$HDR" | grep -qE 'Apache/[0-9]'; then
  echo -e "${RED}FAIL${NC} version leaked: ${HDR}"
elif echo "$HDR" | grep -qi 'apache'; then
  echo -e "${GREEN}PASS${NC} apache without version (${HDR})"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} unexpected Server: '${HDR}'"
fi

echo "Test 6: security headers on HTTPS..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
HEAD_DUMP=$(docker exec "$ROUTER" bash -c "curl -k -sS -I --connect-timeout 5 https://${TARGET}/" || true)
MISS=""
if ! echo "$HEAD_DUMP" | tr -d '\r' | grep -qi 'strict-transport-security:.*31536000'; then MISS="${MISS} HSTS"; fi
if ! echo "$HEAD_DUMP" | tr -d '\r' | grep -qi 'x-frame-options:.*deny'; then MISS="${MISS} XFO"; fi
if ! echo "$HEAD_DUMP" | tr -d '\r' | grep -qi 'x-content-type-options:.*nosniff'; then MISS="${MISS} XCTO"; fi
if ! echo "$HEAD_DUMP" | tr -d '\r' | grep -qi 'x-xss-protection:.*1'; then MISS="${MISS} XXSS"; fi
if ! echo "$HEAD_DUMP" | tr -d '\r' | grep -qi 'referrer-policy:.*strict-origin-when-cross-origin'; then MISS="${MISS} RP"; fi
if ! echo "$HEAD_DUMP" | tr -d '\r' | grep -qi 'content-security-policy:.*default-src'; then MISS="${MISS} CSP"; fi
if [[ -z "$MISS" ]]; then
  echo -e "${GREEN}PASS${NC} all six headers"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} missing:${MISS}"
fi

echo "Test 7: directory listing blocked (no_index_here)..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
echo -e "${YELLOW}[*] GET https://${TARGET}/no_index_here/${NC}"
BODY=$(docker exec "$ROUTER" bash -c "curl -k -sS --connect-timeout 5 https://${TARGET}/no_index_here/" || true)
CODE=$(docker exec "$ROUTER" bash -c "curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 https://${TARGET}/no_index_here/" || true)
if [[ "$CODE" == "403" ]] && ! echo "$BODY" | grep -qi 'index of'; then
  echo -e "${GREEN}PASS${NC} 403, no listing"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} expected 403 without listing; code=${CODE}"
fi

echo -e "${YELLOW}[*] Results: ${TESTS_PASSED}/${TESTS_TOTAL} tests passed${NC}"
if [[ "$TESTS_PASSED" -eq "$TESTS_TOTAL" ]]; then
  echo -e "${GREEN}[+] all tests passed${NC}"
  exit 0
fi
echo -e "${RED}[-] some tests failed${NC}"
exit 1
