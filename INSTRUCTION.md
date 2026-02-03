# Hướng Dẫn SD-WAN: VPS1 (vina7) và VPS2 (vina8)

Tài liệu này hướng dẫn **setup** và **clear** cấu hình WireGuard SD-WAN trên:

- **VPS1 (vina7)**: 103.109.187.182 - Hub/Router
- **VPS2 (vina8)**: 103.109.187.179 - Exit Node

---

# PHẦN 1: HANDON SETUP

## Kiến Trúc

```
PC1 (10.10.0.2) ──wg0:51820──► VPS1 (103.109.187.182)
                                    │
                          ┌─────────┴─────────┐
                          │                   │
                    China IPs            Other IPs
                          │                   │
                          ▼                   ▼
                    VPS1 eth0           wg1:51821
                  (103.109.187.182)           │
                                              ▼
                                        VPS2 (103.109.187.179)
                                              │
                                              ▼
                                          Internet
```

## Keys Đã Định Sẵn

> ⚠️ **LƯU Ý BẢO MẬT**: Đây là keys test/development. Trong production, hãy generate keys mới!

### VPS7 (vina7) Keys:

| Interface | Type    | Key                                            |
| --------- | ------- | ---------------------------------------------- |
| wg0       | Private | `WDKVq4PXGMRP6ATXN3GR4q9uPgP2AEwR0nzm5ozV0E4=` |
| wg0       | Public  | `PABCmv2igz9IGPa7uUgFDmQ6OfVOEEDG2DSqAoCySmA=` |
| wg1       | Private | `oO/8LKJ5X3F8gqI3Qs0VbJy5LNRdutD/rCZc9M0lxHo=` |
| wg1       | Public  | `62KgOvm8+te7DHdHYvf7D22lF+NDyUQxaucN/Qduc2c=` |

### VPS8 (vina8) Keys:

| Interface | Type    | Key                                            |
| --------- | ------- | ---------------------------------------------- |
| wg1       | Private | `8N6cPMRz7GxQdFV9YPTB5kAlZ3Wm0HsJ4vOoLnE2WXk=` |
| wg1       | Public  | `aD+5ZpaU+Tf8oiWPfeSDSzsqVXPSHgIcMdm4MCecMl8=` |

### PC1 Keys:

| Type    | Key                                            |
| ------- | ---------------------------------------------- |
| Private | `mFT2P7Qx9rKzJW0cXsN5AhB6dE3iL8oGvY1uHkVwR4M=` |
| Public  | `Pv2II5K98M2Eu18N9Cx5oW0CuUI6U+qpqd8lW45san0=` |

---

## Quick Setup - Copy & Paste Blocks

> **Thứ tự**: Setup VPS8 (vina8) trước, rồi đến VPS7 (vina7).

### Block 1: VPS8 (vina8) - Setup TRƯỚC

SSH vào vina8 và paste:

```bash
# === SETUP VPS8 (vina8) - Exit Node ===
set -e

# Keys đã định sẵn
VPS8_WG1_PRIVATE="8N6cPMRz7GxQdFV9YPTB5kAlZ3Wm0HsJ4vOoLnE2WXk="
VPS7_WG1_PUBLIC="62KgOvm8+te7DHdHYvf7D22lF+NDyUQxaucN/Qduc2c="

# Install WireGuard
apt-get update -qq && apt-get install -y wireguard -qq

# Save keys
mkdir -p /etc/wireguard
echo "$VPS8_WG1_PRIVATE" > /etc/wireguard/wg1_privatekey
echo "aD+5ZpaU+Tf8oiWPfeSDSzsqVXPSHgIcMdm4MCecMl8=" > /etc/wireguard/wg1_publickey
chmod 600 /etc/wireguard/wg1_privatekey

# Detect network interface
ETH=$(ip route | grep default | awk '{print $5}' | head -1)
[ -z "$ETH" ] && ETH="eth0"

# Create wg1.conf
cat > /etc/wireguard/wg1.conf << EOF
# VPS2 - Exit Node
[Interface]
Address = 10.20.0.2/24
PrivateKey = $VPS8_WG1_PRIVATE

PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o $ETH -j MASQUERADE
PostUp = iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o $ETH -j MASQUERADE
PostUp = iptables -A FORWARD -i wg1 -o $ETH -j ACCEPT
PostUp = iptables -A FORWARD -i $ETH -o wg1 -m state --state RELATED,ESTABLISHED -j ACCEPT

PostDown = iptables -t nat -D POSTROUTING -s 10.20.0.0/24 -o $ETH -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.10.0.0/24 -o $ETH -j MASQUERADE
PostDown = iptables -D FORWARD -i wg1 -o $ETH -j ACCEPT
PostDown = iptables -D FORWARD -i $ETH -o wg1 -m state --state RELATED,ESTABLISHED -j ACCEPT

[Peer]
PublicKey = $VPS7_WG1_PUBLIC
Endpoint = 103.109.187.182:51821
AllowedIPs = 10.20.0.0/24, 10.10.0.0/24
PersistentKeepalive = 25
EOF

# Start WireGuard
wg-quick down wg1 2>/dev/null || true
wg-quick up wg1
systemctl enable wg-quick@wg1 2>/dev/null || true

echo ""
echo "=== VPS8 SETUP DONE ==="
wg show wg1
```

