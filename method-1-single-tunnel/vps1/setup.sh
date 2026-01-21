#!/bin/bash
#===============================================================================
# VPS1 Setup Script - Port Forward Only (Method 1)
# Chức năng: Forward UDP port 51820 từ VPS1 đến VPS2
#===============================================================================

set -e

# ===== CẤU HÌNH - THAY ĐỔI THEO MÔI TRƯỜNG CỦA BẠN =====
VPS2_PUBLIC_IP="VPS2_PUBLIC_IP"  # Thay bằng IP public của VPS2
WG_PORT="51820"
# ========================================================

echo "================================================"
echo "  VPS1 Port Forward Setup (Method 1)"
echo "================================================"

# Kiểm tra root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Vui lòng chạy script với quyền root (sudo)"
    exit 1
fi

# Kiểm tra đã thay đổi IP chưa
if [ "$VPS2_PUBLIC_IP" == "VPS2_PUBLIC_IP" ]; then
    echo "❌ Vui lòng thay đổi VPS2_PUBLIC_IP trong script này!"
    exit 1
fi

echo ""
echo "[1/4] Cài đặt packages cần thiết..."
apt update
apt install -y iptables iptables-persistent

echo ""
echo "[2/4] Bật IP Forwarding..."
# Bật ngay lập tức
sysctl -w net.ipv4.ip_forward=1

# Lưu vĩnh viễn
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

echo ""
echo "[3/4] Cấu hình iptables Port Forward..."

# Xác định interface mạng chính
MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
echo "    → Interface chính: $MAIN_INTERFACE"

# Xóa rules cũ nếu có
iptables -t nat -D PREROUTING -p udp --dport $WG_PORT -j DNAT --to-destination $VPS2_PUBLIC_IP:$WG_PORT 2>/dev/null || true
iptables -t nat -D POSTROUTING -p udp -d $VPS2_PUBLIC_IP --dport $WG_PORT -j MASQUERADE 2>/dev/null || true

# Thêm rules mới
# DNAT: Chuyển đổi destination IP từ VPS1 sang VPS2
iptables -t nat -A PREROUTING -p udp --dport $WG_PORT -j DNAT --to-destination $VPS2_PUBLIC_IP:$WG_PORT

# MASQUERADE: Đổi source IP thành IP của VPS1 khi gửi đến VPS2
iptables -t nat -A POSTROUTING -p udp -d $VPS2_PUBLIC_IP --dport $WG_PORT -j MASQUERADE

# Cho phép forward
iptables -A FORWARD -p udp -d $VPS2_PUBLIC_IP --dport $WG_PORT -j ACCEPT
iptables -A FORWARD -p udp -s $VPS2_PUBLIC_IP --sport $WG_PORT -j ACCEPT

echo ""
echo "[4/4] Lưu iptables rules..."
iptables-save > /etc/iptables/rules.v4

echo ""
echo "================================================"
echo "  ✅ VPS1 Port Forward đã được cấu hình!"
echo "================================================"
echo ""
echo "Thông tin cấu hình:"
echo "  - Forward: UDP $WG_PORT → $VPS2_PUBLIC_IP:$WG_PORT"
echo "  - Interface: $MAIN_INTERFACE"
echo ""
echo "Kiểm tra rules:"
echo "  iptables -t nat -L -n -v"
echo ""
