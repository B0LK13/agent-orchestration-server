# Install backup script
sudo tee /usr/local/bin/vps-backup.sh > /dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

HOST="$(hostname -s)"
TS="$(date +%F_%H-%M-%S)"
DEST="/var/backups/vps"
TMP="$DEST/${HOST}_${TS}.tar.gz"
GOTIFY_URL="${GOTIFY_URL:-}"
GOTIFY_TOKEN="${GOTIFY_TOKEN:-}"

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

SIZE=$(du -sh "$TMP" | cut -f1)
echo "Backup created: $TMP ($SIZE)"

# Offsite transfer via rclone (optional — configure rclone first)
if command -v rclone >/dev/null 2>&1 && rclone listremotes | grep -q "offsite:"; then
    rclone copy "$TMP" "offsite:vps-backups/$HOST/" --log-level INFO
    echo "Offsite upload complete"
fi

# Gotify notification
notify() {
    local title="$1" msg="$2" priority="${3:-5}"
    if [[ -n "$GOTIFY_URL" && -n "$GOTIFY_TOKEN" ]]; then
        curl -s -X POST "$GOTIFY_URL/message" \
            -H "X-Gotify-Key: $GOTIFY_TOKEN" \
            -F "title=$title" \
            -F "message=$msg" \
            -F "priority=$priority" > /dev/null
    fi
}

notify "✅ Backup Complete — $HOST" "Archive: $(basename "$TMP") | Size: $SIZE" 3

EOF

sudo chmod +x /usr/local/bin/vps-backup.sh

# Install cron job (daily at 02:00)
CRON_LINE="0 2 * * * /usr/local/bin/vps-backup.sh >> /var/log/vps-backup.log 2>&1"
( sudo crontab -l 2>/dev/null | grep -v "vps-backup.sh" ; echo "$CRON_LINE" ) | sudo crontab -

echo "✓ Backup script installed: /usr/local/bin/vps-backup.sh"
echo "✓ Cron job added: daily at 02:00"
echo ""
echo "Optional: set Gotify credentials in /etc/environment or the cron environment:"
echo "  GOTIFY_URL=https://notify.theblackagency.cloud"
echo "  GOTIFY_TOKEN=your-app-token"
echo ""
echo "Optional: configure rclone for offsite uploads:"
echo "  rclone config   # add a remote named 'offsite'"
