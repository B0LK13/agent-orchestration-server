#!/bin/bash
# VPS-1 Automation Stack Deployment Script
# Run this on VPS-1 (Automation Server) as root or with sudo

set -e

SCRIPT_DIR="/opt/automation"
DOMAIN="theblackagency.cloud"

echo "========================================"
echo "VPS-1 Automation Stack Deployment"
echo "========================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

# Create directory structure
echo "=== Creating directory structure ==="
mkdir -p $SCRIPT_DIR/{n8n/{data,files},postgres/data,redis/data,uptime-kuma,gotify,miniflux,loki/{config,data},promtail/config,grafana/{data,provisioning/{datasources,dashboards}},cloudflared,backups}
chown -R deploy:deploy $SCRIPT_DIR
chmod 750 $SCRIPT_DIR
chmod 700 $SCRIPT_DIR/backups
echo "✓ Directories created"

# Generate secure passwords
echo "=== Generating secure passwords ==="
POSTGRES_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
GRAFANA_PASSWORD=$(openssl rand -base64 16)

# Create .env file
cat > $SCRIPT_DIR/.env << EOF
# Cloudflare Tunnel Token — fill in before starting services
CLOUDFLARE_TUNNEL_TOKEN=YOUR_TUNNEL_TOKEN_HERE

# Database Configuration
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_USER=n8n_user
POSTGRES_DB=n8n_db
POSTGRES_NON_ROOT_USER=miniflux_user
POSTGRES_NON_ROOT_PASSWORD=$MINIFLUX_PASSWORD

# Redis Configuration
REDIS_PASSWORD=$REDIS_PASSWORD

# N8N Configuration
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=$N8N_BASIC_AUTH_PASSWORD
N8N_HOST=n8n.$DOMAIN
N8N_PORT=5678
N8N_PROTOCOL=https

# Gotify Configuration
GOTIFY_DEFAULT_USER=admin
GOTIFY_DEFAULT_PASS=$GOTIFY_PASSWORD

# Miniflux Configuration
MINIFlux_ADMIN_USERNAME=admin
MINIFLUX_ADMIN_PASSWORD=$MINIFLUX_PASSWORD

# Grafana Configuration
GRAFANA_PASSWORD=$GRAFANA_PASSWORD
EOF

chmod 600 $SCRIPT_DIR/.env

# Validate Cloudflare token was set
if grep -q "YOUR_TUNNEL_TOKEN_HERE" "$SCRIPT_DIR/.env"; then
    echo ""
    echo "❌ ERROR: Cloudflare tunnel token is not set!"
    echo "   Edit $SCRIPT_DIR/.env and replace YOUR_TUNNEL_TOKEN_HERE with your real token."
    echo "   Get your token at: https://one.dash.cloudflare.com/ → Networks → Tunnels"
    rm -f "$SCRIPT_DIR/.env"
    exit 1
fi
echo "✓ Environment file created at $SCRIPT_DIR/.env"
echo "⚠️  IMPORTANT: Edit .env and add your Cloudflare tunnel token!"

# Create docker-compose.yml
echo "=== Creating docker-compose.yml ==="
cat > $SCRIPT_DIR/docker-compose.yml << 'EOF'
version: '3.8'

networks:
  automation:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24

