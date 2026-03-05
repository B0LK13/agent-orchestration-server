# Fix sudoers for deploy
echo "deploy ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/deploy
chmod 440 /etc/sudoers.d/deploy

# Port 2222 is already set (line 13), so just configure UFW
ufw allow 2222/tcp comment 'SSH'
ufw enable

# Validate and restart SSH
sshd -t && systemctl restart ssh
