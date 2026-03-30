# Luna Bags Network Defense — Architecture

---

## Network Topology

![Luna Bags Network Topology](./network_topology.png)
*Figure 1 — Luna Bags lab network topology. Two isolated Docker bridge networks mirror a real enterprise DMZ topology. The router is dual-homed and is the sole enforcement point for all inter-zone traffic. No direct route exists from DMZ to internal — the only permitted path requires a valid WireGuard key exchange.*

| Zone | Subnet | Hosts | Purpose |
|---|---|---|---|
| DMZ | 10.9.0.0/24 | hostA (10.9.0.5) | Public-facing web server |
| Internal | 192.168.60.0/24 | host1–3 (.5/.6/.7) | Business workstations |
| VPN Tunnel | 10.200.200.0/24 | router (.1), hostA (.2) | Authenticated cross-zone path |

---

## Security Design Philosophy

**Defense in Depth** — No single control is relied upon exclusively. Each layer assumes the previous layer may be bypassed. An attacker who evades the firewall still faces the WAF. An attacker who exploits a web vulnerability still cannot reach internal systems directly.

**Least Privilege** — Every host, service, and network zone has access only to what it requires to function. The web server in the DMZ cannot initiate connections to the internal network except through the authenticated VPN tunnel.

---

## Layer-by-Layer Security Model

| Layer | Control | Protects Against |
|---|---|---|
| 1 | Apache hardening + security headers | Version fingerprinting, clickjacking, MIME sniffing, XSS via browser policy |
| 2 | SSL/TLS | Data interception in transit, MITM, downgrade attacks |
| 3 | iptables firewall | Network-level DoS, zone isolation, port scanning, spoofing, reverse shells |
| 4 | WireGuard VPN | Unauthorized DMZ→internal access, unencrypted cross-zone traffic |
| 5 | Fail2Ban IDS | Brute force, scanner bots, repeated failure exploitation |
| 6 | ModSecurity + OWASP CRS | SQLi, XSS, RCE, path traversal, scanner UA fingerprints |

For the full STRIDE threat model mapped to each layer, see [docs/threat_model.md](./threat_model.md).

---

## Key Design Decisions

**Why self-signed certificates?**
Luna Bags operates without a registered domain in this lab. Self-signed certificates provide identical encryption to CA-signed certificates — the only difference is the trust chain. A production deployment replaces these with Let's Encrypt or an organization CA.

**Why WireGuard over OpenVPN?**
WireGuard's codebase is ~4,000 lines vs ~70,000 for OpenVPN. Smaller codebase means smaller attack surface, faster security auditing, and significantly simpler configuration. It is the standard recommendation for Linux VPN deployments.

**Why Fail2Ban if iptables already exists?**
iptables operates on individual packets and has no visibility into application logs. Fail2Ban reads log files and dynamically inserts iptables ban rules when it detects patterns — like 5 failed Apache auth attempts from the same IP over 60 seconds. This catches attacks that are valid at the packet level individually but malicious in aggregate.

**Why ModSecurity + OWASP CRS?**
iptables operates at Layer 3/4. A well-formed HTTP request to port 443 passes the firewall regardless of what the URL parameters contain. ModSecurity runs inside Apache at Layer 7 and inspects every request against 900+ OWASP CRS rules before Apache processes it. This closes the application-layer gap entirely.

**Why OWASP CRS v3.3.x and not v4?**
CRS v4 requires a newer ModSecurity (v3.x) than the `libapache2-mod-security2` package available on Ubuntu 22.04. v3.3.5 provides full production coverage and is compatible with the lab environment.

**Why iptables-legacy on containers?**
The nf_tables kernel module used by the default `iptables` binary on newer systems is not available inside Docker containers that don't share the host kernel's module set. The `iptables-legacy` frontend uses the older x_tables interface which works reliably inside containers. The router container uses `privileged: true` which gives it full iptables access.

---

For HTTP security header documentation, see [docs/security_headers.md](./security_headers.md).
