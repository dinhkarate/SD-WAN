#!/bin/bash
# Cleanup script - Remove method-1 WireGuard configs
# Run on VPS1 and VPS2 before deploying method-2

set -e

echo "=== WireGuard Method-1 Cleanup ==="

# Stop WG interfaces
echo "[1/5] Stopping WireGuard interfaces..."
wg-quick down wg0 2>/dev/null || echo "  wg0 not running"
wg-quick down wg1 2>/dev/null || echo "  wg1 not running"

# Disable systemd services
echo "[2/5] Disabling systemd services..."
systemctl disable wg-quick@wg0 2>/dev/null || true
systemctl disable wg-quick@wg1 2>/dev/null || true

# Backup and remove configs
echo "[3/5] Backing up and removing configs..."
if [ -d /etc/wireguard ]; then
    BACKUP_DIR="/etc/wireguard.backup.$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp /etc/wireguard/*.conf "$BACKUP_DIR/" 2>/dev/null || true
    cp /etc/wireguard/*key* "$BACKUP_DIR/" 2>/dev/null || true
    echo "  Backed up to: $BACKUP_DIR"
    
    rm -f /etc/wireguard/wg0.conf
    rm -f /etc/wireguard/wg1.conf
    echo "  Removed wg0.conf, wg1.conf"
fi

# Clear routing rules and ipset
echo "[4/5] Clearing routing rules..."
ip rule del fwmark 100 table 100 2>/dev/null || true
ip rule del fwmark 200 table 200 2>/dev/null || true
ip route flush table 100 2>/dev/null || true
ip route flush table 200 2>/dev/null || true
iptables -t mangle -F PREROUTING 2>/dev/null || true
ipset destroy special_ips 2>/dev/null || true
echo "  Cleared fwmark rules, tables, ipset"

# Clear NAT rules
echo "[5/5] Clearing NAT rules..."
iptables -t nat -F POSTROUTING 2>/dev/null || true
echo "  Cleared NAT POSTROUTING"

echo ""
echo "=== Cleanup Complete ==="
echo "Verify with:"
echo "  wg show"
echo "  ip rule show"
echo "  iptables -t nat -L POSTROUTING -n"
