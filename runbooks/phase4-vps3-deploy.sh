#!/usr/bin/env bash
# Run on VPS-3 as root/sudo
# Usage: CF_TOKEN=<your-new-token> bash phase4-vps3-deploy.sh

CF_TOKEN="${CF_TOKEN:-${1:-}}"
if [[ -z "$CF_TOKEN" ]]; then
    echo "ERROR: provide CF_TOKEN=<token> bash phase4-vps3-deploy.sh"
    exit 1
fi

curl -fsSL https://raw.githubusercontent.com/B0LK13/agent-orchestration-server/main/vps3_deploy.sh -o /tmp/vps3_deploy.sh
chmod +x /tmp/vps3_deploy.sh
sed -i "s/YOUR_TUNNEL_TOKEN_HERE/$CF_TOKEN/" /tmp/vps3_deploy.sh
bash /tmp/vps3_deploy.sh

echo ""
echo "===== STARTING SERVICES ====="
cd /opt/dev && docker compose up -d

echo ""
echo "===== PULLING OLLAMA MODELS ====="
docker exec ollama ollama pull llama3.2 &
docker exec ollama ollama pull nomic-embed-text &
wait

echo ""
echo "===== CONTAINER STATUS ====="
docker compose ps