### Block 2: VPS7 (vina7) - Setup SAU

SSH vào vina7 và paste:

```bash
# === SETUP VPS7 (vina7) - Hub/Router ===
set -e

# Keys đã định sẵn
VPS7_WG0_PRIVATE="WDKVq4PXGMRP6ATXN3GR4q9uPgP2AEwR0nzm5ozV0E4="
VPS7_WG0_PUBLIC="PABCmv2igz9IGPa7uUgFDmQ6OfVOEEDG2DSqAoCySmA="
VPS7_WG1_PRIVATE="oO/8LKJ5X3F8gqI3Qs0VbJy5LNRdutD/rCZc9M0lxHo="
VPS7_WG1_PUBLIC="62KgOvm8+te7DHdHYvf7D22lF+NDyUQxaucN/Qduc2c="
VPS8_WG1_PUBLIC="aD+5ZpaU+Tf8oiWPfeSDSzsqVXPSHgIcMdm4MCecMl8="
PC1_PUBLIC="Pv2II5K98M2Eu18N9Cx5oW0CuUI6U+qpqd8lW45san0="

# Install dependencies
apt-get update -qq && apt-get install -y wireguard ipset -qq

# Save keys
mkdir -p /etc/wireguard
echo "$VPS7_WG0_PRIVATE" > /etc/wireguard/wg0_privatekey
echo "$VPS7_WG0_PUBLIC" > /etc/wireguard/wg0_publickey
echo "$VPS7_WG1_PRIVATE" > /etc/wireguard/wg1_privatekey
echo "$VPS7_WG1_PUBLIC" > /etc/wireguard/wg1_publickey
chmod 600 /etc/wireguard/wg0_privatekey /etc/wireguard/wg1_privatekey

# Create SD-WAN directory
mkdir -p /etc/sdwan/scripts/method-2

# Download China IPs
curl -sL -o /etc/sdwan/chinaip.txt https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt

# Create routing-setup.sh
cat > /etc/sdwan/scripts/method-2/routing-setup.sh << 'ROUTING_EOF'
#!/bin/bash
# Policy-based routing for SD-WAN

CHINA_IPS="/etc/sdwan/chinaip.txt"
VPS2_TUNNEL_IP="10.20.0.2"
VPS1_GATEWAY="103.109.187.1"
ETH_IFACE="eth0"

setup_routing() {
    # Add routing tables if not exist
    grep -q "100 vps2exit" /etc/iproute2/rt_tables || echo "100 vps2exit" >> /etc/iproute2/rt_tables
    grep -q "200 vps1exit" /etc/iproute2/rt_tables || echo "200 vps1exit" >> /etc/iproute2/rt_tables

    # Create ipset for China IPs
    ipset create china_ips hash:net -exist
    ipset flush china_ips

    if [ -f "$CHINA_IPS" ]; then
        while IFS= read -r ip; do
            [ -n "$ip" ] && ipset add china_ips "$ip" 2>/dev/null || true
        done < "$CHINA_IPS"
    fi

    # Default: forward to VPS2 (table 100)
    ip route add default via $VPS2_TUNNEL_IP dev wg1 table 100 2>/dev/null || true

    # China: use VPS1 eth0 (table 200)
    ip route add default via $VPS1_GATEWAY dev $ETH_IFACE table 200 2>/dev/null || true

    # IP rules
    ip rule add fwmark 100 lookup 100 priority 100 2>/dev/null || true
    ip rule add fwmark 200 lookup 200 priority 200 2>/dev/null || true

    # iptables mangle: mark traffic from wg0
    # Default mark 100 (VPS2), China IPs mark 200 (VPS1)
    iptables -t mangle -A PREROUTING -i wg0 -m set --match-set china_ips dst -j MARK --set-mark 200
    iptables -t mangle -A PREROUTING -i wg0 -m mark ! --mark 200 -j MARK --set-mark 100

    # NAT for China traffic (mark 200)
    iptables -t nat -A POSTROUTING -m mark --mark 200 -o $ETH_IFACE -j MASQUERADE
}

teardown_routing() {
    iptables -t mangle -D PREROUTING -i wg0 -m set --match-set china_ips dst -j MARK --set-mark 200 2>/dev/null || true
    iptables -t mangle -D PREROUTING -i wg0 -m mark ! --mark 200 -j MARK --set-mark 100 2>/dev/null || true
    iptables -t nat -D POSTROUTING -m mark --mark 200 -o $ETH_IFACE -j MASQUERADE 2>/dev/null || true
    ip rule del fwmark 100 lookup 100 2>/dev/null || true
    ip rule del fwmark 200 lookup 200 2>/dev/null || true
    ip route flush table 100 2>/dev/null || true
    ip route flush table 200 2>/dev/null || true
    ipset destroy china_ips 2>/dev/null || true
}

case "$1" in
    up) setup_routing ;;
    down) teardown_routing ;;
    reload) teardown_routing; setup_routing ;;
    status)
        echo "=== IP Rules ===" && ip rule show | grep -E 'fwmark|100|200'
        echo "=== Table 100 ===" && ip route show table 100
        echo "=== Table 200 ===" && ip route show table 200
        echo "=== China IPs count ===" && ipset list china_ips | grep "Number of entries"
        ;;
    *) echo "Usage: $0 {up|down|reload|status}"; exit 1 ;;
esac
ROUTING_EOF
chmod +x /etc/sdwan/scripts/method-2/routing-setup.sh

# Create wg0.conf (for PC1)
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.10.0.1/24
ListenPort = 51820
PrivateKey = $VPS7_WG0_PRIVATE

PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = /etc/sdwan/scripts/method-2/routing-setup.sh up
PostDown = /etc/sdwan/scripts/method-2/routing-setup.sh down

[Peer]
PublicKey = $PC1_PUBLIC
AllowedIPs = 10.10.0.2/32
EOF

# Create wg1.conf (for VPS2)
cat > /etc/wireguard/wg1.conf << EOF
[Interface]
Address = 10.20.0.1/24
ListenPort = 51821
PrivateKey = $VPS7_WG1_PRIVATE
Table = off

PostUp = sysctl -w net.ipv4.ip_forward=1

[Peer]
PublicKey = $VPS8_WG1_PUBLIC
AllowedIPs = 10.20.0.2/32, 0.0.0.0/0
EOF

# Open firewall
ufw allow 51820/udp 2>/dev/null || true
ufw allow 51821/udp 2>/dev/null || true

# Start WireGuard
wg-quick down wg0 2>/dev/null || true
wg-quick down wg1 2>/dev/null || true
wg-quick up wg1
wg-quick up wg0
systemctl enable wg-quick@wg0 wg-quick@wg1 2>/dev/null || true

echo ""
echo "=== VPS7 SETUP DONE ==="
wg show
echo ""
echo "Test tunnel: ping -c 2 10.20.0.2"
```

