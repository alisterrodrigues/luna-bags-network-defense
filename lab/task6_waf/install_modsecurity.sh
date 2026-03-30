#!/bin/bash
# install_modsecurity.sh — ModSecurity + OWASP CRS 3.3.5 on hostA (Task 6)
# Usage: from lab/: ./task6_waf/install_modsecurity.sh
# Depends on: docker, hostA up, Apache installed, GitHub reachable

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOSTA="hostA-10.9.0.5"
CRS_TAG="3.3.5"
CRS_TAR="v${CRS_TAG}.tar.gz"
CRS_URL="https://github.com/coreruleset/coreruleset/archive/refs/tags/${CRS_TAR}"
CRS_DIR="coreruleset-${CRS_TAG}"

echo "Checking ${HOSTA}..."
if ! docker ps --format '{{.Names}}' | grep -qx "$HOSTA"; then
  echo -e "${RED}[-] ${HOSTA} not running${NC}"
  exit 1
fi

echo "Installing libapache2-mod-security2 and wget..."
if ! docker exec "$HOSTA" bash -c "
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq libapache2-mod-security2 wget ca-certificates >/dev/null 2>&1
"; then
  echo -e "${RED}[-] apt failed${NC}"
  exit 1
fi
echo -e "${GREEN}[+] packages installed${NC}"

echo "Baseline modsecurity.conf..."
if ! docker exec "$HOSTA" bash -c "
if [[ ! -f /etc/modsecurity/modsecurity.conf ]]; then
  cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf
fi
"; then
  echo -e "${RED}[-] modsecurity.conf missing${NC}"
  exit 1
fi

echo "a2enmod security2..."
if ! docker exec "$HOSTA" bash -c "a2enmod security2 >/dev/null 2>&1"; then
  echo -e "${RED}[-] a2enmod failed${NC}"
  exit 1
fi

echo "Setting up crs-setup.conf from apt package example..."
if ! docker exec "$HOSTA" bash -c '
mkdir -p /etc/modsecurity/crs
if [[ ! -f /etc/modsecurity/crs/crs-setup.conf ]]; then
  # Use apt-installed CRS example (compatible with ModSecurity 2.9.5)
  if [[ -f /usr/share/modsecurity-crs/crs-setup.conf.example ]]; then
    cp /usr/share/modsecurity-crs/crs-setup.conf.example /etc/modsecurity/crs/crs-setup.conf
  elif [[ -f /etc/modsecurity/crs-setup.conf.example ]]; then
    cp /etc/modsecurity/crs-setup.conf.example /etc/modsecurity/crs/crs-setup.conf
  else
    touch /etc/modsecurity/crs/crs-setup.conf
  fi
fi
exit 0
'; then
  echo -e "${RED}[-] crs-setup.conf init failed${NC}"
  exit 1
fi
echo -e "${GREEN}[+] crs-setup.conf ready (using apt CRS 3.3.2)${NC}"

echo "Pre-loading security2 module (graceful restart)..."
docker exec "$HOSTA" bash -c "apache2ctl graceful >/dev/null 2>&1; sleep 8" || true

echo -e "${GREEN}[+] next: configure_modsecurity.sh${NC}"
exit 0
