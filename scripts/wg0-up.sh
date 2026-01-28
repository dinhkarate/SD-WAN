#!/bin/bash
#
# VPS1 Routing Script - Method 1 (Single Interface Chain)
#
# Kiến trúc:
#   PC1 (10.10.0.2) ──wg0──► VPS1 (10.10.0.1) ──wg0──► VPS2 (10.10.0.3) ──► Internet
#                              │
#                              └─ Special IPs ─► eth0 (VPS1 IP)
#
# Logic:
#   1. Traffic từ PC1 đến special IPs → mark 100 → route qua eth0
#   2. Traffic từ PC1 đến IP khác → forward trong wg0 tới VPS2
#

set -e

IPSET_NAME="special_ips"
MARK_DIRECT=100
TABLE_DIRECT=100
TABLE_VPN=200
WAN_IF="eth0"
PC1_IP="10.10.0.2"
VPS2_IP="10.10.0.3"
SPECIAL_IPS_FILE="/etc/sdwan/special-ips.txt"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

up() {
    log "Setting up routing..."
    
    # 1. Get default gateway
    GATEWAY=$(ip route | grep "default via" | grep "$WAN_IF" | awk '{print $3}' | head -1)
    log "Default gateway: $GATEWAY"
    
    # 2. Create ipset for special IPs
    ipset create "$IPSET_NAME" hash:net 2>/dev/null || ipset flush "$IPSET_NAME"
    if [[ -f "$SPECIAL_IPS_FILE" ]]; then
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            ipset add "$IPSET_NAME" "$line" 2>/dev/null || true
        done < "$SPECIAL_IPS_FILE"
        log "Loaded special IPs"
    fi
    
    # 3. Routing tables
    # Table 100: Special IPs → eth0
    ip route replace default via "$GATEWAY" dev "$WAN_IF" table $TABLE_DIRECT
    
    # Table 200: Default traffic → VPS2
    ip route replace default via "$VPS2_IP" dev wg0 table $TABLE_VPN
    
    # 4. IP rules (order matters!)
    # Priority 100: Special IPs (marked) → table 100 (eth0)
    ip rule add fwmark $MARK_DIRECT table $TABLE_DIRECT priority 100 2>/dev/null || true
    
    # Priority 150: All PC1 traffic → table 200 (VPS2)  
    ip rule add from $PC1_IP table $TABLE_VPN priority 150 2>/dev/null || true
    
    # 5. Mangle: Mark special IP packets
    iptables -t mangle -A PREROUTING -s $PC1_IP -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark $MARK_DIRECT
    
    # 6. NAT for special IPs going out eth0
    iptables -t nat -A POSTROUTING -s $PC1_IP -o $WAN_IF -j MASQUERADE
    
    # 7. Forward rules
    # wg0 → wg0 (PC1 → VPS2)
    iptables -A FORWARD -i wg0 -o wg0 -j ACCEPT
    # wg0 → eth0 (PC1 → special IPs)
    iptables -A FORWARD -s $PC1_IP -o $WAN_IF -j ACCEPT
    iptables -A FORWARD -i $WAN_IF -d $PC1_IP -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    log "Routing setup complete"
}

down() {
    log "Cleaning up..."
    
    # Remove iptables
    iptables -t mangle -D PREROUTING -s $PC1_IP -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark $MARK_DIRECT 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s $PC1_IP -o $WAN_IF -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i wg0 -o wg0 -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -s $PC1_IP -o $WAN_IF -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i $WAN_IF -d $PC1_IP -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    
    # Remove ip rules
    ip rule del fwmark $MARK_DIRECT table $TABLE_DIRECT 2>/dev/null || true
    ip rule del from $PC1_IP table $TABLE_VPN 2>/dev/null || true
    
    # Flush tables
    ip route flush table $TABLE_DIRECT 2>/dev/null || true
    ip route flush table $TABLE_VPN 2>/dev/null || true
    
    # Remove ipset
    ipset destroy "$IPSET_NAME" 2>/dev/null || true
    
    log "Cleanup complete"
}

status() {
    echo "=== IPSet ==="
    ipset list "$IPSET_NAME" 2>/dev/null | grep -E "^(Name|Members)" || echo "Not found"
    ipset list "$IPSET_NAME" 2>/dev/null | tail -5
    echo ""
    echo "=== Routing Tables ==="
    echo "Table $TABLE_DIRECT (special→eth0):"
    ip route show table $TABLE_DIRECT 2>/dev/null || echo "Empty"
    echo "Table $TABLE_VPN (default→VPS2):"
    ip route show table $TABLE_VPN 2>/dev/null || echo "Empty"
    echo ""
    echo "=== IP Rules ==="
    ip rule show | grep -E "$TABLE_DIRECT|$TABLE_VPN|fwmark"
    echo ""
    echo "=== Mangle ==="
    iptables -t mangle -L PREROUTING -n | grep -E "special|$MARK_DIRECT" || echo "No rules"
}

reload() {
    log "Reloading special IPs..."
    ipset flush "$IPSET_NAME"
    if [[ -f "$SPECIAL_IPS_FILE" ]]; then
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            ipset add "$IPSET_NAME" "$line" 2>/dev/null || true
        done < "$SPECIAL_IPS_FILE"
    fi
    log "Reloaded"
}

case "$1" in
    up) up ;;
    down) down ;;
    status) status ;;
    reload) reload ;;
    *) echo "Usage: $0 {up|down|status|reload}" ;;
esac
