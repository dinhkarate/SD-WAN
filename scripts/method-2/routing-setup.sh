#!/bin/bash
# Method-2 Routing Setup Script for Dual WireGuard Servers
# Usage: routing-setup.sh [up|down] [wg0|wg1]
#
# This script manages routing for 2 WG servers on the same VPS.
# Each server has its own subnet and can optionally use split routing.

set -e

ACTION=$1
INTERFACE=$2

# Config
SPECIAL_IPS_FILE="/etc/sdwan/special-ips.txt"
IPSET_NAME="special_ips"

# Routing tables (defined in /etc/iproute2/rt_tables)
TABLE_SPECIAL=100  # Route via eth0 (direct)
TABLE_VPN=200      # Route via VPN tunnel (if using double tunnel)

# Get the gateway IP for eth0
get_default_gw() {
    ip route show default | awk '/default/ {print $3; exit}'
}

# Setup ipset for special IPs
setup_ipset() {
    if ! ipset list "$IPSET_NAME" &>/dev/null; then
        ipset create "$IPSET_NAME" hash:net family inet hashsize 4096 maxelem 100000
    fi
    
    # Load IPs if file exists
    if [[ -f "$SPECIAL_IPS_FILE" ]]; then
        ipset create "${IPSET_NAME}_tmp" hash:net family inet hashsize 4096 maxelem 100000
        
        while IFS= read -r ip || [[ -n "$ip" ]]; do
            [[ -z "$ip" || "$ip" =~ ^# ]] && continue
            ip="${ip%%#*}"  # Remove inline comments
            ip="${ip// /}"  # Trim whitespace
            [[ -n "$ip" ]] && ipset add "${IPSET_NAME}_tmp" "$ip" 2>/dev/null || true
        done < "$SPECIAL_IPS_FILE"
        
        # Atomic swap
        ipset swap "${IPSET_NAME}_tmp" "$IPSET_NAME"
        ipset destroy "${IPSET_NAME}_tmp"
        
        echo "[routing-setup] Loaded $(ipset list $IPSET_NAME | grep -c '^[0-9]') special IPs"
    fi
}

# Setup routing tables in /etc/iproute2/rt_tables
setup_rt_tables() {
    grep -q "^${TABLE_SPECIAL}" /etc/iproute2/rt_tables || echo "$TABLE_SPECIAL special" >> /etc/iproute2/rt_tables
    grep -q "^${TABLE_VPN}" /etc/iproute2/rt_tables || echo "$TABLE_VPN vpn" >> /etc/iproute2/rt_tables
}

# Setup fwmark rules for policy routing
setup_fwmark_rules() {
    local gw
    gw=$(get_default_gw)
    
    # Mark packets matching special_ips ipset
    if ! iptables -t mangle -C PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark 100 2>/dev/null; then
        iptables -t mangle -A PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark 100
    fi
    
    # Route marked packets via eth0 (table 100)
    if ! ip rule show | grep -q "fwmark 0x64"; then
        ip rule add fwmark 100 table $TABLE_SPECIAL priority 100
    fi
    
    # Add default route to table 100 via eth0
    if ! ip route show table $TABLE_SPECIAL | grep -q "default"; then
        ip route add default via "$gw" dev eth0 table $TABLE_SPECIAL
    fi
    
    echo "[routing-setup] Policy routing configured: fwmark 100 -> table $TABLE_SPECIAL -> eth0"
}

# Cleanup fwmark rules
cleanup_fwmark_rules() {
    iptables -t mangle -D PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark 100 2>/dev/null || true
    ip rule del fwmark 100 table $TABLE_SPECIAL 2>/dev/null || true
    ip route flush table $TABLE_SPECIAL 2>/dev/null || true
}

# Main
case "$ACTION" in
    up)
        echo "[routing-setup] Setting up routing for $INTERFACE"
        setup_rt_tables
        setup_ipset
        setup_fwmark_rules
        echo "[routing-setup] Done"
        ;;
    down)
        echo "[routing-setup] Cleaning up routing for $INTERFACE"
        # Only cleanup if no other WG interfaces are up
        if ! ip link show wg0 2>/dev/null | grep -q "UP" && ! ip link show wg1 2>/dev/null | grep -q "UP"; then
            cleanup_fwmark_rules
            echo "[routing-setup] All rules cleaned up"
        else
            echo "[routing-setup] Other WG interfaces still up, keeping rules"
        fi
        ;;
    reload)
        echo "[routing-setup] Reloading special IPs"
        setup_ipset
        ;;
    *)
        echo "Usage: $0 [up|down|reload] [interface]"
        exit 1
        ;;
esac
