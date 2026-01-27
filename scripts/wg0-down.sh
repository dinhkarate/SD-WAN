#!/bin/bash
# WG0 Interface Down Script - SAFE VERSION
# Cleanup routing rules mà không ảnh hưởng main table

set -e

source /etc/sdwan/config.env

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "WG0 interface going down..."

DEFAULT_IF=$(ip route show default | head -1 | awk '{print $5}')

# ============================================
# Remove iptables rules
# ============================================
iptables -t mangle -D PREROUTING -i wg0 -m set --match-set special_ips dst -j MARK --set-mark 100 2>/dev/null || true
iptables -t mangle -D PREROUTING -i wg0 -m mark --mark 0 -j MARK --set-mark 200 2>/dev/null || true
iptables -t nat -D POSTROUTING -o $DEFAULT_IF -m mark --mark 100 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -o wg1 -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

# ============================================
# Remove routing rules (chỉ xóa rules của mình)
# ============================================
ip rule del fwmark 100 table 100 2>/dev/null || true
ip rule del fwmark 200 table 200 2>/dev/null || true

# Flush custom tables (không chạm main table)
ip route flush table 100 2>/dev/null || true
ip route flush table 200 2>/dev/null || true

# ============================================
# Destroy ipset
# ============================================
ipset destroy special_ips 2>/dev/null || true

log "WG0 down complete. Cleanup finished."
