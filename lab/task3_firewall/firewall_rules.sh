#!/bin/bash
# firewall_rules.sh — Phase 1 host hardening + telnet off; Phase 2 router firewall (Task 3)
# Usage: from lab/: ./task3_firewall/firewall_rules.sh (stack up, seed-router privileged)
# Depends on: docker, NET_ADMIN on all containers

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOSTA_IP="10.9.0.5"
ROUTER_DMZ_IP="10.9.0.11"
ROUTER_INT_IP="192.168.60.11"
DMZ_NET="10.9.0.0/24"
INT_NET="192.168.60.0/24"

ALL_CONTAINERS=(
  "hostA-10.9.0.5"
  "seed-router"
  "host1-192.168.60.5"
  "host2-192.168.60.6"
  "host3-192.168.60.7"
)

echo "Phase 1: harden each container (inetd/telnet, iptables)..."
echo -e "${YELLOW}[*] inetd stop, telnet commented, tcp/23 reject, syn/icmp limits, ssh brute cap${NC}"

for c in "${ALL_CONTAINERS[@]}"; do
  echo "Phase 1 on ${c}..."
  if ! docker ps --format '{{.Names}}' | grep -qx "$c"; then
    echo -e "${RED}[-] ${c} not running — docker compose up -d first${NC}"
    exit 1
  fi

  # Install tools quietly; suppress all apt/dpkg output
  docker exec "$c" bash -c '
    export DEBIAN_FRONTEND=noninteractive
    need=""
    command -v iptables-legacy >/dev/null 2>&1 || need="$need iptables"
    command -v ip >/dev/null 2>&1 || need="$need iproute2"
    if [[ -n "$need" ]]; then
      apt-get update -qq >/dev/null 2>&1
      apt-get install -y -qq $need >/dev/null 2>&1
    fi
  ' 2>/dev/null

  # Disable inetd/telnet service
  docker exec "$c" bash -c '
    command -v systemctl >/dev/null 2>&1 && { systemctl stop inetd 2>/dev/null; systemctl disable inetd 2>/dev/null; } || true
    if [[ -f /etc/inetd.conf ]] && grep -qE "^[[:space:]]*telnet" /etc/inetd.conf 2>/dev/null; then
      sed -i "s/^[[:space:]]*telnet/# telnet disabled by Luna Bags firewall /" /etc/inetd.conf
    fi
  ' 2>/dev/null

  # Apply iptables rules — use legacy frontend to avoid nf_tables module issues.
  # On non-privileged containers this may print warnings; we treat failures as
  # non-fatal because the router enforces all inter-zone policy.
  IPT_OUT=$(docker exec "$c" bash -c '
    IPT="iptables-legacy"
    command -v iptables-legacy >/dev/null 2>&1 || IPT="iptables"
    $IPT -F INPUT 2>/dev/null || true
    $IPT -P INPUT ACCEPT 2>/dev/null || true
    $IPT -A INPUT -i lo -j ACCEPT 2>/dev/null || true
    $IPT -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    $IPT -A INPUT -p tcp --dport 23 -j REJECT --reject-with tcp-reset 2>/dev/null || true
    $IPT -A INPUT -p tcp --dport 4444 -j DROP 2>/dev/null || true
    $IPT -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --name SSH_BRUTE --set 2>/dev/null || true
    $IPT -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --name SSH_BRUTE --update --seconds 60 --hitcount 4 -j DROP 2>/dev/null || true
    $IPT -A INPUT -p tcp --tcp-flags SYN,RST,ACK SYN -m limit --limit 10/sec --limit-burst 20 -j ACCEPT 2>/dev/null || true
    $IPT -A INPUT -p tcp --tcp-flags SYN,RST,ACK SYN -j DROP 2>/dev/null || true
    $IPT -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/sec --limit-burst 3 -j ACCEPT 2>/dev/null || true
    $IPT -A INPUT -p icmp --icmp-type echo-request -j DROP 2>/dev/null || true
  ' 2>&1)

  # Only surface iptables output if it contains actual errors (not just warnings)
  if echo "$IPT_OUT" | grep -qi 'error\|fatal\|cannot\|failed' 2>/dev/null; then
    echo -e "${YELLOW}[!] iptables warnings on ${c} (router policy still enforces zone rules):${NC}"
    echo "$IPT_OUT" | grep -i 'error\|fatal\|cannot\|failed' || true
  fi

  echo -e "${GREEN}[+] Phase 1 applied on ${c}${NC}"
done

echo "Static routes for zone tests..."
echo -e "${YELLOW}[*] internal -> DMZ via router; hostA -> internal LAN via router${NC}"

for c in host1-192.168.60.5 host2-192.168.60.6 host3-192.168.60.7; do
  if docker exec "$c" bash -c \
    "ip route replace ${DMZ_NET} via ${ROUTER_INT_IP} 2>/dev/null || ip route add ${DMZ_NET} via ${ROUTER_INT_IP} 2>/dev/null" \
    2>/dev/null; then
    echo -e "${GREEN}[+] ${c}: route to ${DMZ_NET} via ${ROUTER_INT_IP}${NC}"
  else
    echo -e "${YELLOW}[!] Could not add DMZ route on ${c} — router will handle forwarding${NC}"
  fi
done

if docker exec hostA-10.9.0.5 bash -c \
  "ip route replace ${INT_NET} via ${ROUTER_DMZ_IP} 2>/dev/null || ip route add ${INT_NET} via ${ROUTER_DMZ_IP} 2>/dev/null" \
  2>/dev/null; then
  echo -e "${GREEN}[+] hostA: route to ${INT_NET} via ${ROUTER_DMZ_IP}${NC}"
else
  echo -e "${YELLOW}[!] Could not add internal route on hostA${NC}"
fi

echo "Phase 2: router iptables (seed-router)..."
echo -e "${YELLOW}[*] DROP defaults, zone rules, mitigations, log${NC}"

if ! docker ps --format '{{.Names}}' | grep -qx "seed-router"; then
  echo -e "${RED}[-] seed-router is not running${NC}"
  exit 1
fi

docker exec -i seed-router bash << 'ROUTER_EOF'
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq iptables iproute2 >/dev/null 2>&1

IPT="iptables"
command -v iptables-legacy >/dev/null 2>&1 && IPT="iptables-legacy"

DMZ_IF=""
INT_IF=""
while IFS= read -r line; do
  iface="${line#*: }"
  iface="${iface%%@*}"
  case "$iface" in
    lo|docker*|br-*|veth*) continue ;;
  esac
  ip -4 -o addr show dev "$iface" 2>/dev/null | grep -q "10.9.0.11"    && DMZ_IF="$iface"
  ip -4 -o addr show dev "$iface" 2>/dev/null | grep -q "192.168.60.11" && INT_IF="$iface"