### Block 3: Tạo PC1 Config (Trên local machine)

PC1 config với keys đã định sẵn:

```bash
# === PC1 CONFIG ===
# Keys đã định sẵn
PC1_PRIVATE="mFT2P7Qx9rKzJW0cXsN5AhB6dE3iL8oGvY1uHkVwR4M="
VPS7_WG0_PUBLIC="PABCmv2igz9IGPa7uUgFDmQ6OfVOEEDG2DSqAoCySmA="

# Tạo config file
cat > pc1.conf << EOF
[Interface]
Address = 10.10.0.2/24
PrivateKey = $PC1_PRIVATE
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = $VPS7_WG0_PUBLIC
Endpoint = 103.109.187.182:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

echo "Config saved to pc1.conf"
cat pc1.conf
```

### Block 4: Test kết nối

```bash
# Kết nối PC1
sudo cp pc1.conf /etc/wireguard/wg-sdwan.conf
sudo wg-quick up wg-sdwan

# Test China IP (phải ra VPS1: 103.109.187.182)
echo "Testing China IP..."
curl --connect-timeout 5 -s ip.sb

# Test non-China IP (phải ra VPS2: 103.109.187.179)
echo "Testing non-China IP..."
curl --connect-timeout 5 -s ifconfig.me

echo "Expected: China→VPS1(182), Other→VPS2(179)"
```

