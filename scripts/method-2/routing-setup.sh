#!/bin/bash
#
# VPS1 Policy Routing Script - Method 2
# 
# Kiến trúc:
#   PC1 ──wg0──► VPS1 ──wg1──► VPS2 ──► Internet
#                 │
#                 └─ Special IPs ─► eth0 (VPS1 IP)
#
# Traffic flow:
#   - Packets từ PC1 (10.10.0.0/24) đến special IPs → ra eth0 (IP VPS1)
#   - Packets từ PC1 đến các IP khác → forward qua wg1 → VPS2
#

set -e

# Configuration
IPSET_NAME="special_ips"
TABLE_DIRECT=100          # Routing table cho special IPs (ra eth0)
MARK_DIRECT=100           # fwmark cho packets đi thẳng
WAN_IF="eth0"
WG_CLIENT_IF="wg0"        # Interface nhận PC1
WG_UPSTREAM_IF="wg1"      # Interface tunnel tới VPS2
CLIENT_SUBNET="10.10.0.0/24"
SPECIAL_IPS_FILE="/etc/sdwan/special-ips.txt"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

create_ipset() {
    if ! ipset list "$IPSET_NAME" &>/dev/null; then
        ipset create "$IPSET_NAME" hash:net
        log "Created ipset: $IPSET_NAME"
    fi
}

load_special_ips() {
    if [[ -f "$SPECIAL_IPS_FILE" ]]; then
        ipset flush "$IPSET_NAME"
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            ipset add "$IPSET_NAME" "$line" 2>/dev/null || true
        done < "$SPECIAL_IPS_FILE"
        log "Loaded special IPs from $SPECIAL_IPS_FILE"
    else
        log "Warning: $SPECIAL_IPS_FILE not found"
    fi
}

setup_routing_tables() {
    # Tạo routing table cho traffic đi thẳng qua eth0
    if ! ip route show table $TABLE_DIRECT | grep -q "default"; then
        # Get default gateway
        local gateway=$(ip route | grep "default via" | grep "$WAN_IF" | awk '{print $3}')
        if [[ -n "$gateway" ]]; then
            ip route add default via "$gateway" dev "$WAN_IF" table $TABLE_DIRECT
            log "Added default route via $gateway to table $TABLE_DIRECT"
        fi
    fi
    
    # Rule: packets với fwmark MARK_DIRECT sử dụng table TABLE_DIRECT
    if ! ip rule show | grep -q "fwmark $MARK_DIRECT"; then
        ip rule add fwmark $MARK_DIRECT table $TABLE_DIRECT priority 100
        log "Added ip rule for fwmark $MARK_DIRECT"
    fi
}

setup_iptables() {
    # NAT cho traffic ra eth0 (special IPs)
    if ! iptables -t nat -C POSTROUTING -s "$CLIENT_SUBNET" -o "$WAN_IF" -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -s "$CLIENT_SUBNET" -o "$WAN_IF" -j MASQUERADE
        log "Added NAT for $CLIENT_SUBNET via $WAN_IF"
    fi
    
    # NAT cho traffic qua wg1 tới VPS2
    if ! iptables -t nat -C POSTROUTING -s "$CLIENT_SUBNET" -o "$WG_UPSTREAM_IF" -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -s "$CLIENT_SUBNET" -o "$WG_UPSTREAM_IF" -j MASQUERADE
        log "Added NAT for $CLIENT_SUBNET via $WG_UPSTREAM_IF"
    fi
    
    # Mark packets đến special IPs
    if ! iptables -t mangle -C PREROUTING -s "$CLIENT_SUBNET" -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark $MARK_DIRECT 2>/dev/null; then
        iptables -t mangle -A PREROUTING -s "$CLIENT_SUBNET" -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark $MARK_DIRECT
        log "Added mangle rule for special IPs"
    fi
    
    # Forward rules
    iptables -C FORWARD -i "$WG_CLIENT_IF" -o "$WAN_IF" -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i "$WG_CLIENT_IF" -o "$WAN_IF" -j ACCEPT
    iptables -C FORWARD -i "$WAN_IF" -o "$WG_CLIENT_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i "$WAN_IF" -o "$WG_CLIENT_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    iptables -C FORWARD -i "$WG_CLIENT_IF" -o "$WG_UPSTREAM_IF" -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i "$WG_CLIENT_IF" -o "$WG_UPSTREAM_IF" -j ACCEPT
    iptables -C FORWARD -i "$WG_UPSTREAM_IF" -o "$WG_CLIENT_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i "$WG_UPSTREAM_IF" -o "$WG_CLIENT_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT
        
    log "Configured iptables rules"
}

cleanup() {
    # Remove iptables rules
    iptables -t nat -D POSTROUTING -s "$CLIENT_SUBNET" -o "$WAN_IF" -j MASQUERADE 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s "$CLIENT_SUBNET" -o "$WG_UPSTREAM_IF" -j MASQUERADE 2>/dev/null || true
    iptables -t mangle -D PREROUTING -s "$CLIENT_SUBNET" -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark $MARK_DIRECT 2>/dev/null || true
    iptables -D FORWARD -i "$WG_CLIENT_IF" -o "$WAN_IF" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$WAN_IF" -o "$WG_CLIENT_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$WG_CLIENT_IF" -o "$WG_UPSTREAM_IF" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$WG_UPSTREAM_IF" -o "$WG_CLIENT_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    
    # Remove ip rules and routes
    ip rule del fwmark $MARK_DIRECT table $TABLE_DIRECT 2>/dev/null || true
    ip route flush table $TABLE_DIRECT 2>/dev/null || true
    
    # Remove ipset
    ipset destroy "$IPSET_NAME" 2>/dev/null || true
    
    log "Cleaned up routing rules"
}

case "$1" in
    up)
        log "Setting up policy routing..."
        create_ipset
        load_special_ips
        setup_routing_tables
        setup_iptables
        log "Policy routing enabled"
        ;;
    down)
        log "Tearing down policy routing..."
        cleanup
        log "Policy routing disabled"
        ;;
    reload)
        log "Reloading special IPs..."
        load_special_ips
        log "Special IPs reloaded"
        ;;
    status)
        echo "=== IPSet: $IPSET_NAME ==="
        ipset list "$IPSET_NAME" 2>/dev/null || echo "Not created"
        echo ""
        echo "=== Routing Table $TABLE_DIRECT ==="
        ip route show table $TABLE_DIRECT 2>/dev/null || echo "Empty"
        echo ""
        echo "=== IP Rules ==="
        ip rule show | grep -E "fwmark|$TABLE_DIRECT" || echo "No custom rules"
        echo ""
        echo "=== Mangle Rules ==="
        iptables -t mangle -L PREROUTING -n -v | grep -E "special_ips|$MARK_DIRECT" || echo "No mangle rules"
        ;;
    *)
        echo "Usage: $0 {up|down|reload|status}"
        exit 1
        ;;
esac