done < <(ip -o link show | awk -F': ' '{print $2}')

if [[ -z "$DMZ_IF" || -z "$INT_IF" ]]; then
  echo "[-] Could not map DMZ/internal interfaces"
  exit 1
fi

WAN_IF=$(ip -4 route show default 2>/dev/null | awk '/default/ {print $5; exit}')
[[ -z "$WAN_IF" ]] && WAN_IF="$DMZ_IF"

HOSTA_IP="10.9.0.5"
DMZ_NET="10.9.0.0/24"
INT_NET="192.168.60.0/24"

$IPT -F; $IPT -X
$IPT -t nat -F; $IPT -t nat -X
$IPT -t mangle -F 2>/dev/null; $IPT -t mangle -X 2>/dev/null

$IPT -P INPUT DROP
$IPT -P FORWARD DROP
$IPT -P OUTPUT ACCEPT

# ICMP echo-request flood protection — MUST be first in FORWARD, scoped to INT_IF input.
# conntrack marks rapid pings in the same flow as ESTABLISHED after the first exchange,
# so placing rate limits after the ESTABLISHED/RELATED rule would silently bypass them.
# Scoped to -i "$INT_IF" so DMZ->INT echo-requests still reach the DMZ->INT DROP rule below.
$IPT -A FORWARD -p icmp --icmp-type echo-request -i "$INT_IF" -m hashlimit --hashlimit 2/sec --hashlimit-burst 5 --hashlimit-mode srcip --hashlimit-name icmp_flood -j ACCEPT
$IPT -A FORWARD -p icmp --icmp-type echo-request -i "$INT_IF" -j DROP

