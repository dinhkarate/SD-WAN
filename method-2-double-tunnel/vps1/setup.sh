#!/bin/bash
#===============================================================================
# VPS1 Setup Script - WireGuard Server + Client (Method 2)
# Chức năng: 
#   - wg0: WireGuard Server nhận kết nối từ PC
#   - wg1: WireGuard Client kết nối đến VPS2
#===============================================================================

set -e

echo "================================================"
echo "  VPS1 WireGuard Setup (Method 2)"
echo "  - wg0: Server cho PC"
echo "  - wg1: Client đến VPS2"
echo "================================================"

# Kiểm tra root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Vui lòng chạy script với quyền root (sudo)"
    exit 1
fi

echo ""
echo "[1/8] Cài đặt WireGuard..."
apt update
apt install -y wireguard wireguard-tools iptables

echo ""
echo "[2/8] Tạo key pairs..."
cd /etc/wireguard

# Keys cho wg0 (server cho PC)
if [ ! -f "vps1_wg0_privatekey" ]; then
    wg genkey | tee vps1_wg0_privatekey | wg pubkey > vps1_wg0_publickey
    chmod 600 vps1_wg0_privatekey
    echo "    ✅ Keys cho wg0 đã được tạo"
else
    echo "    ⚠️  Keys cho wg0 đã tồn tại, bỏ qua..."
fi

# Keys cho wg1 (client đến VPS2)
if [ ! -f "vps1_wg1_privatekey" ]; then
    wg genkey | tee vps1_wg1_privatekey | wg pubkey > vps1_wg1_publickey
    chmod 600 vps1_wg1_privatekey
    echo "    ✅ Keys cho wg1 đã được tạo"
else
    echo "    ⚠️  Keys cho wg1 đã tồn tại, bỏ qua..."
fi

echo ""
echo "================================================"
echo "  🔑 VPS1 PUBLIC KEYS:"
echo "================================================"
echo "  wg0 (cho PC):     $(cat vps1_wg0_publickey)"
echo "  wg1 (cho VPS2):   $(cat vps1_wg1_publickey)"
echo "================================================"
echo ""

echo "[3/7] Kiểm tra files cấu hình WireGuard..."
echo "    (IP Forwarding sẽ được bật tự động qua PostUp trong wg0.conf)"
if [ ! -f "/etc/wireguard/wg0.conf" ]; then
    echo "    ⚠️  Chưa có file wg0.conf!"
    echo "    → Copy file wg0.conf vào /etc/wireguard/"
    exit 1
fi

if [ ! -f "/etc/wireguard/wg1.conf" ]; then
    echo "    ⚠️  Chưa có file wg1.conf!"
    echo "    → Copy file wg1.conf vào /etc/wireguard/"
    exit 1
fi

echo ""
echo "[4/7] Thay thế Private Keys trong configs..."
WG0_PRIVATE_KEY=$(cat /etc/wireguard/vps1_wg0_privatekey)
WG1_PRIVATE_KEY=$(cat /etc/wireguard/vps1_wg1_privatekey)

sed -i "s|<VPS1_WG0_PRIVATE_KEY>|$WG0_PRIVATE_KEY|g" /etc/wireguard/wg0.conf
sed -i "s|<VPS1_WG1_PRIVATE_KEY>|$WG1_PRIVATE_KEY|g" /etc/wireguard/wg1.conf

echo ""
echo "[5/7] Khởi động WireGuard wg0 (Server cho PC)..."
wg-quick down wg0 2>/dev/null || true
wg-quick up wg0
systemctl enable wg-quick@wg0

echo ""
echo "[6/7] Khởi động WireGuard wg1 (Client đến VPS2)..."
wg-quick down wg1 2>/dev/null || true
wg-quick up wg1
systemctl enable wg-quick@wg1

echo ""
echo "[7/7] Cấu hình routing..."
# Route traffic từ PC (10.0.0.0/24) qua wg1 đến VPS2
# Điều này được thực hiện tự động qua WireGuard AllowedIPs

echo ""
echo "================================================"
echo "  ✅ VPS1 WireGuard đã được cấu hình!"
echo "================================================"
echo ""
echo "Trạng thái WireGuard:"
echo ""
echo "--- wg0 (Server cho PC) ---"
wg show wg0
echo ""
echo "--- wg1 (Client đến VPS2) ---"
wg show wg1
echo ""
echo "Lưu ý:"
echo "  1. Đảm bảo đã thay <PC_PUBLIC_KEY> trong wg0.conf"
echo "  2. Đảm bảo đã thay <VPS2_PUBLIC_KEY> và VPS2_PUBLIC_IP trong wg1.conf"
echo "  3. Firewall cần mở UDP port 51820"
echo ""
