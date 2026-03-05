#!/usr/bin/env bash
# Run on EACH VPS as root/sudo
# Optional: GOTIFY_URL and GOTIFY_TOKEN for notifications

curl -fsSL https://raw.githubusercontent.com/B0LK13/agent-orchestration-server/main/backup.sh | bash

echo ""
echo "===== CRON VERIFY ====="
crontab -l | grep vps-backup

echo ""
echo "===== TEST RUN ====="
/usr/local/bin/vps-backup.sh

echo ""
echo "===== BACKUP FILES ====="
ls -lh /var/backups/vps/