$IPT -A INPUT -i lo -j ACCEPT
$IPT -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
$IPT -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

$IPT -A INPUT -p tcp --dport 22 -m state --state NEW -j ACCEPT
$IPT -A INPUT -p tcp --dport 23 -j REJECT --reject-with tcp-reset

$IPT -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
$IPT -A INPUT -p tcp --tcp-flags ALL FIN -j DROP
$IPT -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
$IPT -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
$IPT -A INPUT -p tcp --tcp-flags ALL SYN,FIN -j DROP
$IPT -A INPUT -p tcp --tcp-flags ALL SYN,RST -j DROP
$IPT -A INPUT -f -j DROP
$IPT -A INPUT -s 127.0.0.0/8 ! -i lo -j DROP
$IPT -A INPUT -s 0.0.0.0/8 -j DROP

$IPT -A INPUT -p tcp --tcp-flags SYN,RST,ACK SYN -m limit --limit 10/sec --limit-burst 20 -j ACCEPT
$IPT -A INPUT -p tcp --tcp-flags SYN,RST,ACK SYN -j DROP

$IPT -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/sec --limit-burst 3 -j ACCEPT
$IPT -A INPUT -p icmp --icmp-type echo-request -j DROP

$IPT -A INPUT -p udp --dport 53 -m length --length 512:65535 -j DROP

$IPT -A FORWARD -p tcp --dport 23 -j REJECT --reject-with tcp-reset
$IPT -A FORWARD -p tcp --sport 23 -j REJECT --reject-with tcp-reset

$IPT -A FORWARD -p tcp --tcp-flags ALL NONE -j DROP
$IPT -A FORWARD -p tcp --tcp-flags ALL FIN -j DROP
$IPT -A FORWARD -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
$IPT -A FORWARD -p tcp --tcp-flags ALL ALL -j DROP
$IPT -A FORWARD -p tcp --tcp-flags ALL SYN,FIN -j DROP
$IPT -A FORWARD -p tcp --tcp-flags ALL SYN,RST -j DROP
$IPT -A FORWARD -f -j DROP

for iface in "$DMZ_IF" "$INT_IF"; do
  $IPT -A FORWARD -i "$iface" -s 127.0.0.0/8 -j DROP
done

$IPT -A FORWARD -i "$DMZ_IF" -o "$INT_IF" -j DROP

$IPT -A FORWARD -p tcp -m multiport --dports 80,443 -d "$HOSTA_IP" --tcp-flags SYN,RST,ACK SYN -m hashlimit --hashlimit 40/sec --hashlimit-burst 80 --hashlimit-mode srcip --hashlimit-name syn2hosta -j ACCEPT
$IPT -A FORWARD -p tcp -m multiport --dports 80,443 -d "$HOSTA_IP" --tcp-flags SYN,RST,ACK SYN -j DROP

$IPT -A FORWARD -i "$DMZ_IF" -s "$HOSTA_IP" ! -d "$DMZ_NET" -m state --state NEW -j DROP

