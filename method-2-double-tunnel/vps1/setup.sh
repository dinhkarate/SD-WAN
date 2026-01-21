#!/bin/bash
#===============================================================================
# VPS1 Setup Script - WireGuard Server + Client (Method 2)
# Chức năng: 
#   - wg0: WireGuard Server nhận kết nối từ PC
#   - wg1: WireGuard Client kết nối đến VPS2
#
# ⚠️ POLICY ROUTING:
#   - Table 51821 được dùng cho wg1 để tránh mất kết nối SSH
#   - Traffic từ PC → table 51821 → wg1 → VPS2 → Internet
#   - Traffic VPS1 (SSH) → table main → Internet trực tiếp
#===============================================================================

set -e

echo "================================================"
echo "  VPS1 WireGuard Setup (Method 2)"
echo "  - wg0: Server cho PC"
echo "  - wg1: Client đến VPS2"
echo "  🔒 Với Policy Routing (không mất kết nối VPS1)"
echo "================================================"

# Kiểm tra root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Vui lòng chạy script với quyền root (sudo)"
    exit 1
fi

echo ""
echo "[1/7] Cài đặt WireGuard..."
apt update
apt install -y wireguard wireguard-tools iptables iproute2

echo ""
echo "[2/7] Tạo key pairs..."
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
echo "[5/7] Enable WireGuard auto-start (nhưng KHÔNG khởi động ngay)..."
systemctl enable wg-quick@wg0 2>/dev/null || true
systemctl enable wg-quick@wg1 2>/dev/null || true
echo "    ✅ WireGuard đã được enable auto-start"

echo ""
echo "[6/7] Mở firewall ports..."
iptables -A INPUT -p udp --dport 51820 -j ACCEPT 2>/dev/null || true

echo ""
echo "[7/7] Hoàn tất..."

echo ""
echo "================================================"
echo "  ✅ VPS1 WireGuard đã được cấu hình!"
echo "================================================"
echo ""
echo "⚠️  QUAN TRỌNG: WireGuard CHƯA được khởi động!"
echo ""
echo "Để khởi động WireGuard thủ công, chạy:"
echo "  wg-quick up wg1    # Client đến VPS2 (start TRƯỚC)"
echo "  wg-quick up wg0    # Server cho PC"
echo ""
echo "Hoặc restart server để auto-start."
echo ""
echo "🔑 Public Keys:"
echo "  wg0 (cho PC):   $(cat /etc/wireguard/vps1_wg0_publickey)"
echo "  wg1 (cho VPS2): $(cat /etc/wireguard/vps1_wg1_publickey)"
echo ""
echo "📌 POLICY ROUTING (Table 51821):"
echo "  - Traffic từ PC → table 51821 → wg1 → VPS2"
echo "  - Traffic VPS1 → table main → Internet trực tiếp"
echo ""
echo "Kiểm tra routing:"
echo "  ip route show table 51821"
echo "  ip rule show"
echo ""
