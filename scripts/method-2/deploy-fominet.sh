#!/bin/bash
# Deploy fominet (VPS2/OpenWRT): WireGuard Exit Node
# Runs ON fominet (192.168.20.1) via SSH
# Usage: ./deploy-fominet.sh [--force] [DO2_WG1_PUBKEY]

set -e

DO2_IP="152.42.238.137"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[fominet]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

log "=== Deploying fominet (VPS2/OpenWRT) WireGuard Exit Node ==="

# Install WireGuard
log "Installing WireGuard..."
opkg update 2>/dev/null || true
opkg install wireguard-tools luci-proto-wireguard kmod-wireguard 2>/dev/null || true

# Generate keys if not exist
log "Checking/generating keys..."
WG_DIR="/etc/wireguard"
mkdir -p "$WG_DIR"

if [ ! -f "$WG_DIR/wg1_privatekey" ]; then
    wg genkey | tee "$WG_DIR/wg1_privatekey" | wg pubkey > "$WG_DIR/wg1_publickey"
    chmod 600 "$WG_DIR/wg1_privatekey"
    log "Generated wg1 keys"
fi

PRIVATE_KEY=$(cat "$WG_DIR/wg1_privatekey")
PUBLIC_KEY=$(cat "$WG_DIR/wg1_publickey")
log "wg1 pubkey: $PUBLIC_KEY"

# Get do2 pubkey
DO2_PUBKEY_ARG=""
if [ "$1" = "--force" ] && [ -n "$2" ]; then
    DO2_PUBKEY_ARG="$2"
elif [ -n "$1" ] && [ "$1" != "--force" ]; then
    DO2_PUBKEY_ARG="$1"
fi

if [ -n "$DO2_PUBKEY_ARG" ]; then
    DO2_WG1_PUBKEY="$DO2_PUBKEY_ARG"
elif [ -f "$WG_DIR/do2_wg1_pubkey" ]; then
    DO2_WG1_PUBKEY=$(cat "$WG_DIR/do2_wg1_pubkey")
else
    warn "do2 pubkey not provided. Deploy do2 first, then re-run with pubkey."
    DO2_WG1_PUBKEY="PLACEHOLDER_DEPLOY_DO2_FIRST"
fi

# Configure WireGuard via UCI
log "Configuring WireGuard interface (wg1)..."

# Remove old config
uci delete network.wg1 2>/dev/null || true
# Remove old wireguard peers
while uci delete network.@wireguard_wg1[-1] 2>/dev/null; do :; done

# Create interface
uci set network.wg1=interface
uci set network.wg1.proto='wireguard'
uci set network.wg1.private_key="$PRIVATE_KEY"
uci set network.wg1.listen_port='51821'
uci add_list network.wg1.addresses='10.20.0.2/24'

# Peer: do2 (VPS1)
uci add network wireguard_wg1
uci set network.@wireguard_wg1[-1].description='do2-vps1'
uci set network.@wireguard_wg1[-1].public_key="$DO2_WG1_PUBKEY"
uci set network.@wireguard_wg1[-1].endpoint_host="$DO2_IP"
uci set network.@wireguard_wg1[-1].endpoint_port='51821'
uci set network.@wireguard_wg1[-1].persistent_keepalive='25'
uci add_list network.@wireguard_wg1[-1].allowed_ips='10.20.0.0/24'
uci add_list network.@wireguard_wg1[-1].allowed_ips='10.10.0.0/24'
uci set network.@wireguard_wg1[-1].route_allowed_ips='1'

# Configure Firewall
log "Configuring firewall..."

# Check if wg zone already exists
WG_ZONE_EXISTS=$(uci show firewall 2>/dev/null | grep "\.name='wg'" | head -1 | cut -d'.' -f2 | cut -d'=' -f1)

if [ -z "$WG_ZONE_EXISTS" ]; then
    uci add firewall zone
    uci set firewall.@zone[-1].name='wg'
    uci set firewall.@zone[-1].input='ACCEPT'
    uci set firewall.@zone[-1].output='ACCEPT'
    uci set firewall.@zone[-1].forward='ACCEPT'
    uci set firewall.@zone[-1].masq='1'
    uci add_list firewall.@zone[-1].network='wg1'

    # Forward: wg -> wan
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='wg'
    uci set firewall.@forwarding[-1].dest='wan'

    # Forward: wg -> lan
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='wg'
    uci set firewall.@forwarding[-1].dest='lan'
    
    log "Created firewall zone 'wg'"
else
    log "Firewall zone 'wg' already exists"
fi

# Enable IP forwarding
uci set network.@globals[0].ip_forward='1' 2>/dev/null || true

# Commit and restart
log "Applying configuration..."
uci commit network
uci commit firewall

/etc/init.d/network restart
sleep 3
/etc/init.d/firewall restart

log "=== fominet Deployment Complete ==="
echo ""
echo "wg1 pubkey: $PUBLIC_KEY"
echo ""
echo "Next steps:"
echo "  1. Copy pubkey to do2:"
echo "     ssh root@$DO2_IP \"wg set wg1 peer $PUBLIC_KEY allowed-ips 10.20.0.2/32,0.0.0.0/0\""
echo "  2. Verify: wg show wg1"
echo "  3. Test: ping 10.20.0.1"