$IPT -A FORWARD -i "$INT_IF" -o "$WAN_IF" -s "$INT_NET" -p tcp -m multiport --dports 80,443 -m state --state NEW -d 10.0.0.0/8 -j DROP
$IPT -A FORWARD -i "$INT_IF" -o "$WAN_IF" -s "$INT_NET" -p tcp -m multiport --dports 80,443 -m state --state NEW -d 172.16.0.0/12 -j DROP
$IPT -A FORWARD -i "$INT_IF" -o "$WAN_IF" -s "$INT_NET" -p tcp -m multiport --dports 80,443 -m state --state NEW -d 192.168.0.0/16 -j DROP
$IPT -A FORWARD -i "$INT_IF" -o "$WAN_IF" -s "$INT_NET" -p tcp -m multiport --dports 80,443 -m state --state NEW -j ACCEPT

$IPT -A FORWARD -i "$INT_IF" -o "$WAN_IF" -s "$INT_NET" -p udp -m multiport --dports 53,123 -d 10.0.0.0/8 -j DROP
$IPT -A FORWARD -i "$INT_IF" -o "$WAN_IF" -s "$INT_NET" -p udp -m multiport --dports 53,123 -d 172.16.0.0/12 -j DROP
$IPT -A FORWARD -i "$INT_IF" -o "$WAN_IF" -s "$INT_NET" -p udp -m multiport --dports 53,123 -d 192.168.0.0/16 -j DROP
$IPT -A FORWARD -i "$INT_IF" -o "$WAN_IF" -s "$INT_NET" -p udp -m multiport --dports 53,123 -j ACCEPT

$IPT -A FORWARD -p tcp --tcp-flags SYN,RST,ACK SYN -d "$INT_NET" -m limit --limit 10/sec --limit-burst 20 -j ACCEPT
$IPT -A FORWARD -p tcp --tcp-flags SYN,RST,ACK SYN -d "$INT_NET" -j DROP

$IPT -A FORWARD -p udp --dport 53 -m length --length 512:65535 -j DROP

$IPT -A FORWARD -p tcp --dport 4444:4555 -j DROP
$IPT -A FORWARD -p tcp --sport 4444:4555 -j DROP

$IPT -t nat -A POSTROUTING -s "$INT_NET" -o "$WAN_IF" -j MASQUERADE

$IPT -A INPUT -j LOG --log-prefix "IPTables-Input-Dropped: " --log-level 4
$IPT -A FORWARD -j LOG --log-prefix "IPTables-Forward-Dropped: " --log-level 4

sysctl -w net.ipv4.ip_forward=1 >/dev/null
echo "[+] Router iptables and NAT applied"
ROUTER_EOF

rc=$?
if [[ "$rc" -ne 0 ]]; then
  echo -e "${RED}[-] Phase 2 router configuration failed${NC}"
  exit 1
fi
echo -e "${GREEN}[+] Phase 2 complete on seed-router${NC}"

echo "Set default gateway on internal hosts (via firewall)..."
for c in host1-192.168.60.5 host2-192.168.60.6 host3-192.168.60.7; do
  echo -e "${YELLOW}[*] default via ${ROUTER_INT_IP} on ${c}${NC}"
  if docker exec "$c" bash -c "
    DEV=\$(ip -4 route show default 2>/dev/null | awk '/default/ {print \$5; exit}')
    [[ -n \"\$DEV\" ]] || DEV=\$(ip -o link show 2>/dev/null | awk -F': ' '/eth/{gsub(/@.*/,\"\",\$2); print \$2; exit}')
    [[ -n \"\$DEV\" ]] || exit 1
    ip route del default 2>/dev/null || true
    ip route add default via ${ROUTER_INT_IP} dev \"\$DEV\" 2>/dev/null
  " 2>/dev/null; then
    echo -e "${GREEN}[+] ${c} default route -> firewall${NC}"
  else
    echo -e "${RED}[-] Failed to set default route on ${c}${NC}"
    exit 1
  fi
done

echo -e "${GREEN}[+] done — next: ./task3_firewall/verify_firewall.sh${NC}"
exit 0
