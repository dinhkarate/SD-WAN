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
TABLE_SPECIAL="special"       # Routing table cho special IPs (ra eth0) - defined in rt_tables as 100
TABLE_TUNNEL="tunnel"         # Routing table cho tunnel traffic (qua wg1) - defined in rt_tables as 200
WAN_IF="eth0"
WG_CLIENT_IF="wg0"            # Interface nhận PC1
WG_UPSTREAM_IF="wg1"          # Interface tunnel tới VPS2
CLIENT_SUBNET="10.10.0.0/24"
SPECIAL_IPS_FILE="/etc/sdwan/special-ips.txt"
PRIORITY_SPECIAL=50           # Priority cao hơn (check trước)
PRIORITY_DEFAULT=100          # Priority cho default tunnel route

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

ensure_rt_tables() {
    # Đảm bảo routing tables được định nghĩa
    if ! grep -q "^100.*special" /etc/iproute2/rt_tables 2>/dev/null; then
        echo "100 special" >> /etc/iproute2/rt_tables
        log "Added table 'special' to rt_tables"
    fi
    if ! grep -q "^200.*tunnel" /etc/iproute2/rt_tables 2>/dev/null; then
        echo "200 tunnel" >> /etc/iproute2/rt_tables
        log "Added table 'tunnel' to rt_tables"
    fi
}

setup_base_routes() {
    # Get default gateway
    local gateway=$(ip route | grep "default via" | grep "$WAN_IF" | awk '{print $3}' | head -1)
    
    # Table special: default route qua eth0 (cho special IPs)
    if ! ip route show table $TABLE_SPECIAL 2>/dev/null | grep -q "default"; then
        if [[ -n "$gateway" ]]; then
            ip route add default via "$gateway" dev "$WAN_IF" table $TABLE_SPECIAL
            log "Added default route via $gateway to table $TABLE_SPECIAL"
        fi
    fi
    
    # Table tunnel: default route qua wg1 (cho non-special traffic)
    if ! ip route show table $TABLE_TUNNEL 2>/dev/null | grep -q "default"; then
        ip route add default dev "$WG_UPSTREAM_IF" src 10.20.0.2 table $TABLE_TUNNEL 2>/dev/null || true
        log "Added default route via $WG_UPSTREAM_IF to table $TABLE_TUNNEL"
    fi
    
    # Default rule: traffic từ PC1 đi qua tunnel (priority thấp hơn special IPs)
    if ! ip rule show | grep -q "from $CLIENT_SUBNET lookup $TABLE_TUNNEL"; then
        ip rule add from "$CLIENT_SUBNET" table $TABLE_TUNNEL priority $PRIORITY_DEFAULT
        log "Added default rule for $CLIENT_SUBNET via $TABLE_TUNNEL"
    fi
}

setup_special_ip_rules() {
    if [[ ! -f "$SPECIAL_IPS_FILE" ]]; then
        log "Warning: $SPECIAL_IPS_FILE not found"
        return
    fi
    
    local gateway=$(ip route | grep "default via" | grep "$WAN_IF" | awk '{print $3}' | head -1)
    local count=0
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        
        # Normalize IP (remove /32 suffix for rule matching)
        local ip="${line%/32}"
        
        # Add route to table special
        ip route add "$line" via "$gateway" dev "$WAN_IF" table $TABLE_SPECIAL 2>/dev/null || true
        
        # Add ip rule with high priority (check before default tunnel rule)
        if ! ip rule show | grep -q "from $CLIENT_SUBNET to $ip lookup $TABLE_SPECIAL"; then
            ip rule add from "$CLIENT_SUBNET" to "$ip" table $TABLE_SPECIAL priority $PRIORITY_SPECIAL
            count=$((count + 1))
        fi
    done < "$SPECIAL_IPS_FILE"
    
    log "Loaded $count special IP rules from $SPECIAL_IPS_FILE"
}

setup_iptables() {
    # Detect iptables command (legacy vs nft)
    local IPT="iptables"
    if command -v iptables-legacy &>/dev/null && iptables-legacy -L -n &>/dev/null; then
        IPT="iptables-legacy"
        log "Using iptables-legacy"
    fi

    # Xóa rules cũ trước (nếu có) để tránh duplicate
    $IPT -t nat -D POSTROUTING -s "$CLIENT_SUBNET" -o "$WAN_IF" -j MASQUERADE 2>/dev/null || true
    $IPT -t nat -D POSTROUTING -s "$CLIENT_SUBNET" -o "$WG_UPSTREAM_IF" -j MASQUERADE 2>/dev/null || true
    $IPT -D FORWARD -i "$WG_CLIENT_IF" -o "$WAN_IF" -j ACCEPT 2>/dev/null || true
    $IPT -D FORWARD -i "$WAN_IF" -o "$WG_CLIENT_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    $IPT -D FORWARD -i "$WG_CLIENT_IF" -o "$WG_UPSTREAM_IF" -j ACCEPT 2>/dev/null || true
    $IPT -D FORWARD -i "$WG_UPSTREAM_IF" -o "$WG_CLIENT_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true

    # NAT cho traffic ra eth0 (special IPs)
    $IPT -t nat -A POSTROUTING -s "$CLIENT_SUBNET" -o "$WAN_IF" -j MASQUERADE
    log "Added NAT for $CLIENT_SUBNET via $WAN_IF"
    
    # NAT cho traffic qua wg1 tới VPS2
    $IPT -t nat -A POSTROUTING -s "$CLIENT_SUBNET" -o "$WG_UPSTREAM_IF" -j MASQUERADE
    log "Added NAT for $CLIENT_SUBNET via $WG_UPSTREAM_IF"
    
    # Forward rules: wg0 -> eth0 (special IPs)
    $IPT -A FORWARD -i "$WG_CLIENT_IF" -o "$WAN_IF" -j ACCEPT
    $IPT -A FORWARD -i "$WAN_IF" -o "$WG_CLIENT_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Forward rules: wg0 -> wg1 (tunnel traffic)
    $IPT -A FORWARD -i "$WG_CLIENT_IF" -o "$WG_UPSTREAM_IF" -j ACCEPT
    $IPT -A FORWARD -i "$WG_UPSTREAM_IF" -o "$WG_CLIENT_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT
        
    log "Configured iptables rules"
}

