# Luna Bags Network Defense

<p align="center">
  <img src="https://img.shields.io/badge/Defense_Layers-6-blue?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Tool-Apache%2FOpenSSL-red?style=for-the-badge&logo=apache&logoColor=white" />
  <img src="https://img.shields.io/badge/Tool-iptables-EE0000?style=for-the-badge&logo=linux&logoColor=white" />
  <img src="https://img.shields.io/badge/Tool-WireGuard-88171A?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Tool-Fail2Ban-orange?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Tool-ModSecurity%2FOWASP_CRS-black?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Platform-Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white" />
</p>

---

## What This Is

A fully reproducible Docker-based network security implementation for a fictional e-commerce client — Luna Bags. The engagement covers the full defense stack: from web server hardening at the application layer down through firewall policy, VPN tunneling, intrusion detection, and a Layer 7 WAF.

The environment runs on SEED Ubuntu VM across five Docker containers on two isolated networks. Each security layer is implemented as a standalone, idempotent script that can be run independently and verified with a dedicated test script that simulates real attacks.

This is not a configuration walkthrough — every verify script fires actual attack payloads and confirms they are blocked.

---

## The Client

Luna Bags is a growing e-commerce retailer of eco-friendly bags transitioning to a fully digital business model. The engagement objective: design and implement a network security architecture that protects customer data, secures internal business operations, and withstands common attack vectors — while keeping the web store accessible to legitimate users.

---

## Network Topology

<p align="center">
  <img src="./docs/network_topology.png" alt="Luna Bags network topology diagram" width="600" />
</p>

| Container | IP | Role |
|---|---|---|
| hostA-10.9.0.5 | 10.9.0.5 | Web server — Apache, SSL, WAF, IDS |
| seed-router | 10.9.0.11 / 192.168.60.11 | Firewall, VPN server, NAT gateway |
| host1-192.168.60.5 | 192.168.60.5 | Internal workstation |
| host2-192.168.60.6 | 192.168.60.6 | Internal workstation |
| host3-192.168.60.7 | 192.168.60.7 | Internal workstation |

---

## Security Layers

### Task 1 — Apache Web Server Hardening
Apache 2.4 installed and hardened on hostA. Server version information suppressed (`ServerTokens Prod`). HTTP redirected permanently to HTTPS. Directory listing disabled. Six security headers enforced on all responses: HSTS, X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy, Content-Security-Policy.

### Task 2 — SSL/TLS Certificate
Self-signed 2048-bit RSA certificate generated with OpenSSL. Certificate subject matches the server IP (`CN=10.9.0.5`, `O=Luna Bags`). Apache configured with a dedicated SSL virtual host on port 443 with session caching. All HTTP traffic redirected to HTTPS at the vhost level.

### Task 3 — iptables Firewall
Two-phase implementation. Phase 1 hardens each container individually: Telnet service disabled (inetd stopped, `inetd.conf` patched), host-level SYN flood and ICMP flood rate limiting, SSH brute force protection. Phase 2 applies router-level policy: default DROP on INPUT and FORWARD, explicit zone rules, attack mitigations covering NULL/FIN/Xmas scan protection, IP spoofing, DNS amplification, and reverse shell port blocking (4444–4555).

### Task 4 — WireGuard VPN
WireGuard tunnel between seed-router (server, `10.200.200.1`) and hostA (client, `10.200.200.2`). Provides the only permitted path from the DMZ to the internal network. Requires cryptographic key authentication. Firewall updated to allow UDP 51820 and forward VPN traffic to `192.168.60.0/24`. Internal hosts reachable from hostA via VPN with 0% packet loss.

### Task 5 — Fail2Ban IDS
Fail2Ban deployed on both hostA and seed-router. Four active jails: `sshd` (3 failures/60s, ban 300s), `apache-auth` (5 failures/60s, ban 600s), `apache-badbots` (1 hit, ban 24h), `apache-noscript` (5 hits/60s, ban 300s). Verify script simulates a scanner user-agent request and confirms the source IP is banned.

### Task 6 — ModSecurity WAF + OWASP CRS
ModSecurity installed as an Apache module with OWASP Core Rule Set v3.3.5 in enforcement mode (`SecRuleEngine On`). Protects against SQL injection, XSS, path traversal, RCE, and known scanner fingerprints. All blocks logged to `/var/log/apache2/modsec_audit.log`. Verify script fires five attack payloads from the router and confirms each returns HTTP 403.

---

## Repository Structure

```
luna-bags-network-defense/
├── README.md
├── report/
│   └── Luna_Bags_Network_Defense_Report.md
├── docs/
│   ├── network_topology.png
│   ├── architecture.md
│   ├── threat_model.md
│   └── security_headers.md
├── evidence/
│   └── (screenshots)
└── lab/
    ├── docker-compose.yml
    ├── hostA_entrypoint/start_apache.sh
    ├── router_entrypoint/start_router.sh
    ├── task1_apache/verify_apache.sh
    ├── task2_ssl/verify_ssl.sh
    ├── task3_firewall/
    │   ├── firewall_rules.sh
    │   ├── verify_firewall.sh
    │   ├── comprehensive_scan.sh
    │   └── access_control_policies.md
    ├── task4_vpn/
    │   ├── install_wireguard.sh
    │   ├── configure_wireguard.sh
    │   ├── start_vpn.sh
    │   └── verify_vpn.sh
    ├── task5_ids/
    │   ├── install_fail2ban.sh
    │   ├── configure_fail2ban.sh
    │   └── verify_fail2ban.sh
    └── task6_waf/
        ├── install_modsecurity.sh
        ├── configure_modsecurity.sh
        └── verify_waf.sh
```

---

## Running the Lab

### Prerequisites
- Docker and Docker Compose
- Linux host (tested on SEED Ubuntu VM, Ubuntu 22.04)
- Outbound internet access from containers (for apt installs on first run)

### Step 1 — Start the environment

```bash
cd lab/
docker compose up -d
```

Wait ~60 seconds for hostA to finish installing Apache. Verify it started cleanly:

```bash
docker logs hostA-10.9.0.5 | tail -5
```

Expected: `[+] config OK` and `Starting Apache in foreground...`

### Step 2 — Verify Tasks 1 and 2

```bash
./task1_apache/verify_apache.sh   # expected: 8/8 passed
./task2_ssl/verify_ssl.sh         # expected: 6/6 passed
```

### Step 3 — Firewall

```bash
./task3_firewall/comprehensive_scan.sh before
./task3_firewall/firewall_rules.sh
./task3_firewall/comprehensive_scan.sh after
./task3_firewall/verify_firewall.sh
```

### Step 4 — WireGuard VPN

```bash
./task4_vpn/install_wireguard.sh
./task4_vpn/configure_wireguard.sh
./task4_vpn/start_vpn.sh
./task4_vpn/verify_vpn.sh
```

### Step 5 — Fail2Ban

```bash
./task5_ids/install_fail2ban.sh
./task5_ids/configure_fail2ban.sh
./task5_ids/verify_fail2ban.sh
```

### Step 6 — ModSecurity WAF

```bash
./task6_waf/install_modsecurity.sh
./task6_waf/configure_modsecurity.sh
./task6_waf/verify_waf.sh
```

---

## Full Technical Report

> **[→ Luna Bags Network Defense — Full Implementation Report](./report/Luna_Bags_Network_Defense_Report.md)**

---

*Developed by Alister A. Rodrigues. All testing conducted in an isolated lab environment.*
