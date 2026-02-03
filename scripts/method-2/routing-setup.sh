#!/bin/bash
#
# VPS1 Policy Routing Script - Method 2 (Using ipset)
# 
# Kiến trúc (LAB 3 - Reversed):
#   PC1 ──wg0──► VPS1 ──wg1──► VPS2 ──► Internet (China IPs)
#                 │
#                 └─ Other IPs ─► eth0 (VPS1 IP)
#
# Traffic flow:
#   - Packets từ PC1 đến China IPs → mark 200 → forward qua wg1 → VPS2
#   - Packets từ PC1 đến các IP khác → mark 100 → ra eth0 (IP VPS1)
#

# Configuration
IPSET_FILE='/etc/sdwan/chinaip.txt'
WAN_IF="eth0"
WG_CLIENT_IF="wg0"
WG_UPSTREAM_IF="wg1"
VPS2_IP="10.20.0.2"

# Get default gateway
get_gateway() {
    ip route | grep "default via" | grep "$WAN_IF" | awk '{print $3}' | head -1
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

load_ipset() {
    # Destroy existing ipset
    ipset destroy china_ips 2>/dev/null || true
    
    # Create new ipset
    ipset create china_ips hash:net hashsize 8192 maxelem 65536
    
    if [ -f "$IPSET_FILE" ]; then
        local count=0
        while IFS= read -r ip || [ -n "$ip" ]; do
            # Skip empty lines and comments
            [[ -z "$ip" || "$ip" =~ ^# ]] && continue
            ipset add china_ips "$ip" 2>/dev/null && count=$((count + 1))
        done < "$IPSET_FILE"
        log "Loaded $count China IPs into ipset"
    else
        log "Warning: $IPSET_FILE not found - no China IP routing"
    fi
}

ensure_rt_tables() {
    # LAB 3: Table 100 = VPS1 exit (Other IPs), Table 200 = VPS2 exit (China IPs)
    # Check by table number, not name (in case old names exist)
    grep -q '^100 ' /etc/iproute2/rt_tables 2>/dev/null || \
        echo '100 vps1exit' >> /etc/iproute2/rt_tables
    grep -q '^200 ' /etc/iproute2/rt_tables 2>/dev/null || \
        echo '200 vps2exit' >> /etc/iproute2/rt_tables
}

setup_routing() {
    local gateway=$(get_gateway)
    
    if [ -z "$gateway" ]; then
        log "Error: Cannot detect default gateway for $WAN_IF"
        return 1
    fi
    
    log "Using gateway: $gateway"
    
    # Setup routing tables (LAB 3 - Reversed)
    # Table 100: Route through local eth0 (for Other IPs - default)
    ip route replace default via $gateway dev $WAN_IF table 100
    
    # Table 200: Route through VPS2 (wg1) (for China IPs)
    ip route replace default via $VPS2_IP dev $WG_UPSTREAM_IF table 200
    
    # Add ip rules for fwmark
    ip rule add fwmark 100 lookup 100 prio 100 2>/dev/null || true
    ip rule add fwmark 200 lookup 200 prio 99 2>/dev/null || true
    
    log "Routing tables configured"
}

setup_iptables() {
    # Clean existing rules first
    iptables -t mangle -D PREROUTING -i $WG_CLIENT_IF -j MARK --set-mark 100 2>/dev/null || true
    iptables -t mangle -D PREROUTING -i $WG_CLIENT_IF -m set --match-set china_ips dst -j MARK --set-mark 200 2>/dev/null || true
    iptables -t nat -D POSTROUTING -m mark --mark 100 -o $WAN_IF -j MASQUERADE 2>/dev/null || true
    iptables -t nat -D POSTROUTING -m mark --mark 200 -o $WAN_IF -j MASQUERADE 2>/dev/null || true
    
    # Mark all traffic from wg0 with 100 (default: go to VPS1 eth0)
    iptables -t mangle -A PREROUTING -i $WG_CLIENT_IF -j MARK --set-mark 100
    
    # Override mark for China IPs with 200 (go to VPS2 via wg1)
    iptables -t mangle -A PREROUTING -i $WG_CLIENT_IF -m set --match-set china_ips dst -j MARK --set-mark 200
    
    # NAT for traffic exiting through eth0 (Other IPs - mark 100)
    iptables -t nat -A POSTROUTING -m mark --mark 100 -o $WAN_IF -j MASQUERADE
    
    log "iptables rules configured"
}

cleanup() {
    log "Cleaning up..."
    
    # Remove iptables rules
    iptables -t mangle -D PREROUTING -i $WG_CLIENT_IF -j MARK --set-mark 100 2>/dev/null || true
    iptables -t mangle -D PREROUTING -i $WG_CLIENT_IF -m set --match-set china_ips dst -j MARK --set-mark 200 2>/dev/null || true
    iptables -t nat -D POSTROUTING -m mark --mark 100 -o $WAN_IF -j MASQUERADE 2>/dev/null || true
    iptables -t nat -D POSTROUTING -m mark --mark 200 -o $WAN_IF -j MASQUERADE 2>/dev/null || true
    
    # Remove ip rules
    ip rule del fwmark 100 lookup 100 2>/dev/null || true
    ip rule del fwmark 200 lookup 200 2>/dev/null || true
    
    # Flush routing tables
    ip route flush table 100 2>/dev/null || true
    ip route flush table 200 2>/dev/null || true
    
    # Destroy ipset
    ipset destroy china_ips 2>/dev/null || true
    
    log "Cleanup complete"
}

status() {
    echo "=== ipset china_ips ==="
    ipset list china_ips 2>/dev/null | head -10 || echo "Not created"
    echo "Number of entries: $(ipset list china_ips 2>/dev/null | grep -c '^[0-9]' || echo 0)"
    echo ""
    
    echo "=== IP Rules ==="
    ip rule show | grep -E 'fwmark|100|200' | head -5
    echo ""
    
    echo "=== Table 100 (VPS1 local exit - Other IPs) ==="
    ip route show table 100 2>/dev/null || echo "Empty"
    echo ""
    
    echo "=== Table 200 (VPS2 exit - China IPs) ==="
    ip route show table 200 2>/dev/null || echo "Empty"
    echo ""
    
    echo "=== iptables mangle ==="
    iptables -t mangle -L PREROUTING -n -v 2>/dev/null | grep -E 'wg0|china_ips|MARK' | head -5
    echo ""
    
    echo "=== Test IPs ==="
    echo -n "8.8.8.8 (Google): "
    ipset test china_ips 8.8.8.8 2>&1 | grep -q "is in set" && echo "China (VPS2)" || echo "Other (VPS1)"
    echo -n "223.5.5.5 (Alibaba): "
    ipset test china_ips 223.5.5.5 2>&1 | grep -q "is in set" && echo "China (VPS2)" || echo "Other (VPS1)"
}

case "$1" in
    up)
        log "Setting up split routing..."
        ensure_rt_tables
        load_ipset
        setup_routing
        setup_iptables
        log "Split routing enabled: China→VPS2, Others→VPS1"
        ;;
    down)
        cleanup
        ;;
    reload)
        load_ipset
        log "ipset reloaded"
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {up|down|reload|status}"
        exit 1
        ;;
esac
