#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Cloudflare DNS Provisioner — theblackagency.cloud
# Creates CNAME records for all tunnel-routed hostnames.
#
# Usage:
#   CF_API_TOKEN=<your-token> bash provision-dns.sh
#
# Get a token at: Cloudflare Dashboard → My Profile → API Tokens
# Required permissions: Zone > DNS > Edit  (for zone theblackagency.cloud)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ZONE_NAME="theblackagency.cloud"
TUNNEL_ID="e6710ff6-b8d5-47b5-9c04-4982e6b4cd66"
TUNNEL_CNAME="${TUNNEL_ID}.cfargotunnel.com"

CF_API_TOKEN="${CF_API_TOKEN:-}"
if [[ -z "$CF_API_TOKEN" ]]; then
  echo "ERROR: Set CF_API_TOKEN environment variable first."
  echo "  export CF_API_TOKEN=your_token_here"
  echo "  bash $(basename "$0")"
  exit 1
fi

CF_API="https://api.cloudflare.com/client/v4"
HEADERS=(-H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

# Get Zone ID
echo "Looking up zone: $ZONE_NAME"
ZONE_ID=$(curl -s "${HEADERS[@]}" "$CF_API/zones?name=$ZONE_NAME" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result'][0]['id'])")
echo "Zone ID: $ZONE_ID"

# Subdomains to provision
HOSTNAMES=(
  # Remote access
  "ssh"
  "terminal"
  "files"
  # Automation stack
  "n8n"
  "status"
  "notify"
  "rss"
)

provision_cname() {
  local name="$1"
  local fqdn="${name}.${ZONE_NAME}"

  # Check if record already exists
  EXISTING=$(curl -s "${HEADERS[@]}" \
    "$CF_API/zones/$ZONE_ID/dns_records?type=CNAME&name=$fqdn" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result'][0]['id'] if d['result'] else '')" 2>/dev/null || echo "")

  if [[ -n "$EXISTING" ]]; then
    # Update existing
    RESULT=$(curl -s -X PUT "${HEADERS[@]}" \
      "$CF_API/zones/$ZONE_ID/dns_records/$EXISTING" \
      -d "{\"type\":\"CNAME\",\"name\":\"$fqdn\",\"content\":\"$TUNNEL_CNAME\",\"proxied\":true,\"ttl\":1}")
  else
    # Create new
    RESULT=$(curl -s -X POST "${HEADERS[@]}" \
      "$CF_API/zones/$ZONE_ID/dns_records" \
      -d "{\"type\":\"CNAME\",\"name\":\"$fqdn\",\"content\":\"$TUNNEL_CNAME\",\"proxied\":true,\"ttl\":1}")
  fi

  SUCCESS=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['success'])")
  if [[ "$SUCCESS" == "True" ]]; then
    echo "  ✓ $fqdn → $TUNNEL_CNAME"
  else
    echo "  ✗ $fqdn FAILED:"
    echo "$RESULT" | python3 -m json.tool | grep "message"
  fi
}

echo ""
echo "Provisioning CNAME records → tunnel $TUNNEL_ID"
echo ""
for name in "${HOSTNAMES[@]}"; do
  provision_cname "$name"
done

echo ""
echo "Done. All records proxied through Cloudflare (orange-cloud)."
echo "Tunnel routing is live once propagated (usually <30s)."