services:
  postgres:
    image: postgres:16-alpine
    container_name: postgres
    restart: unless-stopped
    env_file: .env
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_NON_ROOT_USER=${POSTGRES_NON_ROOT_USER}
      - POSTGRES_NON_ROOT_PASSWORD=${POSTGRES_NON_ROOT_PASSWORD}
    volumes:
      - ./postgres/data:/var/lib/postgresql/data
    networks:
      automation:
        ipv4_address: 172.20.0.10
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
    volumes:
      - ./redis/data:/data
    networks:
      automation:
        ipv4_address: 172.20.0.11
    deploy:
      resources:
        limits:
          memory: 192M
          cpus: '0.25'
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    env_file: .env
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=172.20.0.10
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_BASIC_AUTH_ACTIVE=${N8N_BASIC_AUTH_ACTIVE}
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=${N8N_PORT}
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - WEBHOOK_URL=https://${N8N_HOST}/
    volumes:
      - ./n8n/data:/home/node/.n8n
      - ./n8n/files:/files
    networks:
      - automation
    ports:
      - "127.0.0.1:5678:5678"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '1.0'
    security_opt:
      - no-new-privileges:true

  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    restart: unless-stopped
    volumes:
      - ./uptime-kuma:/app/data
    networks:
      - automation
    ports:
      - "127.0.0.1:3001:3001"
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.25'
    security_opt:
      - no-new-privileges:true

  gotify:
    image: gotify/server:latest
    container_name: gotify
    restart: unless-stopped
    env_file: .env
    environment:
      - GOTIFY_DEFAULT_USER=${GOTIFY_DEFAULT_USER}
      - GOTIFY_DEFAULT_PASS=${GOTIFY_DEFAULT_PASS}
    volumes:
      - ./gotify:/app/data
    networks:
      - automation
    ports:
      - "127.0.0.1:8080:80"
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.15'
    security_opt:
      - no-new-privileges:true

  miniflux:
    image: miniflux/miniflux:latest
    container_name: miniflux
    restart: unless-stopped
    environment:
      - DATABASE_URL=postgres://${POSTGRES_NON_ROOT_USER}:${POSTGRES_NON_ROOT_PASSWORD}@172.20.0.10/miniflux?sslmode=disable
      - RUN_MIGRATIONS=1
      - CREATE_ADMIN=1
      - ADMIN_USERNAME=${MINIFlux_ADMIN_USERNAME}
      - ADMIN_PASSWORD=${MINIFLUX_ADMIN_PASSWORD}
    networks:
      - automation
    ports:
      - "127.0.0.1:8081:8080"
    depends_on:
      postgres:
        condition: service_healthy
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.15'
    security_opt:
      - no-new-privileges:true

  loki:
    image: grafana/loki:latest
    container_name: loki
    restart: unless-stopped
    volumes:
      - ./loki/config:/etc/loki
      - ./loki/data:/loki
    networks:
      - automation
    ports:
      - "127.0.0.1:3100:3100"
    deploy:
      resources:
        limits:
          memory: 256M
    security_opt:
      - no-new-privileges:true

  promtail:
    image: grafana/promtail:latest
    container_name: promtail
    restart: unless-stopped
    volumes:
      - ./promtail/config:/etc/promtail
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
    networks:
      - automation
    deploy:
      resources:
        limits:
          memory: 128M
    security_opt:
      - no-new-privileges:true
    depends_on:
      - loki

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    networks:
      - automation
    ports:
      - "127.0.0.1:9100:9100"
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    deploy:
      resources:
        limits:
          memory: 64M
          cpus: '0.1'
    security_opt:
      - no-new-privileges:true

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
      - GF_SERVER_ROOT_URL=https://metrics.theblackagency.cloud
      - GF_SERVER_DOMAIN=metrics.theblackagency.cloud
      - GF_ANALYTICS_REPORTING_ENABLED=false
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - ./grafana/data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    networks:
      - automation
    ports:
      - "127.0.0.1:3000:3000"
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
      - automation
    deploy:
      resources:
        limits:
          memory: 128M
    security_opt:
      - no-new-privileges:true
EOF

echo "✓ docker-compose.yml created"

# Create Loki configuration
echo "=== Creating Loki configuration ==="
cat > $SCRIPT_DIR/loki/config/config.yaml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://localhost:9093

analytics:
  reporting_enabled: false
EOF

echo "✓ Loki config created"

# Create Promtail configuration
echo "=== Creating Promtail configuration ==="
cat > $SCRIPT_DIR/promtail/config/config.yaml << 'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/**/*.log
  
  - job_name: docker
    static_configs:
      - targets:
          - localhost
        labels:
          job: docker
          __path__: /var/lib/docker/containers/*/*.log
EOF

echo "✓ Promtail config created"

# Create Grafana Loki datasource provisioning
echo "=== Creating Grafana provisioning ==="
cat > $SCRIPT_DIR/grafana/provisioning/datasources/loki.yaml << 'EOF'
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: true
    editable: false
EOF

echo "✓ Grafana provisioning created"

# Set ownership
chown -R deploy:deploy $SCRIPT_DIR
chmod 600 $SCRIPT_DIR/.env

# Validate Cloudflare token was set
if grep -q "YOUR_TUNNEL_TOKEN_HERE" "$SCRIPT_DIR/.env"; then
    echo ""
    echo "❌ ERROR: Cloudflare tunnel token is not set!"
    echo "   Edit $SCRIPT_DIR/.env and replace YOUR_TUNNEL_TOKEN_HERE with your real token."
    echo "   Get your token at: https://one.dash.cloudflare.com/ → Networks → Tunnels"
    rm -f "$SCRIPT_DIR/.env"
    exit 1
fi

echo ""
echo "========================================"
echo "✅ VPS-1 Automation Stack Ready!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Edit $SCRIPT_DIR/.env and add your Cloudflare tunnel token"
echo "2. Run: cd $SCRIPT_DIR && docker compose up -d"
echo "3. Access services at:"
echo "   - https://n8n.theblackagency.cloud"
echo "   - https://status.theblackagency.cloud"
echo "   - https://notify.theblackagency.cloud"
echo "   - https://rss.theblackagency.cloud"
echo "   - https://metrics.theblackagency.cloud"
echo ""
echo "Default credentials saved in: $SCRIPT_DIR/.env"
echo ""
echo "To view passwords: cat $SCRIPT_DIR/.env"
