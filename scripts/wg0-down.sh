#!/bin/bash
#
# Cleanup script khi wg0 down - Method 1 (Single Interface)
#

set -e

# Configuration
IPSET_NAME="special_ips"
TABLE_DIRECT=100
MARK_DIRECT=100
WAN_IF="eth0"
CLIENT_IP="10.10.0.2"
VPS2_IP="10.10.0.3"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "WG0 interface going down..."

# Remove iptables rules
iptables -t nat -D POSTROUTING -s "$CLIENT_IP" -o "$WAN_IF" -j MASQUERADE 2>/dev/null || true
iptables -t mangle -D PREROUTING -s "$CLIENT_IP" -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark $MARK_DIRECT 2>/dev/null || true
iptables -D FORWARD -s "$CLIENT_IP" -o "$WAN_IF" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i "$WAN_IF" -d "$CLIENT_IP" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -s "$CLIENT_IP" -d "$VPS2_IP" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -s "$VPS2_IP" -d "$CLIENT_IP" -j ACCEPT 2>/dev/null || true

# Remove ip rules and routes
ip rule del fwmark $MARK_DIRECT table $TABLE_DIRECT 2>/dev/null || true
ip route flush table $TABLE_DIRECT 2>/dev/null || true

# Remove ipset
ipset destroy "$IPSET_NAME" 2>/dev/null || true

log "WG0 down complete. Cleanup finished."
