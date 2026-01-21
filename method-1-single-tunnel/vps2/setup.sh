#!/bin/bash
#===============================================================================
# VPS2 Setup Script - WireGuard Client + NAT (Method 1 - Single Tunnel)
# Chức năng: WG Client kết nối đến VPS1, NAT traffic ra Internet
#===============================================================================

set -e

# ===== CẤU HÌNH - THAY ĐỔI THEO MÔI TRƯỜNG CỦA BẠN =====
VPS1_PUBLIC_IP="VPS1_PUBLIC_IP"  # Thay bằng IP public của VPS1
# ========================================================

echo "================================================"
echo "  VPS2 WireGuard Client Setup (Method 1)"
echo "================================================"

# Kiểm tra root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Vui lòng chạy script với quyền root (sudo)"
    exit 1
fi

# Load config.env nếu có
if [ -f "/root/sd-wan/config.env" ]; then
    echo "    📄 Đọc cấu hình từ config.env..."
    source /root/sd-wan/config.env
    VPS1_PUBLIC_IP="$VPS1_HOST"
fi

# Kiểm tra đã thay đổi IP chưa
if [ "$VPS1_PUBLIC_IP" == "VPS1_PUBLIC_IP" ]; then
    echo "❌ Vui lòng thay đổi VPS1_PUBLIC_IP trong script này hoặc config.env!"
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

echo "[3/6] Kiểm tra file cấu hình WireGuard..."
if [ ! -f "/etc/wireguard/wg0.conf" ]; then
    echo "    ⚠️  Chưa có file wg0.conf!"
    echo "    → Copy file wg0.conf vào /etc/wireguard/"
    echo "    → Sau đó chạy lại script này"
    exit 1
fi

echo ""
echo "[4/6] Thay thế Private Key và VPS1 IP trong config..."
PRIVATE_KEY=$(cat /etc/wireguard/vps2_privatekey)
sed -i "s|<VPS2_PRIVATE_KEY>|$PRIVATE_KEY|g" /etc/wireguard/wg0.conf
sed -i "s|VPS1_PUBLIC_IP|$VPS1_PUBLIC_IP|g" /etc/wireguard/wg0.conf

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
echo "  ✅ VPS2 WireGuard Client đã được cấu hình!"
echo "================================================"
echo ""
echo "Trạng thái WireGuard:"
wg show
echo ""
echo "Lưu ý:"
echo "  1. Đảm bảo đã thay <VPS1_PUBLIC_KEY> trong wg0.conf"
echo "  2. Đảm bảo VPS1 đã thêm <VPS2_PUBLIC_KEY> vào cấu hình"
echo ""
echo "Public Key của VPS2 (copy để cấu hình VPS1):"
cat /etc/wireguard/vps2_publickey
echo ""
