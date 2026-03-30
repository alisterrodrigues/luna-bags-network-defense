#!/bin/bash
# verify_ssl.sh — check TLS, cert subject, ssl module, expiry (Task 2)
# Usage: from lab/: ./task2_ssl/verify_ssl.sh
# Depends on: docker, hostA and seed-router up, Apache SSL on hostA

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ROUTER="seed-router"
HOSTA="hostA-10.9.0.5"
TARGET="10.9.0.5"
CERT_PATH="/etc/apache2/ssl/lunabags.crt"

TESTS_PASSED=0
TESTS_TOTAL=0

echo "Checking containers..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if docker ps --format '{{.Names}}' | grep -qx "$ROUTER" && docker ps --format '{{.Names}}' | grep -qx "$HOSTA"; then
  echo -e "${GREEN}PASS${NC} containers up"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} docker compose up -d (from lab/)"
  echo -e "${YELLOW}[*] ${TESTS_PASSED}/${TESTS_TOTAL} tests passed${NC}"
  exit 1
fi

echo "Test 1: HTTPS localhost on hostA..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CODE=$(docker exec "$HOSTA" bash -c "curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 https://127.0.0.1/" || true)
if [[ "$CODE" == "200" ]]; then
  echo -e "${GREEN}PASS${NC} HTTPS 200 localhost"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} got ${CODE:-none}"
fi

echo "Test 2: HTTPS from router..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
CODE=$(docker exec "$ROUTER" bash -c "curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 https://${TARGET}/" || true)
if [[ "$CODE" == "200" ]]; then
  echo -e "${GREEN}PASS${NC} HTTPS 200 from router"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} got ${CODE:-none}"
fi

echo "Test 3: certificate subject..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
SUBJ=$(docker exec "$HOSTA" bash -c "openssl x509 -in ${CERT_PATH} -noout -subject" || true)
if echo "$SUBJ" | grep -q 'CN = 10.9.0.5' && echo "$SUBJ" | grep -q 'O = Luna Bags' && echo "$SUBJ" | grep -q 'ST = New York'; then
  echo -e "${GREEN}PASS${NC} subject ok"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} ${SUBJ}"
fi

echo "Test 4: ssl_module loaded..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if docker exec "$HOSTA" bash -c 'apache2ctl -M 2>/dev/null | grep -q ssl_module'; then
  echo -e "${GREEN}PASS${NC} ssl_module"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} ssl_module not in apache2ctl -M"
fi

echo "Test 5: cert not expired..."
TESTS_TOTAL=$((TESTS_TOTAL + 1))
echo -e "${YELLOW}[*] openssl -checkend${NC}"
if docker exec "$HOSTA" bash -c "openssl x509 -in ${CERT_PATH} -noout -checkend 0"; then
  echo -e "${GREEN}PASS${NC} validity ok"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "${RED}FAIL${NC} checkend failed"
fi

echo -e "${YELLOW}[*] Results: ${TESTS_PASSED}/${TESTS_TOTAL} tests passed${NC}"
if [[ "$TESTS_PASSED" -eq "$TESTS_TOTAL" ]]; then
  echo -e "${GREEN}[+] all tests passed${NC}"
  exit 0
fi
echo -e "${RED}[-] some tests failed${NC}"
exit 1
