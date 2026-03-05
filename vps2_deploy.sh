#!/bin/bash
# VPS-2 Workspace Stack Deployment Script
# Run on VPS-2 (72.60.176.178) as root or with sudo
#
# Services deployed:
#   code-server  — VS Code in the browser
#   Gitea        — self-hosted Git server
#   Portainer    — Docker management UI
#   cloudflared  — Cloudflare tunnel (zero-trust access)

set -e

SCRIPT_DIR="/opt/workspace"
DOMAIN="theblackagency.cloud"

echo "========================================"
echo "VPS-2 Workspace Stack Deployment"
echo "========================================"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

echo "=== Creating directory structure ==="
mkdir -p "$SCRIPT_DIR"/{code-server/data,gitea/{data,ssh},portainer/data,cloudflared,backups}
chown -R deploy:deploy "$SCRIPT_DIR"
chmod 750 "$SCRIPT_DIR"
chmod 700 "$SCRIPT_DIR/backups"
echo "✓ Directories created"

echo "=== Generating secure passwords ==="
GITEA_DB_PASSWORD=$(openssl rand -base64 32)
GITEA_SECRET_KEY=$(openssl rand -hex 32)
CODE_SERVER_PASSWORD=$(openssl rand -base64 16)

cat > "$SCRIPT_DIR/.env" << EOF
# Cloudflare Tunnel Token — fill in before starting services
CLOUDFLARE_TUNNEL_TOKEN=YOUR_TUNNEL_TOKEN_HERE

# code-server
CODE_SERVER_PASSWORD=$CODE_SERVER_PASSWORD

# Gitea
GITEA_DB_PASSWORD=$GITEA_DB_PASSWORD
GITEA_SECRET_KEY=$GITEA_SECRET_KEY
EOF

chmod 600 "$SCRIPT_DIR/.env"

if grep -q "YOUR_TUNNEL_TOKEN_HERE" "$SCRIPT_DIR/.env"; then
    echo ""
    echo "❌ ERROR: Cloudflare tunnel token is not set!"
    echo "   Edit $SCRIPT_DIR/.env and replace YOUR_TUNNEL_TOKEN_HERE with your real token."
    echo "   Get your token at: https://one.dash.cloudflare.com/ → Networks → Tunnels"
    rm -f "$SCRIPT_DIR/.env"
    exit 1
fi

echo "✓ Environment file created at $SCRIPT_DIR/.env"

echo "=== Creating docker-compose.yml ==="
cat > "$SCRIPT_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

networks:
  workspace:
    driver: bridge
    ipam:
      config:
        - subnet: 172.21.0.0/24

services:
  code-server:
    image: codercom/code-server:latest
    container_name: code-server
    restart: unless-stopped
    env_file: .env
    environment:
      - PASSWORD=${CODE_SERVER_PASSWORD}
      - TZ=UTC
    volumes:
      - ./code-server/data:/home/coder/.local/share/code-server
      - /home/deploy:/home/coder/workspace:rw
    networks:
      - workspace
    ports:
      - "127.0.0.1:8080:8080"
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '1.0'
    security_opt:
      - no-new-privileges:true

  gitea-db:
    image: postgres:16-alpine
    container_name: gitea-db
    restart: unless-stopped
    env_file: .env
    environment:
      - POSTGRES_USER=gitea
      - POSTGRES_PASSWORD=${GITEA_DB_PASSWORD}
      - POSTGRES_DB=gitea
    volumes:
      - ./gitea/data/postgres:/var/lib/postgresql/data
    networks:
      workspace:
        ipv4_address: 172.21.0.10
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.3'
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U gitea -d gitea"]
      interval: 10s
      timeout: 5s
      retries: 5

  gitea:
    image: gitea/gitea:latest
    container_name: gitea
    restart: unless-stopped
    env_file: .env
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=postgres
      - GITEA__database__HOST=172.21.0.10:5432
      - GITEA__database__NAME=gitea
      - GITEA__database__USER=gitea
      - GITEA__database__PASSWD=${GITEA_DB_PASSWORD}
      - GITEA__security__SECRET_KEY=${GITEA_SECRET_KEY}
      - GITEA__server__DOMAIN=git.theblackagency.cloud
      - GITEA__server__ROOT_URL=https://git.theblackagency.cloud
      - GITEA__server__SSH_DOMAIN=git.theblackagency.cloud
    volumes:
      - ./gitea/data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    networks:
      - workspace
    ports:
      - "127.0.0.1:3000:3000"
      - "127.0.0.1:2222:22"
    depends_on:
      gitea-db:
        condition: service_healthy
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
    security_opt:
      - no-new-privileges:true

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./portainer/data:/data
    networks:
      - workspace
    ports:
      - "127.0.0.1:9443:9443"
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.25'
    security_opt:
      - no-new-privileges:true

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    env_file: .env
    command: tunnel --no-autoupdate run --token ${CLOUDFLARE_TUNNEL_TOKEN}
    networks:
      - workspace
    deploy:
      resources:
        limits:
          memory: 128M
    security_opt:
      - no-new-privileges:true
EOF

echo "✓ docker-compose.yml created"

chown -R deploy:deploy "$SCRIPT_DIR"
chmod 600 "$SCRIPT_DIR/.env"

echo ""
echo "========================================"
echo "✅ VPS-2 Workspace Stack Ready!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Run: cd $SCRIPT_DIR && docker compose up -d"
echo "2. Access services at:"
echo "   - https://code.theblackagency.cloud   (code-server)"
echo "   - https://git.theblackagency.cloud    (Gitea)"
echo "   - https://docker.theblackagency.cloud (Portainer)"
echo ""
echo "Default credentials saved in: $SCRIPT_DIR/.env"