---

## Xác Nhận Setup Thành Công

| Kiểm tra         | Command                                                           | Expected                  |
| ---------------- | ----------------------------------------------------------------- | ------------------------- |
| VPS7↔VPS8 tunnel | `ssh vina7 "ping -c 2 10.20.0.2"`                                 | ping OK                   |
| WireGuard VPS7   | `ssh vina7 "wg show"`                                             | 2 interfaces              |
| WireGuard VPS8   | `ssh vina8 "wg show"`                                             | 1 interface, handshake OK |
| Routing tables   | `ssh vina7 "/etc/sdwan/scripts/method-2/routing-setup.sh status"` | Tables có routes          |
| PC1 IP (China)   | Truy cập baidu.com                                                | IP = 103.109.187.182      |
| PC1 IP (Other)   | curl ifconfig.me                                                  | IP = 103.109.187.179      |

---

# PHẦN 2: CLEAR SETUP

## Tổng Quan

Phần này hướng dẫn xóa toàn bộ cấu hình WireGuard SD-WAN đã được deploy trên:

- **VPS1 (vina7)**: 103.109.187.182 - Hub/Router
- **VPS2 (vina8)**: 103.109.187.179 - Exit Node

## Thứ Tự Thực Hiện

> **Quan trọng**: Nên clear VPS2 trước, rồi đến VPS1 để tránh lỗi kết nối.

---

## Bước 1: Clear VPS2 (vina8) - Exit Node

### 1.1. SSH vào VPS2

```bash
ssh vina8
# hoặc
ssh root@103.109.187.179
```

### 1.2. Dừng WireGuard

```bash
# Dừng interface wg1
wg-quick down wg1

# Tắt auto-start khi boot
systemctl disable wg-quick@wg1
```

### 1.3. Backup và xóa cấu hình

```bash
# Backup configs (optional)
BACKUP_DIR="/etc/wireguard.backup.$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/wireguard/*.conf "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/wireguard/*key* "$BACKUP_DIR/" 2>/dev/null || true
echo "Backed up to: $BACKUP_DIR"

# Xóa config files
rm -f /etc/wireguard/wg1.conf
```

### 1.4. Xóa iptables rules (nếu còn sót)

```bash
# Detect network interface
ETH_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
[ -z "$ETH_IFACE" ] && ETH_IFACE="eth0"

# Xóa NAT rules
iptables -t nat -D POSTROUTING -s 10.20.0.0/24 -o $ETH_IFACE -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -s 10.10.0.0/24 -o $ETH_IFACE -j MASQUERADE 2>/dev/null || true

# Xóa FORWARD rules
iptables -D FORWARD -i wg1 -o $ETH_IFACE -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i $ETH_IFACE -o wg1 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
```

### 1.5. Xác nhận VPS2 đã clean

```bash
# Kiểm tra không còn WireGuard interface
wg show

# Kiểm tra không còn NAT rules
iptables -t nat -L POSTROUTING -n -v

# Output mong đợi: Không có entries liên quan đến 10.20.0.0/24 hoặc 10.10.0.0/24
```

---

## Bước 2: Clear VPS1 (vina7) - Hub/Router

### 2.1. SSH vào VPS1

```bash
ssh vina7
# hoặc
ssh root@103.109.187.182
```

### 2.2. Dừng WireGuard

```bash
# Dừng cả 2 interfaces
wg-quick down wg0
wg-quick down wg1

# Tắt auto-start
systemctl disable wg-quick@wg0
systemctl disable wg-quick@wg1
```

### 2.3. Xóa routing rules và ipset

