#!/usr/bin/env bash
# Run on VPS-2 as root/sudo
# Usage: CF_TOKEN=<your-new-token> bash phase3-vps2-deploy.sh

CF_TOKEN="${CF_TOKEN:-${1:-}}"
if [[ -z "$CF_TOKEN" ]]; then
    echo "ERROR: provide CF_TOKEN=<token> bash phase3-vps2-deploy.sh"
    exit 1
fi

# Download and run the deploy script
curl -fsSL https://raw.githubusercontent.com/B0LK13/agent-orchestration-server/main/vps2_deploy.sh -o /tmp/vps2_deploy.sh
chmod +x /tmp/vps2_deploy.sh

# Patch the token placeholder before running
sed -i "s/YOUR_TUNNEL_TOKEN_HERE/$CF_TOKEN/" /tmp/vps2_deploy.sh

# Remove the exit-if-placeholder guard (we've already set the token)
bash /tmp/vps2_deploy.sh

echo ""
echo "===== STARTING SERVICES ====="
cd /opt/workspace && docker compose up -d

echo ""
echo "===== CONTAINER STATUS ====="
docker compose ps
