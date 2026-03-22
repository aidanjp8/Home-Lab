# Home Lab Documentation

**Maintainer:** Aidan Petta  
**Last Updated:** March 2026  
**Status:** Active Development

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Hardware](#hardware)
4. [Virtualization Layer](#virtualization-layer)
5. [Network Configuration](#network-configuration)
6. [Security Posture](#security-posture)
7. [Maintenance Procedures](#maintenance-procedures)
8. [Scripts](#scripts)
9. [Troubleshooting Runbook](#troubleshooting-runbook)
10. [Security Notice](#security-notice--public-repository-disclosure)

---

## Overview

This document describes the architecture, configuration, and operational procedures
for a self-hosted hybrid Windows/Linux home lab environment. The lab was originally
started as a small project focused on self-hosting personal applications and services.
It has since evolved to simulate enterprise IT infrastructure, providing hands-on
experience with virtualization, containerization, networking, and systems administration.

**Primary Objectives:**
- Gain practical experience with enterprise-grade tools and workflows
- Host and manage self-hosted services in a production-like environment
- Develop structured troubleshooting and documentation habits

---

## Architecture
> network diagram

**Environment Summary:**

| Layer | Technology | Purpose |
|---|---|---|
| Hypervisor | Proxmox VE | VM and LXC container management |
| DNS | Pi-hole (Raspberry Pi 5) | Internal DNS resolution and ad blocking |
| Networking | TCP/IP, vmbr0 bridge | LAN routing and container networking |
| Containerization | Docker / Docker Compose | Application deployment |
| Remote Access | Tailscale VPN | Zero-trust remote connectivity |
| OS Environments | Ubuntu, Raspberry Pi OS | Workload separation |

**Current Scale:** 2 physical nodes actively hosting self-hosted services.
A third node is planned for lab expansion (Active Directory, SIEM, networking projects).

---

## Hardware

### Node 1 — Primary Services Host (Proxmox)

| Component | Specification |
|---|---|
| Host Machine | Dell OptiPlex 7050)_ |
| CPU | _(e.g., Intel Core i7-7700)_ |
| RAM | _(e.g., 16GB DDR4)_ |
| Storage | _(e.g., 512GB SSD)_ |
| Role | Primary hypervisor — LXC container workloads |

### Node 2 — Raspberry Pi 5

| Component | Specification |
|---|---|
| Host Machine | Raspberry Pi 5 |
| CPU | Broadcom BCM2712, quad-core Arm Cortex-A76 @ 2.4GHz (64-bit) |
| RAM | 16GB LPDDR4X |
| Storage | External 1TB SSD |
| Role | Internal DNS (Pi-hole) and self-hosted services |

### Node 3 — Secondary Services Host (UnRaid)

| Component | Specification |
|---|---|
| Host Machine | HP EliteDesk |
| Role | Lab expansion — Active Directory, Wazuh SIEM, networking experiments |
| Storage | 1TB Internal SSD |

---

## Virtualization Layer

**Platform:** Proxmox Virtual Environment  
**Proxmox Host:** `pve.[REDACTED].local`

> No VMs currently deployed. All workloads run as LXC containers on Node 1.
> Node 2 (Raspberry Pi 5) runs services natively on Raspberry Pi OS.

### LXC Containers — Node 1

| CT ID | Name | Status | Purpose |
|---|---|---|---|
| 101 | `jellyfin` | Running | Media server |
| 103 | `immich` | Stopped | Photo management (backup instance) |
| 104 | `arr-stack` | Running | Media automation (Sonarr/Radarr/etc.) |
| 106 | `immichF` | Running | Immich (primary instance) |

### Native Services — Node 2 (Raspberry Pi 5)

| Service | Status | Purpose |
|---|---|---|
| Pi-hole | Running | Internal DNS resolver and network-wide ad blocking |
| _(additional services)_ | — | _(add as deployed)_ |

| Service | Status | Purpose |
|---|---|---|
| Personal Finance Tracker | Developing |  |
| _(additional services)_ | — | _(add as deployed)_ |
---

## Network Configuration

**Topology:** Flat LAN, Proxmox containers bridged via `vmbr0`, Pi 5 on LAN  
**IP Scheme:** `192.168.0.0/24`  
**Remote Access:** Tailscale VPN

### DNS

- **Internal DNS Server:** Pi-hole on Raspberry Pi 5 (`192.168.0.x`)
- **Upstream Resolvers:** Cloudflare `1.1.1.1`, Google `8.8.8.8`
- **Local Domain:** `[REDACTED].local`
- **Fallback:** Router falls back to `1.1.1.1` if Pi-hole is unreachable
- **Ad Blocking:** Network-wide via Pi-hole DNS filtering

### Key Hosts

| Hostname | IP Address | Role |
|---|---|---|
| `pve.[REDACTED].local` | 192.168.0.x | Proxmox hypervisor (Node 1) |
| `pi.[REDACTED].local` | 192.168.0.x | Raspberry Pi 5 — Pi-hole / services (Node 2) |
| `jellyfin.[REDACTED].local` | 192.168.0.x | Jellyfin media server |
| `arr-stack.[REDACTED].local` | 192.168.0.x | Arr-stack media automation |
| `immich.[REDACTED].local` | 192.168.0.x | Immich photo management |

---


## Security Posture

- Internal services are not exposed to the public internet
- Remote access handled exclusively via Tailscale VPN — no open inbound ports on WAN
- SSH access restricted to key-based authentication; password auth disabled
- User accounts follow principle of least privilege
- Pi-hole DNS fallback configured so network remains functional if DNS container goes offline
- Regular OS patching schedule
- All credentials and secrets managed via environment variables — never hardcoded

---

## Maintenance Procedures

### OS Patching

```bash
# Debian/Ubuntu / Raspberry Pi OS
sudo apt update && sudo apt upgrade -y

# Proxmox host
apt update && apt dist-upgrade -y
```

### Pi-hole Updates

```bash
# Update Pi-hole application
pihole -up

# Update block lists
pihole -g
```

### Docker Updates

```bash
# Pull latest images and recreate containers
docker compose pull
docker compose up -d
```

### Backup Strategy

| Asset | Backup Method | Frequency | Retention |
|---|---|---|---|
| Proxmox CTs | Proxmox Backup Server / vzdump | Weekly | 2 copies |
| Docker volumes | rsync to secondary drive | Daily | 7 days |
| Pi-hole config | `pihole -a teleporter` export | Monthly | 2 copies |
| Config files | Git repository | On change | Full history |

---

## Scripts
### Scripts
| Node | Description | Container | Path | Script |
|---|---|---|---|---|
---
## Troubleshooting Runbook

### Service Not Responding

1. Verify container is running: `pct list` or Proxmox UI
2. Check service logs: `docker logs <container_name>`
3. Confirm network connectivity: `ping <host>`, `curl <endpoint>`
4. Review firewall rules
5. Restart service if no config changes needed: `docker compose restart <service>`

### DNS Resolution Failure

1. Confirm Pi-hole is running on Node 2: `systemctl status pihole-FTL`
2. Test resolution directly: `nslookup <hostname> 192.168.0.x`
3. If Pi-hole is down, verify router fallback DNS (`1.1.1.1`) is resolving: `nslookup google.com 1.1.1.1`
4. Check Pi-hole query log for blocked or failed lookups: Pi-hole admin UI → Query Log
5. Check `/etc/resolv.conf` on affected container
6. Review Proxmox host DNS config if host-level resolution fails

### Container Won't Start

1. Check Proxmox task log for error output
2. Verify storage availability on the host: `df -h`
3. Attempt console access via Proxmox web UI: `pct enter <CTID>`
4. Review container logs: `journalctl -xe`

### Tailscale Connectivity Lost

1. Verify Tailscale service is running: `systemctl status tailscaled`
2. Re-authenticate if needed: `tailscale up`
3. Check Tailscale admin console for node status 
4. Confirm firewall is not blocking Tailscale traffic

### Pi-hole Not Blocking / Resolving

1. Check FTL service status: `systemctl status pihole-FTL`
2. Verify clients are using Pi-hole IP as DNS (check router DHCP settings)
3. Update gravity (block lists): `pihole -g`
4. Check for upstream resolver issues: `pihole -d` (debug log)
5. Restart Pi-hole if needed: `pihole restartdns`

---

## Security Notice — Public Repository Disclosure

This repository is published for portfolio purposes. The following has been omitted to protect this environment:

| Omitted Item | Reason |
|---|---|
| WAN / Public IP address | Prevents direct targeting |
| Tailscale node IPs and auth keys | Prevents unauthorized VPN access |
| Internal hostnames and local domain | Reduces reconnaissance surface |
| Service credentials and API keys | Stored in `.env` files, excluded from repo |
| MAC addresses | Fingerprinting risk |

Private RFC-1918 ranges (`192.168.x.x`, `10.x.x.x`), container IDs, service names, and general architecture are safe to publish and present no external attack surface.

### Secret Management

All sensitive values referenced in service configurations use the following pattern:

```bash
# .env file (never committed to version control)
SERVICE_PASSWORD=your_password_here
API_KEY=your_api_key_here
```

```yaml
# docker-compose.yml (safe to commit)
environment:
  - PASSWORD=${SERVICE_PASSWORD}
  - API_KEY=${API_KEY}
```

### .gitignore

The following entries are enforced in `.gitignore`:

```
.env
*.env
.env.*
**/secrets/
**/credentials/
```

---

## References

- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Docker Compose Reference](https://docs.docker.com/compose/)
- [Pi-hole Documentation](https://docs.pi-hole.net/)
- [Tailscale Documentation](https://tailscale.com/kb/)
- [CompTIA Network+ Study Guide](https://www.comptia.org/certifications/network)
