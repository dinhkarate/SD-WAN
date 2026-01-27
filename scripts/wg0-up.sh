#!/bin/bash
# WG0 Interface Up Script - SAFE VERSION
# Chỉ ảnh hưởng traffic từ wg0, không chạm main routing table

set -e

source /etc/sdwan/config.env

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "WG0 interface coming up..."

# Enable IP forwarding
sysctl -q -w net.ipv4.ip_forward=1

# Get default gateway (for special IPs going to internet)
DEFAULT_GW=$(ip route show default | head -1 | awk '{print $3}')
DEFAULT_IF=$(ip route show default | head -1 | awk '{print $5}')

if [ -z "$DEFAULT_GW" ]; then
    log "ERROR: Cannot find default gateway"
    exit 1
fi

log "Default gateway: $DEFAULT_GW via $DEFAULT_IF"

# ============================================
# ROUTING TABLES (chỉ cho traffic từ wg0)
# ============================================
# Table 100: Special IPs -> eth0 (direct internet)
# Table 200: Default -> wg1 (via WG2)

# Thêm entries vào /etc/iproute2/rt_tables nếu chưa có
grep -q "^100" /etc/iproute2/rt_tables || echo "100 special" >> /etc/iproute2/rt_tables
grep -q "^200" /etc/iproute2/rt_tables || echo "200 tunnel" >> /etc/iproute2/rt_tables

# Setup table 100: route qua eth0 (cho special IPs)
ip route flush table 100 2>/dev/null || true
ip route add default via $DEFAULT_GW dev $DEFAULT_IF table 100

# Setup table 200: route qua wg1 (cho traffic còn lại)
ip route flush table 200 2>/dev/null || true
# Chờ wg1 up trước khi add route
if ip link show wg1 &>/dev/null; then
    ip route add default via 10.20.0.2 dev wg1 table 200
else
    log "WARNING: wg1 not up yet, table 200 route will be added later"
fi

# ============================================
# IPSET (danh sách IP đặc biệt)
# ============================================
ipset create special_ips hash:net -exist
/etc/sdwan/scripts/load-special-ips.sh || log "WARNING: Failed to load special IPs"

# ============================================
# IPTABLES MARKING (chỉ cho packets từ wg0)
# ============================================
# Xóa rules cũ trước
iptables -t mangle -D PREROUTING -i wg0 -m set --match-set special_ips dst -j MARK --set-mark 100 2>/dev/null || true
iptables -t mangle -D PREROUTING -i wg0 -m mark --mark 0 -j MARK --set-mark 200 2>/dev/null || true

# Mark packets từ wg0 đến special IPs -> mark 100
iptables -t mangle -A PREROUTING -i wg0 -m set --match-set special_ips dst -j MARK --set-mark 100
# Mark packets còn lại từ wg0 -> mark 200
iptables -t mangle -A PREROUTING -i wg0 -m mark --mark 0 -j MARK --set-mark 200

# ============================================
# ROUTING RULES (chỉ áp dụng cho marked packets)
# ============================================
# Xóa rules cũ
ip rule del fwmark 100 table 100 2>/dev/null || true
ip rule del fwmark 200 table 200 2>/dev/null || true

# Thêm rules mới - priority cao hơn main table
ip rule add fwmark 100 table 100 priority 100
ip rule add fwmark 200 table 200 priority 200

# ============================================
# NAT & FORWARDING
# ============================================
# NAT cho traffic ra eth0 (special IPs)
iptables -t nat -C POSTROUTING -o $DEFAULT_IF -m mark --mark 100 -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o $DEFAULT_IF -m mark --mark 100 -j MASQUERADE

# NAT cho traffic ra wg1 (tunnel)
iptables -t nat -C POSTROUTING -o wg1 -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o wg1 -j MASQUERADE

# Allow forwarding cho wg0
iptables -C FORWARD -i wg0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i wg0 -j ACCEPT
iptables -C FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

log "WG0 up complete. Special IPs: $(ipset list special_ips 2>/dev/null | grep -c '^[0-9]' || echo 0) entries"
