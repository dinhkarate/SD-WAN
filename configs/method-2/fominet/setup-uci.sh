#!/bin/sh
# =============================================================================
# fominet (OpenWRT) - UCI Setup Script cho WireGuard wg1
# Vai trò: VPS2 / Exit Node cho China IPs
#
# Chạy script này trên fominet (192.168.20.1) với quyền root
# =============================================================================

set -e

echo "=== [1/5] Cài đặt WireGuard ==="
opkg update
opkg install wireguard-tools luci-proto-wireguard kmod-wireguard

echo "=== [2/5] Tạo WireGuard keys ==="
WG_DIR="/etc/wireguard"
mkdir -p "$WG_DIR"

if [ ! -f "$WG_DIR/wg1_privatekey" ]; then
    wg genkey | tee "$WG_DIR/wg1_privatekey" | wg pubkey > "$WG_DIR/wg1_publickey"
    chmod 600 "$WG_DIR/wg1_privatekey"
    echo "Keys đã tạo."
    echo "PUBLIC KEY (gửi cho do2):"
    cat "$WG_DIR/wg1_publickey"
else
    echo "Keys đã tồn tại."
    echo "PUBLIC KEY:"
    cat "$WG_DIR/wg1_publickey"
fi

PRIVATE_KEY=$(cat "$WG_DIR/wg1_privatekey")

echo ""
echo "=== [3/5] Cấu hình WireGuard interface (wg1) ==="

# Xóa config cũ nếu có
uci delete network.wg1 2>/dev/null || true

# Tạo interface wg1
uci set network.wg1=interface
uci set network.wg1.proto='wireguard'
uci set network.wg1.private_key="$PRIVATE_KEY"
uci set network.wg1.listen_port='51821'
uci add_list network.wg1.addresses='10.20.0.2/24'

# Peer: do2 (VPS1)
# NOTE: Thay <DO2_WG1_PUBLIC_KEY> bằng public key thực từ do2
uci add network wireguard_wg1
uci set network.@wireguard_wg1[-1].description='do2-vps1'
uci set network.@wireguard_wg1[-1].public_key='<DO2_WG1_PUBLIC_KEY>'
uci set network.@wireguard_wg1[-1].endpoint_host='152.42.238.137'
uci set network.@wireguard_wg1[-1].endpoint_port='51821'
uci set network.@wireguard_wg1[-1].persistent_keepalive='25'
uci add_list network.@wireguard_wg1[-1].allowed_ips='10.20.0.0/24'
uci add_list network.@wireguard_wg1[-1].allowed_ips='10.10.0.0/24'
uci set network.@wireguard_wg1[-1].route_allowed_ips='1'

echo "=== [4/5] Cấu hình Firewall ==="

# Tạo firewall zone cho WireGuard
uci add firewall zone
uci set firewall.@zone[-1].name='wg'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='ACCEPT'
uci set firewall.@zone[-1].masq='1'
uci add_list firewall.@zone[-1].network='wg1'

# Forward: wg -> wan (traffic từ tunnel ra internet)
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='wg'
uci set firewall.@forwarding[-1].dest='wan'

# Forward: wg -> lan (nếu cần truy cập LAN fominet)
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='wg'
uci set firewall.@forwarding[-1].dest='lan'

echo "=== [5/5] Áp dụng cấu hình ==="
uci commit network
uci commit firewall

/etc/init.d/network restart
/etc/init.d/firewall restart

echo ""
echo "=== HOÀN TẤT ==="
echo "WireGuard wg1 đã cấu hình trên fominet."
echo ""
echo "PUBLIC KEY (copy gửi cho do2):"
cat "$WG_DIR/wg1_publickey"
echo ""
echo "Kiểm tra: wg show wg1"
