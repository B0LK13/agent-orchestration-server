# Agent Orchestration Server

Infrastructure-as-code scripts for a 3-VPS automation and AI agent orchestration stack at **theblackagency.cloud**.

## Architecture

```
VPS-1 (Automation — 31.97.47.51)       VPS-2 (Workspace — 72.60.176.178)
├── n8n (workflow automation)           └── /opt/workspace
├── PostgreSQL 16
├── Redis 7                             VPS-3 (Dev — 168.231.86.24)
├── Uptime Kuma (monitoring)            └── /opt/dev
├── Gotify (push notifications)
├── Miniflux (RSS reader)                      All 3 nodes connected via
├── Loki + Promtail (log aggregation)          WireGuard mesh VPN (:51820)
├── node-exporter (metrics)
└── cloudflared (Cloudflare tunnel)
```

All services run on Docker in a private bridge network (`172.20.0.0/24`).  
External access is exclusively via Cloudflare Tunnel — no ports exposed to the internet.

## Services & URLs

| Service | URL |
|---------|-----|
| n8n | https://n8n.theblackagency.cloud |
| Uptime Kuma | https://status.theblackagency.cloud |
| Gotify | https://notify.theblackagency.cloud |
| Miniflux | https://rss.theblackagency.cloud |
| SSH/Terminal | https://terminal.theblackagency.cloud |

## Quick Start

### VPS-1 — Deploy automation stack
```bash
sudo bash vps1_deploy.sh
# Then set your Cloudflare tunnel token:
sudo nano /opt/automation/.env   # replace CLOUDFLARE_TUNNEL_TOKEN
cd /opt/automation && sudo docker compose up -d
```

### All VPS — WireGuard mesh VPN
```bash
# Run on each VPS, then exchange public keys between nodes
sudo bash wireguard_setup.sh
```

### Cloudflare DNS
```bash
CF_API_TOKEN=<your-token> bash provision-dns.sh
```

### AI agent tooling
```bash
bash setup_ai_agents.sh          # Claude Code, OpenCode, Factory Droid, VS Code extensions
bash install_opencode_pro.sh     # Production OpenCode installer with hardened config
```

## Script Reference

| Script | Purpose | Target |
|--------|---------|--------|
| `vps1_deploy.sh` | Full automation stack deploy | VPS-1 (root) |
| `wireguard_setup.sh` | WireGuard mesh VPN setup | Each VPS (root) |
| `provision-dns.sh` | Cloudflare DNS CNAME provisioner | Any host with curl |
| `install_cloudflared_connector.sh` | Install cloudflared daemon | Any VPS |
| `backup.sh` | Install `/usr/local/bin/vps-backup.sh` | Any VPS (root) |
| `setup_ai_agents.sh` | Install AI coding agents & VS Code extensions | Dev machine |
| `install_opencode_pro.sh` | Production OpenCode installer | Dev machine |
| `ssh-fix.sh` | Fix deploy user sudoers + UFW SSH rule | VPS (root) |
| `verification.sh` | Post-deploy health check commands | VPS-1 |
| `test_docker.sh` | Quick Docker sanity check | Any VPS |
| `quick-restore-test.sh` | Test latest backup tarball restore | Any VPS |

## Backup

Backups run from `/usr/local/bin/vps-backup.sh` (installed by `backup.sh`).  
Archives: `/var/backups/vps/` — last 7 retained.  
Covers: `/etc /home /root /opt /srv /var/lib/docker/volumes`

```bash
# Test restore
LATEST=$(ls -1t /var/backups/vps/*.tar.gz | head -n1)
sudo tar -xzf "$LATEST" -C /tmp/restore-test
```

## Environment & Secrets

Secrets are generated at deploy time with `openssl rand` and written to `$DEPLOY_PATH/.env` (`chmod 600`).  
The **Cloudflare tunnel token** must be set manually after first deploy.

```bash
sudo cat /opt/automation/.env    # VPS-1 credentials
```

## Requirements

- Ubuntu/Debian VPS with root or passwordless sudo access
- Docker + Docker Compose v2
- `deploy` user created (scripts use `deploy:deploy` ownership)
- Cloudflare account with tunnel configured for `theblackagency.cloud`
