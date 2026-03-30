#!/bin/bash
# configure_modsecurity.sh — enforcement mode, audit log, CRS includes, HTTP vhost for tests
# Usage: from lab/: ./task6_waf/configure_modsecurity.sh (after install_modsecurity.sh)
# Depends on: docker, hostA, install_modsecurity.sh done
# Note: port 80 serves content (no redirect) so verify_waf can use http://10.9.0.5

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOSTA="hostA-10.9.0.5"

echo "Checking ${HOSTA}..."
if ! docker ps --format '{{.Names}}' | grep -qx "$HOSTA"; then
  echo -e "${RED}[-] not running${NC}"
  exit 1
fi

echo "Patching /etc/modsecurity/modsecurity.conf..."
if ! docker exec "$HOSTA" bash -c '
MS=/etc/modsecurity/modsecurity.conf
[[ -f "$MS" ]] || exit 1
if grep -q "^SecRuleEngine" "$MS"; then sed -i "s/^SecRuleEngine .*/SecRuleEngine On/" "$MS"; else echo "SecRuleEngine On" >> "$MS"; fi
if grep -q "^SecRequestBodyAccess" "$MS"; then sed -i "s/^SecRequestBodyAccess .*/SecRequestBodyAccess On/" "$MS"; else echo "SecRequestBodyAccess On" >> "$MS"; fi
if grep -q "^SecResponseBodyAccess" "$MS"; then sed -i "s/^SecResponseBodyAccess .*/SecResponseBodyAccess On/" "$MS"; else echo "SecResponseBodyAccess On" >> "$MS"; fi
if grep -q "^SecAuditLog " "$MS"; then sed -i "s#^SecAuditLog .*#SecAuditLog /var/log/apache2/modsec_audit.log#" "$MS"; else echo "SecAuditLog /var/log/apache2/modsec_audit.log" >> "$MS"; fi
if grep -q "^SecAuditLogParts" "$MS"; then sed -i "s/^SecAuditLogParts .*/SecAuditLogParts ABCFHZ/" "$MS"; else echo "SecAuditLogParts ABCFHZ" >> "$MS"; fi
if grep -q "^SecAuditEngine" "$MS"; then sed -i "s/^SecAuditEngine .*/SecAuditEngine On/" "$MS"; else echo "SecAuditEngine On" >> "$MS"; fi
if grep -q "^SecAuditLogType" "$MS"; then sed -i "s/^SecAuditLogType .*/SecAuditLogType Serial/" "$MS"; else echo "SecAuditLogType Serial" >> "$MS"; fi
touch /var/log/apache2/modsec_audit.log
chmod 640 /var/log/apache2/modsec_audit.log 2>/dev/null || true
chown www-data:adm /var/log/apache2/modsec_audit.log 2>/dev/null || true
exit 0
'; then
  echo -e "${RED}[-] modsecurity.conf patch failed${NC}"
  exit 1
fi
echo -e "${GREEN}[+] engine on, audit log set${NC}"

echo "Appending to crs-setup.conf..."
if ! docker exec "$HOSTA" bash -c '
CRS=/etc/modsecurity/crs/crs-setup.conf
[[ -f "$CRS" ]] || exit 1
if ! grep -q "id:900199" "$CRS"; then
  printf "\n# Luna Bags\nSecDefaultAction \"phase:2,log,auditlog,deny,status:403\"\nSecAction \"id:900199,phase:1,pass,nolog,setvar:tx.paranoia_level=1\"\n" >> "$CRS"
fi
exit 0
'; then
  echo -e "${RED}[-] crs-setup failed${NC}"
  exit 1
fi

echo "Removing incompatible downloaded CRS rules (using apt CRS 3.3.2 via owasp-crs.load)..."
docker exec "$HOSTA" bash -c 'rm -rf /etc/modsecurity/crs/rules' 2>/dev/null || true
# Remove any stale zz-lunabags-crs.conf that loaded the deleted rules
docker exec "$HOSTA" bash -c 'rm -f /etc/modsecurity/zz-lunabags-crs.conf' 2>/dev/null || true

echo "HTTP vhost: DocumentRoot on :80, WAF exceptions (no redirect to HTTPS for WAF curl tests)..."
docker exec -i "$HOSTA" bash << 'HOSTA_EOF'
cat > /etc/apache2/sites-available/000-lunabags-http.conf << 'VHOST_EOF'
<VirtualHost *:80>
    ServerName 10.9.0.5
    DocumentRoot /var/www/html
    <Directory /var/www/html>
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>
    ErrorLog /var/log/apache2/error.log
    CustomLog /var/log/apache2/access.log combined
    # Lab uses IP-based access — disable numeric-IP Host header rule
    SecRuleRemoveById 920350
    # Intercept path traversal in phase:1 before Apache URI normalization returns 400
    SecRule REQUEST_URI_RAW "@contains ../" "id:9001,phase:1,deny,status:403,log,auditlog,msg:'Path traversal attempt'"
</VirtualHost>
VHOST_EOF
cp -f /etc/apache2/sites-available/000-lunabags-http.conf /etc/apache2/sites-enabled/000-lunabags-http.conf 2>/dev/null || true
HOSTA_EOF

echo "apache2ctl configtest..."
if ! docker exec "$HOSTA" bash -c "apache2ctl configtest 2>/dev/null"; then
  echo -e "${RED}[-] configtest failed${NC}"
  docker exec "$HOSTA" bash -c "apache2ctl configtest"
  exit 1
fi
docker exec "$HOSTA" bash -c '
apache2ctl graceful >/dev/null 2>&1
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  sleep 2
  curl -s http://127.0.0.1/ -o /dev/null 2>/dev/null
  SZ=$(wc -c < /var/log/apache2/modsec_audit.log 2>/dev/null || echo 0)
  [[ "${SZ:-0}" -gt 0 ]] && break
done
' || true

echo "Restoring fail2ban ignoreip for WAF testing (unban router IP, add to ignoreip)..."
docker exec "$HOSTA" bash -c '
fail2ban-client set apache-badbots unbanip 10.9.0.11 2>/dev/null || true
fail2ban-client set apache-noscript unbanip 10.9.0.11 2>/dev/null || true
fail2ban-client set apache-auth unbanip 10.9.0.11 2>/dev/null || true
fail2ban-client set sshd unbanip 10.9.0.11 2>/dev/null || true
sed -i "s|ignoreip = 127.0.0.1/8 ::1$|ignoreip = 127.0.0.1/8 ::1 10.9.0.11|" /etc/fail2ban/jail.local
fail2ban-client reload >/dev/null 2>&1 || true
' 2>/dev/null || true

echo -e "${GREEN}[+] next: verify_waf.sh${NC}"
exit 0
