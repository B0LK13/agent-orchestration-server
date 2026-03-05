# Check all containers are running
sudo docker ps
# Check Cloudflared is connected
sudo docker logs cloudflared | tail -20
# View credentials (save these!)
sudo cat /opt/automation/.env    # VPS-1
sudo cat /opt/workspace/.env     # VPS-2
sudo cat /opt/dev/.env           # VPS-3
