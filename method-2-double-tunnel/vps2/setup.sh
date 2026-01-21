#!/bin/bash
#===============================================================================
# VPS2 Setup Script - WireGuard Server + NAT (Method 2)
# Chức năng: WireGuard Server nhận kết nối từ VPS1, NAT ra Internet
#===============================================================================

set -e

echo "================================================"
echo "  VPS2 WireGuard Server Setup (Method 2)"
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

if [ ! -f "vps2_privatekey" ]; then
    wg genkey | tee vps2_privatekey | wg pubkey > vps2_publickey
    chmod 600 vps2_privatekey
    echo "    ✅ Keys đã được tạo"
else
    echo "    ⚠️  Keys đã tồn tại, bỏ qua..."
fi

echo ""
echo "================================================"
echo "  🔑 VPS2 PUBLIC KEY (lưu lại để cấu hình VPS1):"
echo "================================================"
cat vps2_publickey
echo "================================================"
echo ""

echo "[3/5] Kiểm tra file cấu hình WireGuard..."
echo "    (IP Forwarding sẽ được bật tự động qua PostUp trong wg0.conf)"
if [ ! -f "/etc/wireguard/wg0.conf" ]; then
    echo "    ⚠️  Chưa có file wg0.conf!"
    echo "    → Copy file wg0.conf vào /etc/wireguard/"
    echo "    → Sau đó chạy lại script này"
    exit 1
fi

echo ""
echo "[4/5] Thay thế Private Key trong config..."
PRIVATE_KEY=$(cat /etc/wireguard/vps2_privatekey)
sed -i "s|<VPS2_PRIVATE_KEY>|$PRIVATE_KEY|g" /etc/wireguard/wg0.conf

echo ""
echo "[5/5] Khởi động WireGuard..."
# Dừng nếu đang chạy
wg-quick down wg0 2>/dev/null || true

# Khởi động
wg-quick up wg0

# Enable auto-start
systemctl enable wg-quick@wg0

echo ""
echo "================================================"
echo "  ✅ VPS2 WireGuard Server đã được cấu hình!"
echo "================================================"
echo ""
echo "Trạng thái WireGuard:"
wg show
echo ""
echo "Lưu ý:"
echo "  1. Đảm bảo đã thay <VPS1_WG1_PUBLIC_KEY> trong wg0.conf"
echo "  2. Firewall cần mở UDP port 51821"
echo ""
