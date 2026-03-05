# SSH to VPS-1
ssh root1

# Run deployment script
sudo bash /tmp/vps1_deploy.sh

# Edit .env and add Cloudflare tunnel token
sudo nano /opt/automation/.env
# Replace: CLOUDFLARE_TUNNEL_TOKEN=YOUR_TUNNEL_TOKEN_HERE
# With: CLOUDFLARE_TUNNEL_TOKEN=your_actual_token

# Start services
cd /opt/automation
sudo docker compose up -d

# Verify all containers are running
sudo docker compose ps
