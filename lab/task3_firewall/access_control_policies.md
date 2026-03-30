# Luna Bags — Network Access Control Policies

This document defines the firewall access control policy for Luna Bags'
DMZ and internal network. These rules are implemented in `firewall_rules.sh`.

---

## Default Policy

All traffic is denied unless explicitly permitted. The router runs iptables
with `INPUT DROP` and `FORWARD DROP` as defaults.

---

## Zone Definitions

| Zone | Subnet | Purpose |
|---|---|---|
| DMZ | 10.9.0.0/24 | Public-facing web server |
| Internal | 192.168.60.0/24 | Business operations |
| Internet | 0.0.0.0/0 (non-RFC1918) | External access |

---

## Permitted Traffic

### Internet → DMZ
| Protocol | Port | Destination | Rule |
|---|---|---|---|
| TCP | 80 | 10.9.0.5 | Allow HTTP to web server |
| TCP | 443 | 10.9.0.5 | Allow HTTPS to web server |

### Internal → DMZ
| Protocol | Port | Destination | Rule |
|---|---|---|---|
| TCP | 80 | 10.9.0.5 | Allow HTTP from internal hosts |
| TCP | 443 | 10.9.0.5 | Allow HTTPS from internal hosts |
| ICMP | echo-request | 10.9.0.0/24 | Rate-limited ping (1/s, burst 3) |

### Internal → Internet
| Protocol | Port | Destination | Rule |
|---|---|---|---|
| TCP | 80, 443 | Non-RFC1918 | Allow web browsing |
| UDP | 53 | Non-RFC1918 | Allow DNS resolution |
| UDP | 123 | Non-RFC1918 | Allow NTP time sync |

### Router Management
| Protocol | Port | Rule |
|---|---|---|
| TCP | 22 | Allow SSH to router from any source |

---

## Blocked Traffic

| Traffic Type | Rule |
|---|---|
| DMZ → Internal (direct) | Blocked — DMZ must use VPN to reach internal |
| Telnet (port 23) | Blocked network-wide on all hosts and router |
| Reverse shell ports 4444–4555 | Blocked in both directions on FORWARD chain |
| RFC1918 source addresses on INPUT | Anti-spoofing drop |
| NULL / FIN / Xmas TCP scans | Dropped by malformed flag rules |
| SYN flood above 40/s to hostA | Rate-limited with hashlimit, excess dropped |
| ICMP flood above 1/s | Rate-limited, excess dropped |
| DNS responses over 512 bytes | Dropped to prevent amplification |

---

## VPN Exception

The WireGuard VPN tunnel (UDP 51820) creates an authenticated path from
hostA in the DMZ to the internal network. This is the only permitted
DMZ-to-internal communication path, and it requires cryptographic key
authentication on both sides.