cleanup() {
    log "Cleaning up..."
    
    # Detect iptables command
    local IPT="iptables"
    if command -v iptables-legacy &>/dev/null && iptables-legacy -L -n &>/dev/null; then
        IPT="iptables-legacy"
    fi
    
    # Remove iptables rules
    $IPT -t nat -D POSTROUTING -s "$CLIENT_SUBNET" -o "$WAN_IF" -j MASQUERADE 2>/dev/null || true
    $IPT -t nat -D POSTROUTING -s "$CLIENT_SUBNET" -o "$WG_UPSTREAM_IF" -j MASQUERADE 2>/dev/null || true
    $IPT -D FORWARD -i "$WG_CLIENT_IF" -o "$WAN_IF" -j ACCEPT 2>/dev/null || true
    $IPT -D FORWARD -i "$WAN_IF" -o "$WG_CLIENT_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    $IPT -D FORWARD -i "$WG_CLIENT_IF" -o "$WG_UPSTREAM_IF" -j ACCEPT 2>/dev/null || true
    $IPT -D FORWARD -i "$WG_UPSTREAM_IF" -o "$WG_CLIENT_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    
    # Remove all ip rules for CLIENT_SUBNET
    while ip rule del from "$CLIENT_SUBNET" 2>/dev/null; do :; done
    
    # Flush routing tables
    ip route flush table $TABLE_SPECIAL 2>/dev/null || true
    ip route flush table $TABLE_TUNNEL 2>/dev/null || true
    
    log "Cleanup complete"
}

reload_special_ips() {
    log "Reloading special IPs..."
    
    # Remove existing special IP rules (priority 50)
    while ip rule del priority $PRIORITY_SPECIAL 2>/dev/null; do :; done
    
    # Flush and rebuild table special routes
    ip route flush table $TABLE_SPECIAL 2>/dev/null || true
    
    # Re-add default route to table special
    local gateway=$(ip route | grep "default via" | grep "$WAN_IF" | awk '{print $3}' | head -1)
    if [[ -n "$gateway" ]]; then
        ip route add default via "$gateway" dev "$WAN_IF" table $TABLE_SPECIAL
    fi
    
    # Re-add special IP rules
    setup_special_ip_rules
    
    log "Special IPs reloaded"
}

status() {
    # Detect iptables command
    local IPT="iptables"
    if command -v iptables-legacy &>/dev/null && iptables-legacy -L -n &>/dev/null; then
        IPT="iptables-legacy"
    fi

    echo "=== Special IPs File ==="
    if [[ -f "$SPECIAL_IPS_FILE" ]]; then
        grep -v "^#" "$SPECIAL_IPS_FILE" | grep -v "^$" || echo "(empty)"
    else
        echo "File not found: $SPECIAL_IPS_FILE"
    fi
    echo ""
    
    echo "=== IP Rules (priority $PRIORITY_SPECIAL - Special IPs) ==="
    ip rule show | grep "from $CLIENT_SUBNET to" || echo "No special IP rules"
    echo ""
    
    echo "=== IP Rules (priority $PRIORITY_DEFAULT - Default Tunnel) ==="
    ip rule show | grep "from $CLIENT_SUBNET lookup" | grep -v "to" || echo "No default tunnel rule"
    echo ""
    
    echo "=== Routing Table: $TABLE_SPECIAL ==="
    ip route show table $TABLE_SPECIAL 2>/dev/null || echo "Empty"
    echo ""
    
    echo "=== Routing Table: $TABLE_TUNNEL ==="
    ip route show table $TABLE_TUNNEL 2>/dev/null || echo "Empty"
    echo ""
    
    echo "=== NAT Rules ==="
    $IPT -t nat -L POSTROUTING -n -v 2>/dev/null | grep -E "$CLIENT_SUBNET|MASQUERADE" | head -5 || echo "No NAT rules"
    echo ""
    
    echo "=== FORWARD Rules ==="
    $IPT -L FORWARD -n -v 2>/dev/null | grep -E "$WG_CLIENT_IF|$WG_UPSTREAM_IF" | head -5 || echo "No forward rules"
}

case "$1" in
    up)
        log "Setting up policy routing..."
        ensure_rt_tables
        setup_base_routes
        setup_special_ip_rules
        setup_iptables
        log "Policy routing enabled"
        ;;
    down)
        cleanup
        ;;
    reload)
        reload_special_ips
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {up|down|reload|status}"
        exit 1
        ;;
esac