```bash
# Xóa iptables mangle rules
iptables -t mangle -D PREROUTING -i wg0 -j MARK --set-mark 100 2>/dev/null || true
iptables -t mangle -D PREROUTING -i wg0 -m set --match-set china_ips dst -j MARK --set-mark 200 2>/dev/null || true

# Xóa NAT rules
iptables -t nat -D POSTROUTING -m mark --mark 200 -o eth0 -j MASQUERADE 2>/dev/null || true

# Xóa ip rules
ip rule del fwmark 100 lookup 100 2>/dev/null || true
ip rule del fwmark 200 lookup 200 2>/dev/null || true

# Flush routing tables
ip route flush table 100 2>/dev/null || true
ip route flush table 200 2>/dev/null || true

# Xóa ipset
ipset destroy china_ips 2>/dev/null || true
```

### 2.4. Backup và xóa cấu hình

```bash
# Backup configs
BACKUP_DIR="/etc/wireguard.backup.$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/wireguard/*.conf "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/wireguard/*key* "$BACKUP_DIR/" 2>/dev/null || true
echo "Backed up to: $BACKUP_DIR"

# Xóa config files
rm -f /etc/wireguard/wg0.conf
rm -f /etc/wireguard/wg1.conf
```

### 2.5. Xóa thư mục SD-WAN scripts (optional)

```bash
# Xóa scripts và data
rm -rf /etc/sdwan
```

### 2.6. Xác nhận VPS1 đã clean

```bash
# Kiểm tra không còn WireGuard interface
wg show

# Kiểm tra không còn ip rules
ip rule show | grep -E 'fwmark|100|200'

# Kiểm tra routing tables rỗng
ip route show table 100
ip route show table 200

# Kiểm tra ipset đã xóa
ipset list china_ips

# Kiểm tra iptables mangle
iptables -t mangle -L PREROUTING -n -v

# Output mong đợi: Tất cả đều rỗng/không có entries
```

---

## Quick Clear - Copy & Paste Blocks

> **Thứ tự**: SSH vào vina8 paste block 1, xong SSH vào vina7 paste block 2.

### Block 1: VPS8 (vina8) - Chạy TRƯỚC

```bash
# === CLEAR VPS8 (vina8) - Exit Node ===
wg-quick down wg1 2>/dev/null
systemctl disable wg-quick@wg1 2>/dev/null
ETH=$(ip route | grep default | awk '{print $5}' | head -1)
iptables -t nat -D POSTROUTING -s 10.20.0.0/24 -o $ETH -j MASQUERADE 2>/dev/null
iptables -t nat -D POSTROUTING -s 10.10.0.0/24 -o $ETH -j MASQUERADE 2>/dev/null
iptables -D FORWARD -i wg1 -o $ETH -j ACCEPT 2>/dev/null
iptables -D FORWARD -i $ETH -o wg1 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
rm -f /etc/wireguard/wg1.conf
echo "=== VPS8 CLEARED ===" && wg show
```

### Block 2: VPS7 (vina7) - Chạy SAU

```bash
# === CLEAR VPS7 (vina7) - Hub/Router ===
wg-quick down wg0 2>/dev/null
wg-quick down wg1 2>/dev/null
systemctl disable wg-quick@wg0 wg-quick@wg1 2>/dev/null
iptables -t mangle -D PREROUTING -i wg0 -j MARK --set-mark 100 2>/dev/null
iptables -t mangle -D PREROUTING -i wg0 -m set --match-set china_ips dst -j MARK --set-mark 200 2>/dev/null
iptables -t nat -D POSTROUTING -m mark --mark 200 -o eth0 -j MASQUERADE 2>/dev/null
ip rule del fwmark 100 lookup 100 2>/dev/null
ip rule del fwmark 200 lookup 200 2>/dev/null
ip route flush table 100 2>/dev/null
ip route flush table 200 2>/dev/null
ipset destroy china_ips 2>/dev/null
rm -f /etc/wireguard/wg0.conf /etc/wireguard/wg1.conf
rm -rf /etc/sdwan
echo "=== VPS7 CLEARED ===" && wg show && ip rule show | grep -E 'fwmark|100|200' || echo "No fwmark rules"
```

---

## Script Tự Động (One-liner)

### Clear VPS2 nhanh:

```bash
ssh vina8 'wg-quick down wg1 2>/dev/null; systemctl disable wg-quick@wg1 2>/dev/null; rm -f /etc/wireguard/wg1.conf; echo "VPS2 cleared"'
```

