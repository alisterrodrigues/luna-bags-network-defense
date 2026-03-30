#!/bin/bash
# configure_wireguard.sh — generate keys and write wg0.conf on router and hostA (Task 4)
# Usage: from lab/: ./task4_vpn/configure_wireguard.sh
# Depends on: install_wireguard.sh run first, stack running

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# VPN addressing from SPECS
SERVER_VPN_IP="10.200.200.1"
CLIENT_VPN_IP="10.200.200.2"
WG_PORT="51820"
ROUTER_DMZ_IP="10.9.0.11"
INT_NET="192.168.60.0/24"

if ! docker ps --format '{{.Names}}' | grep -qx 'seed-router'; then
  echo -e "${RED}[-] seed-router is not running${NC}"
  exit 1
fi
if ! docker ps --format '{{.Names}}' | grep -qx 'hostA-10.9.0.5'; then
  echo -e "${RED}[-] hostA-10.9.0.5 is not running${NC}"
  exit 1
fi

echo "[1/4] Generating keys on seed-router..."
docker exec seed-router bash -c '
  mkdir -p /etc/wireguard/keys
  chmod 700 /etc/wireguard/keys
  wg genkey | tee /etc/wireguard/keys/server_private.key | wg pubkey > /etc/wireguard/keys/server_public.key
  chmod 600 /etc/wireguard/keys/server_private.key
  echo "[+] server keys generated"
'
if [ $? -ne 0 ]; then
  echo -e "${RED}[-] Key generation failed on router${NC}"
  exit 1
fi
echo -e "${GREEN}[+] Router keys generated${NC}"

echo "[2/4] Generating keys on hostA..."
docker exec hostA-10.9.0.5 bash -c '
  mkdir -p /etc/wireguard/keys
  chmod 700 /etc/wireguard/keys
  wg genkey | tee /etc/wireguard/keys/client_private.key | wg pubkey > /etc/wireguard/keys/client_public.key
  chmod 600 /etc/wireguard/keys/client_private.key
  echo "[+] client keys generated"
'
if [ $? -ne 0 ]; then
  echo -e "${RED}[-] Key generation failed on hostA${NC}"
  exit 1
fi
echo -e "${GREEN}[+] hostA keys generated${NC}"

# read the public keys back so we can cross-configure the peers
SERVER_PUBKEY=$(docker exec seed-router cat /etc/wireguard/keys/server_public.key | tr -d '\n\r')
CLIENT_PUBKEY=$(docker exec hostA-10.9.0.5 cat /etc/wireguard/keys/client_public.key | tr -d '\n\r')
SERVER_PRIVKEY=$(docker exec seed-router cat /etc/wireguard/keys/server_private.key | tr -d '\n\r')
CLIENT_PRIVKEY=$(docker exec hostA-10.9.0.5 cat /etc/wireguard/keys/client_private.key | tr -d '\n\r')

if [ -z "$SERVER_PUBKEY" ] || [ -z "$CLIENT_PUBKEY" ]; then
  echo -e "${RED}[-] Could not read public keys${NC}"
  exit 1
fi
echo -e "${YELLOW}[*] Server public key: ${SERVER_PUBKEY}${NC}"
echo -e "${YELLOW}[*] Client public key: ${CLIENT_PUBKEY}${NC}"

echo "[3/4] Writing wg0.conf on seed-router..."
docker exec seed-router bash -c "cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = ${SERVER_VPN_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVKEY}
SaveConfig = false
# allow VPN traffic to be forwarded to the internal network
PostUp = iptables-legacy -I FORWARD 1 -i wg0 -j ACCEPT; iptables-legacy -I FORWARD 1 -o wg0 -j ACCEPT; iptables-legacy -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables-legacy -D FORWARD -i wg0 -j ACCEPT; iptables-legacy -D FORWARD -o wg0 -j ACCEPT; iptables-legacy -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
# hostA client
PublicKey = ${CLIENT_PUBKEY}
AllowedIPs = ${CLIENT_VPN_IP}/32
EOF"
if [ $? -ne 0 ]; then
  echo -e "${RED}[-] wg0.conf write failed on router${NC}"
  exit 1
fi
docker exec seed-router chmod 600 /etc/wireguard/wg0.conf
echo -e "${GREEN}[+] Router wg0.conf written${NC}"

echo "[4/4] Writing wg0.conf on hostA..."
docker exec hostA-10.9.0.5 bash -c "cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = ${CLIENT_VPN_IP}/24
PrivateKey = ${CLIENT_PRIVKEY}
SaveConfig = false

[Peer]
# router server
PublicKey = ${SERVER_PUBKEY}
Endpoint = ${ROUTER_DMZ_IP}:${WG_PORT}
# only route internal network traffic through the VPN tunnel
AllowedIPs = ${INT_NET}
PersistentKeepalive = 25
EOF"
if [ $? -ne 0 ]; then
  echo -e "${RED}[-] wg0.conf write failed on hostA${NC}"
  exit 1
fi
docker exec hostA-10.9.0.5 chmod 600 /etc/wireguard/wg0.conf
echo -e "${GREEN}[+] hostA wg0.conf written${NC}"

# allow WireGuard UDP port through the firewall
echo -e "${YELLOW}[*] Adding firewall rules for WireGuard on router...${NC}"
docker exec seed-router bash -c "
  iptables-legacy -A INPUT -p udp --dport ${WG_PORT} -j ACCEPT
  # allow forwarding from VPN interface to internal network
  iptables-legacy -I FORWARD 1 -i wg0 -d ${INT_NET} -j ACCEPT
  echo '[+] firewall updated for WireGuard'"

echo -e "${GREEN}[+] Done — run start_vpn.sh next${NC}"
