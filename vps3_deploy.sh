#!/bin/bash
# VPS-3 Dev Stack Deployment Script
# Run on VPS-3 (168.231.86.24) as root or with sudo
#
# Services deployed:
#   Ollama       — local LLM inference engine
#   Open WebUI   — Ollama web frontend (ChatGPT-style)
#   Langfuse     — AI observability & prompt tracing
#   Qdrant       — vector database for RAG/embeddings
#   cloudflared  — Cloudflare tunnel (zero-trust access)

set -e

SCRIPT_DIR="/opt/dev"
DOMAIN="theblackagency.cloud"

echo "========================================"
echo "VPS-3 Dev / AI Stack Deployment"
echo "========================================"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

echo "=== Creating directory structure ==="
mkdir -p "$SCRIPT_DIR"/{ollama/data,open-webui/data,langfuse/{postgres,data},qdrant/data,cloudflared,backups}
chown -R deploy:deploy "$SCRIPT_DIR"
chmod 750 "$SCRIPT_DIR"
chmod 700 "$SCRIPT_DIR/backups"
echo "✓ Directories created"

echo "=== Generating secure passwords ==="
LANGFUSE_DB_PASSWORD=$(openssl rand -base64 32)
LANGFUSE_SECRET=$(openssl rand -hex 32)
LANGFUSE_NEXTAUTH_SECRET=$(openssl rand -hex 32)
WEBUI_SECRET=$(openssl rand -hex 32)

cat > "$SCRIPT_DIR/.env" << EOF
# Cloudflare Tunnel Token — fill in before starting services
CLOUDFLARE_TUNNEL_TOKEN=YOUR_TUNNEL_TOKEN_HERE

# Langfuse
LANGFUSE_DB_PASSWORD=$LANGFUSE_DB_PASSWORD
LANGFUSE_SECRET_KEY=$LANGFUSE_SECRET
NEXTAUTH_SECRET=$LANGFUSE_NEXTAUTH_SECRET
NEXTAUTH_URL=https://trace.${DOMAIN}

# Open WebUI
WEBUI_SECRET_KEY=$WEBUI_SECRET
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
  dev:
    driver: bridge
    ipam:
      config:
        - subnet: 172.22.0.0/24

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    volumes:
      - ./ollama/data:/root/.ollama
    networks:
      dev:
        ipv4_address: 172.22.0.10
    ports:
      - "127.0.0.1:11434:11434"
    deploy:
      resources:
        limits:
          memory: 8G
          cpus: '4.0'
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/version"]
      interval: 30s
      timeout: 10s
      retries: 5

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    env_file: .env
    environment:
      - OLLAMA_BASE_URL=http://172.22.0.10:11434
      - WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
      - ENABLE_SIGNUP=false
    volumes:
      - ./open-webui/data:/app/backend/data
    networks:
      - dev
    ports:
      - "127.0.0.1:3000:8080"
    depends_on:
      ollama:
        condition: service_healthy
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
    security_opt:
      - no-new-privileges:true

  langfuse-db:
    image: postgres:16-alpine
    container_name: langfuse-db
    restart: unless-stopped
    env_file: .env
    environment:
      - POSTGRES_USER=langfuse
      - POSTGRES_PASSWORD=${LANGFUSE_DB_PASSWORD}
      - POSTGRES_DB=langfuse
    volumes:
      - ./langfuse/postgres:/var/lib/postgresql/data
    networks:
      dev:
        ipv4_address: 172.22.0.11
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.3'
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U langfuse -d langfuse"]
      interval: 10s
      timeout: 5s
      retries: 5

  langfuse:
    image: langfuse/langfuse:latest
    container_name: langfuse
    restart: unless-stopped
    env_file: .env
    environment:
      - DATABASE_URL=postgresql://langfuse:${LANGFUSE_DB_PASSWORD}@172.22.0.11:5432/langfuse
      - LANGFUSE_SECRET_KEY=${LANGFUSE_SECRET_KEY}
      - NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
      - NEXTAUTH_URL=${NEXTAUTH_URL}
      - TELEMETRY_ENABLED=false
    networks:
      - dev
    ports:
      - "127.0.0.1:3001:3000"
    depends_on:
      langfuse-db:
        condition: service_healthy
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
    security_opt:
      - no-new-privileges:true

  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    volumes:
      - ./qdrant/data:/qdrant/storage
    networks:
      - dev
    ports:
      - "127.0.0.1:6333:6333"
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '1.0'
    security_opt:
      - no-new-privileges:true

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    env_file: .env
    command: tunnel --no-autoupdate run --token ${CLOUDFLARE_TUNNEL_TOKEN}
    networks:
      - dev
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
echo "✅ VPS-3 Dev / AI Stack Ready!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Run: cd $SCRIPT_DIR && docker compose up -d"
echo "2. Pull an LLM model:  docker exec ollama ollama pull llama3.2"
echo "3. Access services at:"
echo "   - https://ai.theblackagency.cloud    (Open WebUI)"
echo "   - https://trace.theblackagency.cloud (Langfuse)"
echo "   - https://vectors.theblackagency.cloud (Qdrant)"
echo ""
echo "Default credentials saved in: $SCRIPT_DIR/.env"