### Clear VPS1 nhanh:

```bash
ssh vina7 'wg-quick down wg0 wg1 2>/dev/null; systemctl disable wg-quick@wg0 wg-quick@wg1 2>/dev/null; /etc/sdwan/scripts/method-2/routing-setup.sh down 2>/dev/null; rm -f /etc/wireguard/wg0.conf /etc/wireguard/wg1.conf; rm -rf /etc/sdwan; echo "VPS1 cleared"'
```

### Clear cả 2 VPS từ local:

```bash
# Clear VPS2 trước
ssh vina8 'wg-quick down wg1 2>/dev/null; systemctl disable wg-quick@wg1 2>/dev/null; rm -f /etc/wireguard/wg1.conf' && \
# Sau đó clear VPS1
ssh vina7 'wg-quick down wg0 wg1 2>/dev/null; systemctl disable wg-quick@wg0 wg-quick@wg1 2>/dev/null; /etc/sdwan/scripts/method-2/routing-setup.sh down 2>/dev/null; rm -f /etc/wireguard/wg0.conf /etc/wireguard/wg1.conf; rm -rf /etc/sdwan' && \
echo "Both VPS cleared successfully!"
```

---

## Xác Nhận Sau Khi Clear

### Checklist VPS2:

| Item              | Command                             | Expected            |
| ----------------- | ----------------------------------- | ------------------- |
| WireGuard stopped | `wg show`                           | No output           |
| Service disabled  | `systemctl is-enabled wg-quick@wg1` | disabled/not found  |
| Config removed    | `ls /etc/wireguard/wg1.conf`        | No such file        |
| NAT rules cleared | `iptables -t nat -L POSTROUTING -n` | No 10.x.x.x entries |

### Checklist VPS1:

| Item               | Command                               | Expected             |
| ------------------ | ------------------------------------- | -------------------- |
| WireGuard stopped  | `wg show`                             | No output            |
| wg0 disabled       | `systemctl is-enabled wg-quick@wg0`   | disabled/not found   |
| wg1 disabled       | `systemctl is-enabled wg-quick@wg1`   | disabled/not found   |
| Configs removed    | `ls /etc/wireguard/*.conf`            | No such file         |
| IP rules cleared   | `ip rule show \| grep fwmark`         | No output            |
| Table 100 empty    | `ip route show table 100`             | No output            |
| Table 200 empty    | `ip route show table 200`             | No output            |
| ipset destroyed    | `ipset list china_ips`                | not exist            |
| mangle cleared     | `iptables -t mangle -L PREROUTING -n` | No wg0/china entries |
| SD-WAN dir removed | `ls /etc/sdwan`                       | No such directory    |

---

## Lưu Ý

1. **Keys vẫn còn**: Script chỉ xóa config files, không xóa private/public keys trong `/etc/wireguard/*key*`. Nếu muốn xóa hoàn toàn:

   ```bash
   rm -f /etc/wireguard/*key*
   ```

2. **Firewall ports**: UFW rules cho ports 51820, 51821 vẫn còn. Nếu muốn xóa:

   ```bash
   ufw delete allow 51820/udp
   ufw delete allow 51821/udp
   ```

3. **rt_tables entries**: Entries trong `/etc/iproute2/rt_tables` (100 vps2exit, 200 vps1exit) vẫn còn. Đây là harmless, nhưng nếu muốn xóa:

   ```bash
   sed -i '/vps2exit/d; /vps1exit/d' /etc/iproute2/rt_tables
   ```

4. **Backup location**: Tất cả backups được lưu tại `/etc/wireguard.backup.<timestamp>/`

---

## Rollback (Nếu Cần Deploy Lại)

```bash
# Từ local machine
cd /home/daniel/Documents/Project/SD-WAN

# Deploy VPS2 trước
scp scripts/method-2/deploy-vps2.sh vina8:/tmp/
ssh vina8 'bash /tmp/deploy-vps2.sh'

# Deploy VPS1 sau
scp scripts/method-2/deploy-vps1.sh scripts/method-2/routing-setup.sh chinaip.txt vina7:/tmp/
ssh vina7 'mv /tmp/routing-setup.sh /tmp/chinaip.txt /tmp/ 2>/dev/null; bash /tmp/deploy-vps1.sh'
```
