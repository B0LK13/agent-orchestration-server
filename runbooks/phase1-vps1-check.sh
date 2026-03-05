#!/usr/bin/env bash
# Run on VPS-1 — paste the output back
echo "===== HOSTNAME & UPTIME ====="
hostname && uptime

echo ""
echo "===== DOCKER CONTAINERS ====="
docker compose -f /opt/automation/docker-compose.yml ps 2>/dev/null || docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker not running or /opt/automation not found"

echo ""
echo "===== CLOUDFLARED STATUS ====="
docker logs cloudflared 2>/dev/null | tail -10 || echo "cloudflared container not found"

echo ""
echo "===== DISK SPACE ====="
df -h / /opt 2>/dev/null | head -5

echo ""
echo "===== /opt DIRECTORIES ====="
ls /opt/ 2>/dev/null

echo ""
echo "===== WIREGUARD STATUS ====="
wg show 2>/dev/null || echo "WireGuard not configured yet"

echo ""
echo "===== OPEN PORTS ====="
ss -tlnp | grep -E ':22|:2222|:80|:443|:51820|:5678|:3001|:8080|:3100|:9100'
