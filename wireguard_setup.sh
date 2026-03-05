#!/bin/bash
# WireGuard Mesh VPN Setup Script
# Run this script on EACH VPS (as root or with sudo)
# VPS-1 | VPS-2 | VPS-3

set -e

# Configuration
VPS1_IP="31.97.47.51"
VPS1_HOSTNAME="vps1.theblackagency.cloud"
VPS2_IP="72.60.176.178"
VPS2_HOSTNAME="vps2.theblackagency.cloud"
VPS3_IP="168.231.86.24"
VPS3_HOSTNAME="vps3.theblackagency.cloud"
WG_PORT="51820"

# Detect which VPS this is
detect_vps() {
    local hostname=$(hostname)
    if [[ "$hostname" == *"vps1"* ]] || [[ "$hostname" == *"automation"* ]]; then
        VPS_NUM="1"
        VPS_IP="$VPS1_IP"
    elif [[ "$hostname" == *"vps2"* ]] || [[ "$hostname" == *"workspace"* ]]; then
        VPS_NUM="2"
        VPS_IP="$VPS2_IP"
    elif [[ "$hostname" == *"vps3"* ]] || [[ "$hostname" == *"dev"* ]]; then
        VPS_NUM="3"
        VPS_IP="$VPS3_IP"
    else
        echo "Could not detect VPS number. Please set VPS_NUM manually (1, 2, or 3):"
        read VPS_NUM
        case $VPS_NUM in
            1) VPS_IP="$VPS1_IP" ;;
            2) VPS_IP="$VPS2_IP" ;;
            3) VPS_IP="$VPS3_IP" ;;
            *) echo "Invalid VPS number. Exiting."; exit 1 ;;
        esac
    fi
    echo "Detected VPS-$VPS_NUM with IP $VPS_IP"
}

# Install WireGuard
install_wireguard() {
    echo "=== Installing WireGuard ==="
    apt-get update
    apt-get install -y wireguard wireguard-tools
    
    # Enable IP forwarding
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard.conf
    sysctl --system
    
    echo "✓ WireGuard installed"
}

# Generate keys
generate_keys() {
    echo "=== Generating WireGuard Keys ==="
    mkdir -p /etc/wireguard
    cd /etc/wireguard
    
    # Generate private key
    wg genkey | tee privatekey | wg pubkey > publickey
    
    # Set permissions
    chmod 600 privatekey
    chmod 644 publickey
    
    echo "✓ Keys generated"
    echo "  Private key: $(cat privatekey)"
    echo "  Public key: $(cat publickey)"
    echo ""
    echo "⚠️  SAVE THIS PUBLIC KEY - you'll need it for the other VPS!"
}

# Create WireGuard configuration
create_config() {
    echo "=== Creating WireGuard Configuration ==="
    
    local PRIVATE_KEY=$(cat /etc/wireguard/privatekey)
    local PUBLIC_IP=$(curl -s ifconfig.me)
    
    # These will be filled in after collecting all public keys
    cat > /etc/wireguard/wg0.conf << EOF
# VPS-$VPS_NUM Configuration
# This VPS: $VPS_IP
# Public IP: $PUBLIC_IP
# Generated: $(date)

[Interface]
PrivateKey = $PRIVATE_KEY
Address = $VPS_IP/24
ListenPort = $WG_PORT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# PEERS - Run the add_peers.sh script after collecting all public keys
# Format:
# [Peer]
# PublicKey = <other-vps-public-key>
# AllowedIPs = <other-vps-wg-ip>/32
# Endpoint = <other-vps-public-ip>:$WG_PORT
# PersistentKeepalive = 25
EOF

    chmod 600 /etc/wireguard/wg0.conf
    echo "✓ Configuration created at /etc/wireguard/wg1.conf"
}

# Enable and start WireGuard
start_wireguard() {
    echo "=== Starting WireGuard ==="
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
    
    echo "✓ WireGuard started"
    wg show
}

# Main execution
main() {
    echo "========================================"
    echo "WireGuard Mesh VPN Setup"
    echo "========================================"
    echo ""
    
    detect_vps
    install_wireguard
    generate_keys
    create_config
    
    echo ""
    echo "========================================"
    echo "⚠️  IMPORTANT NEXT STEPS:"
    echo "========================================"
    echo ""
    echo "1. Copy the public key shown above"
    echo "2. Run this script on ALL 3 VPS servers"
    echo "3. Collect all 3 public keys"
    echo "4. Run the add_peers.sh script on each VPS"
    echo ""
    echo "Your VPS details:"
    echo "  VPS Number: $VPS_NUM"
    echo "  WireGuard IP: $VPS_IP"
    echo "  Public Key: $(cat /etc/wireguard/publickey)"
    echo "  Public IP: $(curl -s ifconfig.me)"
    echo ""
    echo "✓ Setup complete for VPS-$VPS_NUM"
}

# Run main function
main
