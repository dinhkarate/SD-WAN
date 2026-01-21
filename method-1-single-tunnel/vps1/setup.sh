#!/bin/bash
#===============================================================================
# VPS1 Setup Script - WireGuard Server (Method 1 - Single Tunnel)
# Chức năng: WG Server nhận kết nối từ PC và VPS2, forward traffic giữa chúng
#===============================================================================

set -e

echo "================================================"
echo "  VPS1 WireGuard Server Setup (Method 1)"
echo "================================================"

# Kiểm tra root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Vui lòng chạy script với quyền root (sudo)"
    exit 1
fi

echo ""
echo "[1/6] Cài đặt WireGuard..."
apt update
apt install -y wireguard wireguard-tools iptables

echo ""
echo "[2/6] Tạo key pair..."
cd /etc/wireguard

if [ ! -f "vps1_privatekey" ]; then
    wg genkey | tee vps1_privatekey | wg pubkey > vps1_publickey
    chmod 600 vps1_privatekey
    echo "    ✅ Keys đã được tạo"
else
    echo "    ⚠️  Keys đã tồn tại, bỏ qua..."
fi

echo ""
echo "================================================"
echo "  🔑 VPS1 PUBLIC KEY (lưu lại để cấu hình PC và VPS2):"
echo "================================================"
cat vps1_publickey
echo "================================================"
echo ""

echo "[3/6] Kiểm tra file cấu hình WireGuard..."
if [ ! -f "/etc/wireguard/wg0.conf" ]; then
    echo "    ⚠️  Chưa có file wg0.conf!"
    echo "    → Copy file wg0.conf vào /etc/wireguard/"
    echo "    → Sau đó chạy lại script này"
    exit 1
fi

echo ""
echo "[4/6] Thay thế Private Key trong config..."
PRIVATE_KEY=$(cat /etc/wireguard/vps1_privatekey)
sed -i "s|<VPS1_PRIVATE_KEY>|$PRIVATE_KEY|g" /etc/wireguard/wg0.conf

echo ""
echo "[5/6] Khởi động WireGuard..."
# Dừng nếu đang chạy
wg-quick down wg0 2>/dev/null || true

# Khởi động
wg-quick up wg0

# Enable auto-start
systemctl enable wg-quick@wg0

echo ""
echo "[6/6] Kiểm tra trạng thái..."

echo ""
echo "================================================"
echo "  ✅ VPS1 WireGuard Server đã được cấu hình!"
echo "================================================"
echo ""
echo "Trạng thái WireGuard:"
wg show
echo ""
echo "Lưu ý:"
echo "  1. Đảm bảo đã thay <PC_PUBLIC_KEY> trong wg0.conf"
echo "  2. Đảm bảo đã thay <VPS2_PUBLIC_KEY> trong wg0.conf"
echo "  3. Firewall cần mở UDP port 51820"
echo ""
echo "Public Key của VPS1 (copy để cấu hình PC và VPS2):"
cat /etc/wireguard/vps1_publickey
echo ""
