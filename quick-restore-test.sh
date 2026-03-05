mkdir -p /tmp/restore-test
LATEST=$(ls -1t /var/backups/vps/*.tar.gz | head -n1)
sudo tar -xzf "$LATEST" -C /tmp/restore-test
ls /tmp/restore-test/etc | head
