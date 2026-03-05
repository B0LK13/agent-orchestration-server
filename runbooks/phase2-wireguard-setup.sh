#!/usr/bin/env bash
# Run on EACH VPS — paste the output back from all 3
# This is the phase 1 of WireGuard setup (key generation)

set -e
apt-get install -y wireguard wireguard-tools -qq

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard.conf
sysctl --system -q

mkdir -p /etc/wireguard
cd /etc/wireguard
[ -f privatekey ] || wg genkey | tee privatekey | wg pubkey > publickey
chmod 600 privatekey

echo ""
echo "===== VPS HOSTNAME ====="
hostname

echo ""
echo "===== WIREGUARD PUBLIC KEY ====="
cat /etc/wireguard/publickey

echo ""
echo "===== PUBLIC IP ====="
curl -s ifconfig.me
