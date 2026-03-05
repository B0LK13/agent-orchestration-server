# Copilot Instructions

## What this repo is

A collection of Bash scripts for provisioning and operating a 3-VPS infrastructure at `theblackagency.cloud`. Scripts are run manually on target hosts — there is no CI/CD pipeline, build system, or test framework.

## Infrastructure layout

| Host | Public IP | Role | Deploy path |
|------|-----------|------|-------------|
| VPS-1 | 31.97.47.51 | Automation | `/opt/automation` |
| VPS-2 | 72.60.176.178 | Workspace | `/opt/workspace` |
| VPS-3 | 168.231.86.24 | Dev | `/opt/dev` |

VPS-1 runs the full Docker stack: **n8n → PostgreSQL → Redis**, plus Uptime Kuma, Gotify, Miniflux, Loki/Promtail, node-exporter, and cloudflared. All containers share a bridged `automation` network (`172.20.0.0/24`) with static IPs (postgres = `172.20.0.10`, redis = `172.20.0.11`). No container ports are exposed publicly — all external access goes through the Cloudflare tunnel.

WireGuard mesh (port 51820) connects all three VPS nodes to each other.

## Running / verifying deployments

```bash
# Deploy VPS-1 automation stack
sudo bash /home/deploy/Scripts/vps1_deploy.sh

# Start services after deploy (VPS-1)
cd /opt/automation && sudo docker compose up -d

# Check container health
sudo docker compose ps
sudo docker logs cloudflared | tail -20

# Test backup restore
LATEST=$(ls -1t /var/backups/vps/*.tar.gz | head -n1)
sudo tar -xzf "$LATEST" -C /tmp/restore-test

# Provision Cloudflare DNS records
CF_API_TOKEN=<token> bash provision-dns.sh
```

## Key conventions

- **All scripts require root or passwordless sudo.** The `deploy` user is granted `NOPASSWD: ALL` via `/etc/sudoers.d/deploy`.
- **`set -e` / `set -euo pipefail`** is used at the top of every script; keep that pattern when adding new scripts.
- **Secrets are generated at deploy time** with `openssl rand` and written to `$DEPLOY_PATH/.env` with `chmod 600`. Never hard-code passwords; the Cloudflare tunnel token is the one exception that must be filled in manually after deploy.
- **All containers have resource limits** (`deploy.resources.limits` for memory and CPU) and `security_opt: no-new-privileges:true`. Maintain these on any new service additions.
- **Service hostnames** follow `<service>.theblackagency.cloud`. New Cloudflare DNS entries must be added to the `HOSTNAMES` array in `provision-dns.sh`.
- **Backups** run from `/usr/local/bin/vps-backup.sh` (installed by `backup.sh`), archive to `/var/backups/vps/`, and retain the last 7 tarballs.
- **WireGuard setup is two-phase**: run `wireguard_setup.sh` on each VPS first to generate keys, then exchange public keys and configure peers separately.

## Cloudflare tunnel

Tunnel ID: `e6710ff6-b8d5-47b5-9c04-4982e6b4cd66`  
All CNAME records point to `<tunnel-id>.cfargotunnel.com` with proxying enabled. The `cloudflared` container inside the Docker stack uses `CLOUDFLARE_TUNNEL_TOKEN` from `.env`.

## AI tooling scripts

`setup_ai_agents.sh` installs Claude Code, OpenCode (`opencode-ai`), and Factory Droid globally via npm, then installs VS Code extensions (Copilot, Continue, Google Cloud Code). `install_opencode_pro.sh` is a more robust installer with configurable install methods (`auto|brew|npm|binary|skip`), config hardening, and backup/rollback support.
