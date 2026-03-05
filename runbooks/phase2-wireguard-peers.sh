#!/usr/bin/env bash
# Run on EACH VPS after collecting all 3 public keys
# Usage:
#   WG_PUBKEY_VPS1=<k1> WG_PUBKEY_VPS2=<k2> WG_PUBKEY_VPS3=<k3> bash phase2-wireguard-peers.sh

WG_PUBKEY_VPS1="${WG_PUBKEY_VPS1:-}"
WG_PUBKEY_VPS2="${WG_PUBKEY_VPS2:-}"
WG_PUBKEY_VPS3="${WG_PUBKEY_VPS3:-}"
WG_PORT=51820

if [[ -z "$WG_PUBKEY_VPS1" || -z "$WG_PUBKEY_VPS2" || -z "$WG_PUBKEY_VPS3" ]]; then
    echo "ERROR: set all three WG_PUBKEY_VPS[1-3] env vars"
    exit 1
fi

curl -fsSL https://raw.githubusercontent.com/B0LK13/agent-orchestration-server/main/wireguard_add_peers.sh \
  | WG_PUBKEY_VPS1="$WG_PUBKEY_VPS1" WG_PUBKEY_VPS2="$WG_PUBKEY_VPS2" WG_PUBKEY_VPS3="$WG_PUBKEY_VPS3" bash

echo ""
echo "===== PING TEST ====="
VPS_NUM=$(hostname | grep -oE '[1-3]$' || echo "?")
case "$VPS_NUM" in
    1) ping -c2 10.10.0.2 && ping -c2 10.10.0.3 ;;
    2) ping -c2 10.10.0.1 && ping -c2 10.10.0.3 ;;
    3) ping -c2 10.10.0.1 && ping -c2 10.10.0.2 ;;
esac
