#!/bin/bash
#===============================================================================
# VPS Cleanup Script - Xóa sạch WireGuard config cũ
# Chạy trên cả VPS1 và VPS2 trước khi deploy lại
#===============================================================================

set -e

echo "================================================"
echo "  🧹 VPS WireGuard Cleanup"
echo "================================================"

# Stop all WireGuard interfaces
echo "[1/5] Stopping WireGuard interfaces..."
wg-quick down wg0 2>/dev/null || true
wg-quick down wg1 2>/dev/null || true

# Remove all ip rules related to WireGuard
echo "[2/5] Removing ip rules..."
ip rule del from 10.0.0.0/24 lookup 51821 2>/dev/null || true
ip rule del from 10.0.0.0/24 lookup 51820 2>/dev/null || true
# Remove any rules with table 51820 or 51821
ip rule show | grep -E "518[0-2][0-9]" | while read line; do
    priority=$(echo "$line" | cut -d: -f1)
    ip rule del priority $priority 2>/dev/null || true
done

# Flush routing tables
echo "[3/5] Flushing routing tables..."
ip route flush table 51820 2>/dev/null || true
ip route flush table 51821 2>/dev/null || true

# Clean iptables rules
echo "[4/5] Cleaning iptables rules..."
# Remove WireGuard related rules
iptables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -o wg0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i wg1 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -o wg1 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i wg0 -o wg1 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i wg1 -o wg0 -j ACCEPT 2>/dev/null || true

# Remove duplicate rules (run multiple times)
for i in 1 2 3 4 5; do
    iptables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -o wg0 -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i wg1 -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -o wg1 -j ACCEPT 2>/dev/null || true
done

# Remove NAT rules
iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -s 10.0.0.0/16 -o eth0 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o wg1 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -s 10.0.1.0/24 -o eth0 -j MASQUERADE 2>/dev/null || true

# Remove duplicates
for i in 1 2 3 4 5; do
    iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s 10.0.0.0/16 -o eth0 -j MASQUERADE 2>/dev/null || true
done

# Remove old config files (but keep keys)
echo "[5/5] Removing old config files..."
rm -f /etc/wireguard/wg0.conf
rm -f /etc/wireguard/wg1.conf

echo ""
echo "================================================"
echo "  ✅ Cleanup complete!"
echo "================================================"
echo ""
echo "Keys preserved in /etc/wireguard/:"
ls -la /etc/wireguard/*key* 2>/dev/null || echo "  (no keys found)"
echo ""
echo "Current state:"
echo "  - ip rule show:"
ip rule show
echo ""
echo "  - iptables FORWARD:"
iptables -L FORWARD -v -n | head -10
echo ""
echo "Ready for fresh deploy!"
