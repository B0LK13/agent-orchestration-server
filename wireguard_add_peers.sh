#!/usr/bin/env bash
# WireGuard Mesh — Phase 2: Add Peers
# Run AFTER wireguard_setup.sh on all 3 VPS nodes.
#
# Usage:
#   WG_PUBKEY_VPS1=<key> WG_PUBKEY_VPS2=<key> WG_PUBKEY_VPS3=<key> sudo bash wireguard_add_peers.sh
#
# Or pass keys as positional args:
#   sudo bash wireguard_add_peers.sh <vps1_pubkey> <vps2_pubkey> <vps3_pubkey>

set -euo pipefail

# ── Public IPs ────────────────────────────────────────────────────────────────
VPS1_PUBLIC_IP="31.97.47.51"
VPS2_PUBLIC_IP="72.60.176.178"
VPS3_PUBLIC_IP="168.231.86.24"

# WireGuard tunnel IPs
VPS1_WG_IP="10.10.0.1"
VPS2_WG_IP="10.10.0.2"
VPS3_WG_IP="10.10.0.3"
WG_PORT="51820"
WG_CONF="/etc/wireguard/wg0.conf"

# ── Resolve public keys ───────────────────────────────────────────────────────
WG_PUBKEY_VPS1="${WG_PUBKEY_VPS1:-${1:-}}"
WG_PUBKEY_VPS2="${WG_PUBKEY_VPS2:-${2:-}}"
WG_PUBKEY_VPS3="${WG_PUBKEY_VPS3:-${3:-}}"

if [[ -z "$WG_PUBKEY_VPS1" || -z "$WG_PUBKEY_VPS2" || -z "$WG_PUBKEY_VPS3" ]]; then
    echo "ERROR: All three VPS public keys are required."
    echo ""
    echo "Usage:"
    echo "  WG_PUBKEY_VPS1=<key> WG_PUBKEY_VPS2=<key> WG_PUBKEY_VPS3=<key> sudo bash $0"
    echo "  sudo bash $0 <vps1_key> <vps2_key> <vps3_key>"
    echo ""
    echo "Tip: get each VPS public key with:  cat /etc/wireguard/publickey"
    exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run as root or with sudo."
    exit 1
fi

# ── Detect which VPS this is ──────────────────────────────────────────────────
detect_vps() {
    local hostname
    hostname="$(hostname)"
    if [[ "$hostname" == *"vps1"* ]] || [[ "$hostname" == *"automation"* ]]; then
        echo "1"
    elif [[ "$hostname" == *"vps2"* ]] || [[ "$hostname" == *"workspace"* ]]; then
        echo "2"
    elif [[ "$hostname" == *"vps3"* ]] || [[ "$hostname" == *"dev"* ]]; then
        echo "3"
    else
        echo ""
    fi
}

VPS_NUM="$(detect_vps)"
if [[ -z "$VPS_NUM" ]]; then
    echo "Could not auto-detect VPS number. Enter 1, 2, or 3:"
    read -r VPS_NUM
fi

echo "========================================"
echo "WireGuard Peer Configuration — VPS-$VPS_NUM"
echo "========================================"

[[ -f "$WG_CONF" ]] || { echo "ERROR: $WG_CONF not found. Run wireguard_setup.sh first."; exit 1; }

# ── Remove any previously added peer blocks ───────────────────────────────────
# Keep only the [Interface] section
INTERFACE_BLOCK="$(awk '/^\[Interface\]/{found=1} found && /^\[Peer\]/{exit} found{print}' "$WG_CONF")"
echo "$INTERFACE_BLOCK" > "$WG_CONF"

# ── Write peer blocks (skip self) ─────────────────────────────────────────────
add_peer() {
    local label="$1" pubkey="$2" endpoint_ip="$3" wg_ip="$4"
    cat >> "$WG_CONF" <<EOF

# $label
[Peer]
PublicKey = $pubkey
AllowedIPs = ${wg_ip}/32
Endpoint = ${endpoint_ip}:${WG_PORT}
PersistentKeepalive = 25
EOF
    echo "  ✓ Added peer: $label ($wg_ip)"
}

case "$VPS_NUM" in
    1)
        add_peer "VPS-2 (Workspace)" "$WG_PUBKEY_VPS2" "$VPS2_PUBLIC_IP" "$VPS2_WG_IP"
        add_peer "VPS-3 (Dev)"       "$WG_PUBKEY_VPS3" "$VPS3_PUBLIC_IP" "$VPS3_WG_IP"
        ;;
    2)
        add_peer "VPS-1 (Automation)" "$WG_PUBKEY_VPS1" "$VPS1_PUBLIC_IP" "$VPS1_WG_IP"
        add_peer "VPS-3 (Dev)"        "$WG_PUBKEY_VPS3" "$VPS3_PUBLIC_IP" "$VPS3_WG_IP"
        ;;
    3)
        add_peer "VPS-1 (Automation)" "$WG_PUBKEY_VPS1" "$VPS1_PUBLIC_IP" "$VPS1_WG_IP"
        add_peer "VPS-2 (Workspace)"  "$WG_PUBKEY_VPS2" "$VPS2_PUBLIC_IP" "$VPS2_WG_IP"
        ;;
    *)
        echo "ERROR: Invalid VPS number: $VPS_NUM"; exit 1 ;;
esac

chmod 600 "$WG_CONF"

# ── Restart WireGuard and verify ─────────────────────────────────────────────
echo ""
echo "=== Restarting WireGuard ==="
wg-quick down wg0 2>/dev/null || true
wg-quick up wg0

echo ""
echo "=== WireGuard Status ==="
wg show

echo ""
echo "========================================"
echo "✅ Peers configured on VPS-$VPS_NUM"
echo "========================================"
echo ""
echo "Verify connectivity with:"
case "$VPS_NUM" in
    1) echo "  ping -c3 $VPS2_WG_IP   # → VPS-2"; echo "  ping -c3 $VPS3_WG_IP   # → VPS-3" ;;
    2) echo "  ping -c3 $VPS1_WG_IP   # → VPS-1"; echo "  ping -c3 $VPS3_WG_IP   # → VPS-3" ;;
    3) echo "  ping -c3 $VPS1_WG_IP   # → VPS-1"; echo "  ping -c3 $VPS2_WG_IP   # → VPS-2" ;;
esac
