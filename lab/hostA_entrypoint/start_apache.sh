#!/bin/bash
# start_apache.sh — install Apache + TLS, Luna Bags placeholder (Tasks 1–2); container entrypoint
# Usage: run by docker-compose on hostA (not usually run by hand)
# Depends on: Ubuntu 22.04 image, apt available

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

WEB_ROOT="/var/www/html"
SSL_DIR="/etc/apache2/ssl"
SSL_KEY="${SSL_DIR}/lunabags.key"
SSL_CRT="${SSL_DIR}/lunabags.crt"
SERVER_NAME_IP="10.9.0.5"
CERT_DAYS="365"
RSA_BITS="2048"

echo "Installing Apache, OpenSSL, curl, ping, and modules..."
export DEBIAN_FRONTEND=noninteractive
if ! apt-get update -qq 2>/dev/null; then
  echo -e "${RED}[-] apt-get update failed${NC}"
  exit 1
fi
if ! apt-get install -y -qq apache2 openssl curl iputils-ping iproute2 2>/dev/null; then
  echo -e "${RED}[-] apt-get install failed${NC}"
  exit 1
fi
echo -e "${GREEN}[+] apache2, openssl, curl, ping, iproute2 installed${NC}"

echo "Writing global hardening (ServerTokens, ServerSignature, TraceEnable, SSLSessionCache)..."
# Overwrite the distro's security.conf directly — it sets ServerTokens OS and
# would override any conf loaded alongside it regardless of load order.
cat > /etc/apache2/conf-available/security.conf <<'EOF'
# Luna Bags — hardened security.conf (replaces Ubuntu default)
ServerTokens Prod
ServerSignature Off
TraceEnable Off
EOF
a2enconf security >/dev/null 2>&1 || true

if ! cat > /etc/apache2/conf-available/lunabags-global.conf <<'EOF'
# Luna Bags global config
# SSL session cache must live at server level, not inside VirtualHost
<IfModule mod_ssl.c>
    SSLSessionCache shmcb:/var/run/apache2/ssl_scache(512000)
    SSLSessionCacheTimeout 300
</IfModule>
EOF
then
  echo -e "${RED}[-] could not write lunabags-global.conf${NC}"
  exit 1
fi
if ! a2enconf lunabags-global >/dev/null 2>&1; then
  echo -e "${RED}[-] a2enconf lunabags-global failed${NC}"
  exit 1
fi
echo -e "${GREEN}[+] lunabags-global.conf enabled${NC}"

echo "Enabling ssl, rewrite, headers, socache_shmcb..."
if ! a2enmod ssl >/dev/null 2>&1 || ! a2enmod rewrite >/dev/null 2>&1 || ! a2enmod headers >/dev/null 2>&1 || ! a2enmod socache_shmcb >/dev/null 2>&1; then
  echo -e "${RED}[-] a2enmod failed${NC}"
  exit 1
fi
echo -e "${GREEN}[+] modules enabled${NC}"

echo "TLS key and certificate (skip if already there)..."
if ! install -d -m 0755 "$SSL_DIR"; then
  echo -e "${RED}[-] could not create ${SSL_DIR}${NC}"
  exit 1
fi
if [[ -f "$SSL_KEY" && -f "$SSL_CRT" ]]; then
  echo -e "${YELLOW}[*] SSL files already present, not regenerating${NC}"
else
  if ! openssl req -x509 -nodes -days "$CERT_DAYS" -newkey "rsa:${RSA_BITS}" \
    -keyout "$SSL_KEY" \
    -out "$SSL_CRT" \
    -subj "/C=US/ST=New York/L=New York/O=Luna Bags/OU=IT/CN=${SERVER_NAME_IP}" 2>/dev/null; then
    echo -e "${RED}[-] openssl failed${NC}"
    exit 1
  fi
  chmod 600 "$SSL_KEY"
  echo -e "${GREEN}[+] self-signed cert created${NC}"
fi

echo "Site content and no_index_here directory..."
if ! install -d -m 0755 "$WEB_ROOT"; then
  echo -e "${RED}[-] could not create web root${NC}"
  exit 1
fi
if ! cat > "${WEB_ROOT}/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Luna Bags — Placeholder</title></head>
<body>
  <h1>Luna Bags</h1>
  <p>Eco-friendly bags — placeholder site for network defense lab.</p>
</body>
</html>
EOF
then
  echo -e "${RED}[-] could not write index.html${NC}"
  exit 1
fi
if ! install -d -m 0755 "${WEB_ROOT}/no_index_here"; then
  echo -e "${RED}[-] could not create no_index_here${NC}"
  exit 1
fi
echo -e "${GREEN}[+] content in place${NC}"

echo "Virtual hosts: HTTP redirect, HTTPS + headers..."
if ! cat > /etc/apache2/sites-available/000-lunabags-http.conf <<EOF
<VirtualHost *:80>
    ServerName ${SERVER_NAME_IP}
    Redirect permanent / https://${SERVER_NAME_IP}/
    CustomLog /var/log/apache2/access.log combined
</VirtualHost>
EOF
then
  echo -e "${RED}[-] could not write HTTP vhost${NC}"
  exit 1
fi

if ! cat > /etc/apache2/sites-available/lunabags-ssl.conf <<EOF
<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerName ${SERVER_NAME_IP}
    DocumentRoot ${WEB_ROOT}

    SSLEngine on
    SSLCertificateFile ${SSL_CRT}
    SSLCertificateKeyFile ${SSL_KEY}

    <Directory ${WEB_ROOT}>
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>

    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    Header always set X-Frame-Options "DENY"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set Content-Security-Policy "default-src 'self'"
    CustomLog /var/log/apache2/access.log combined
</VirtualHost>
</IfModule>
EOF
then
  echo -e "${RED}[-] could not write SSL vhost${NC}"
  exit 1
fi

a2dissite 000-default.conf >/dev/null 2>&1 || true
a2dissite default-ssl.conf >/dev/null 2>&1 || true
if ! a2ensite 000-lunabags-http.conf >/dev/null 2>&1 || ! a2ensite lunabags-ssl.conf >/dev/null 2>&1; then
  echo -e "${RED}[-] a2ensite failed${NC}"
  exit 1
fi

grep -q "^ServerName ${SERVER_NAME_IP}" /etc/apache2/apache2.conf 2>/dev/null || \
  echo "ServerName ${SERVER_NAME_IP}" >> /etc/apache2/apache2.conf

cat > /etc/apache2/ports.conf <<'EOF'
Listen 80
<IfModule ssl_module>
    Listen 443
</IfModule>
<IfModule mod_gnutls.c>
    Listen 443
</IfModule>
EOF

if ! apache2ctl configtest 2>/dev/null; then
  echo -e "${RED}[-] apache2ctl configtest failed${NC}"
  apache2ctl configtest
  exit 1
fi
echo -e "${GREEN}[+] config OK${NC}"

echo "Starting Apache in foreground..."
exec apache2ctl -D FOREGROUND
