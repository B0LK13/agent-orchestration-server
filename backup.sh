sudo tee /usr/local/bin/vps-backup.sh > /dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

HOST="$(hostname -s)"
TS="$(date +%F_%H-%M-%S)"
DEST="/var/backups/vps"
TMP="$DEST/${HOST}_${TS}.tar.gz"

mkdir -p "$DEST"

# Stop containers for consistent volume backup (optional, uncomment if needed)
# docker ps -q | xargs -r docker stop

tar --warning=no-file-changed -czf "$TMP" \
  --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run --exclude=/tmp \
  --exclude=/mnt --exclude=/media --exclude=/swapfile \
  --exclude=/var/backups/vps \
  /etc /home /root /opt /srv /var/lib/docker/volumes

# Restart containers if you stopped them
# docker start $(docker ps -aq) 2>/dev/null || true

# Keep last 7 backups
ls -1t "$DEST"/*.tar.gz | tail -n +8 | xargs -r rm -f

echo "Backup created: $TMP"
EOF

sudo chmod +x /usr/local/bin/vps-backup.sh
