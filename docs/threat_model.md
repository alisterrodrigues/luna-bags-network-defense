# Luna Bags — Threat Model


## Scope

This threat model covers Luna Bags' Docker-based e-commerce network infrastructure: public-facing web server (hostA, DMZ), internal business hosts (host1–3), router/firewall boundary, and WireGuard VPN tunnel.

Out of scope: Docker container escape, host OS security, physical security, supply chain attacks.

---

## Trust Boundaries

| Boundary | From | To | Assumption |
|---|---|---|---|
| 1 | Internet | Router perimeter | Zero trust — all traffic assumed hostile |
| 2 | Router | DMZ (hostA) | HTTP/HTTPS only permitted; all else dropped |
| 3 | DMZ | Internal | No direct path; WireGuard VPN with key auth required |
| 4 | Internal | Internet | Partial trust; HTTP, HTTPS, DNS, NTP permitted outbound |

---

## STRIDE Analysis

### Spoofing

| Threat | Attack Vector | Control |
|---|---|---|
| IP source spoofing | Packets with RFC1918/loopback source on external interface | iptables INPUT DROP on spoofed source ranges |
| ARP spoofing | Attacker poisons ARP cache to intercept traffic | Network segmentation limits blast radius; VPN encryption makes intercepted traffic useless |
| Credential spoofing | Brute-forced SSH or web credentials | Fail2Ban rate-limits and bans; SSH brute force cap on all containers |

### Tampering

| Threat | Attack Vector | Control |
|---|---|---|
| Data in transit | MITM interception of HTTP traffic | SSL/TLS enforced; HTTP redirects to HTTPS at vhost level |
| Web content injection | Attacker injects malicious script into response | HSTS prevents downgrade; CSP blocks inline script execution |
| Packet manipulation | Malformed or fragmented packets | iptables drops fragmented (`-f`) and invalid TCP flag combinations |

### Repudiation

| Threat | Attack Vector | Control |
|---|---|---|
| Attack denial | Attacker denies connection attempts | iptables LOG rules (`IPTables-Input-Dropped:`, `IPTables-Forward-Dropped:`) |
| WAF evasion claim | Attacker claims request was legitimate | ModSecurity audit log records every blocked request with rule ID, matched data, and timestamp |
| Brute force denial | Attacker denies repeated attempts | Fail2Ban ban log records IP, jail, and ban time |

### Information Disclosure

| Threat | Attack Vector | Control |
|---|---|---|
| Server version leakage | Apache `Server:` header reveals version | `ServerTokens Prod` reduces header to `Apache` only |
| Internal network discovery | Compromised DMZ host scans internal | iptables blocks DMZ→Internal; no route without VPN auth |
| HTTPS downgrade | Attacker intercepts first HTTP request | HSTS header forces HTTPS for 1 year; HTTP vhost does redirect only |
| Directory enumeration | Attacker browses web root | `Options -Indexes` returns 403; ModSecurity blocks path traversal |

### Denial of Service

| Threat | Attack Vector | Control |
|---|---|---|
| SYN flood | Thousands of SYN packets exhaust connection table | hashlimit 40/s, burst 80 on FORWARD to hostA ports 80/443 |
| ICMP flood | Ping flood from internal to DMZ | hashlimit 2/s, burst 5 on FORWARD scoped to internal interface |
| HTTP flood | High-volume requests to web server | Fail2Ban `apache-noscript` and `apache-overflows` jails |
| Scanner bots | Automated scanner traffic | Fail2Ban `apache-badbots` — 1 hit triggers 24h ban |
| SSH brute force | Repeated login attempts | Fail2Ban `sshd` — 3 failures in 60s triggers 300s ban |

### Elevation of Privilege

| Threat | Attack Vector | Control |
|---|---|---|
| SQL injection | Malicious SQL in URL parameters | ModSecurity OWASP CRS REQUEST-942 rules |
| Cross-site scripting | Malicious script in URL/body | ModSecurity REQUEST-941 rules; CSP prevents browser execution |
| Path traversal / LFI | `../../../../etc/passwd` in URL | ModSecurity REQUEST-930 rules |
| Remote code execution | `;cat /etc/passwd` in URL params | ModSecurity REQUEST-932 rules |
| Lateral movement | Compromised hostA pivots to internal | iptables FORWARD DROP on DMZ→Internal; VPN requires key auth |
| Reverse shell | Compromised app calls back to attacker C2 | Ports 4444–4555 blocked in both directions on FORWARD |

---

## Residual Risks

**Application-layer logic flaws** — ModSecurity blocks known signatures but cannot detect zero-day vulnerabilities in custom application code. Regular penetration testing is required.

**Compromised VPN credentials** — If hostA's WireGuard private key is stolen, an attacker gains VPN access to the internal network. Key rotation policy and host hardening are the mitigations.

**Container escape** — Docker container isolation is not in scope. Host-level seccomp, AppArmor, or rootless Docker would be required for a production deployment.

**Log exfiltration** — Container logs are stored on the container filesystem. A production deployment ships logs to a centralized SIEM before they can be tampered with.
