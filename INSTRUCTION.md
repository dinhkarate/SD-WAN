# Hướng Dẫn SD-WAN Method 1: VPS1 (vina7) và VPS2 (vina8)

Tài liệu này hướng dẫn **setup** và **clear** cấu hình WireGuard SD-WAN Method 1 (Single Interface Chain) trên:

- **VPS1 (vina7)**: 103.109.187.182 - Gateway/Router (10.10.0.1)
- **VPS2 (vina8)**: 103.109.187.179 - Exit Node (10.10.0.3)
- **PC1**: Client (10.10.0.2)

---

# PHẦN 1: HANDON SETUP

## Kiến Trúc Method 1

```
┌──────────┐   wg0    ┌─────────────────────────┐   wg0    ┌──────────────┐
│          │─────────►│         VPS1            │◄────────►│     VPS2     │
│   PC1    │  :51820  │    103.109.187.182      │  :51820  │103.109.187.179│
│10.10.0.2 │          │       10.10.0.1         │          │  10.10.0.3   │
└──────────┘          └────────────┬────────────┘          └───────┬──────┘
                                   │                               │
                          Special IPs                         All Other
                                   │                               │
                                   ▼                               ▼
                          ┌───────────────┐               ┌───────────────┐
                          │Internet (VPS1)│               │Internet (VPS2)│
                          │103.109.187.182│               │103.109.187.179│
                          └───────────────┘               └───────────────┘
```

**Khác với Method 2**: Method 1 dùng **single wg0 interface** cho cả PC1 và VPS2 trên VPS1.

## Traffic Flow

| Traffic từ PC1 đến         | Route qua   | IP public       |
| -------------------------- | ----------- | --------------- |
| Special IPs (8.8.8.8, ...) | VPS1 eth0   | 103.109.187.182 |
| Tất cả IP khác             | VPS1 → VPS2 | 103.109.187.179 |

## Keys Đã Định Sẵn

> ⚠️ **LƯU Ý BẢO MẬT**: Đây là keys test/development. Trong production, hãy generate keys mới!

### VPS7 (vina7) Keys:

| Interface | Type    | Key                                            |
| --------- | ------- | ---------------------------------------------- |
| wg0       | Private | `eFJ1dlBYR01SUDY0SGNIY29PdkF3a0huRGVmZXc9PQ==` |
| wg0       | Public  | `t+4f9tArVGpO+SZREGdA/v1zSFpnanTEvZfiouIkIFg=` |

### VPS8 (vina8) Keys:

| Interface | Type    | Key                                            |
| --------- | ------- | ---------------------------------------------- |
| wg0       | Private | `R0lzeWMxRTAxTTZtb1lraG13ZlBQV0lNRmx0Q0c3TmM=` |
| wg0       | Public  | `GIsyc1E01M6moYkhmwfPPWIMFltCG7NcZIZ8b67J0RQ=` |

### PC1 Keys:

| Type    | Key                                            |
| ------- | ---------------------------------------------- |
| Private | `dmFmWUZkSWN3THYwTFVzZVlLREUzYzBLSHFHMlZ4aEo=` |
| Public  | `vafYFdIcwLv0LUseYKDE3c0KHqG2VxhJzN1kKAUnsGQ=` |

---

## Quick Setup - Copy & Paste Blocks

> **Thứ tự**: Setup VPS8 (vina8) trước, rồi đến VPS7 (vina7).

### Block 1: VPS8 (vina8) - Setup TRƯỚC

SSH vào vina8 và paste:

```bash
# === SETUP VPS8 (vina8) - Exit Node Method 1 ===
set -e

# Keys đã định sẵn
VPS8_WG0_PRIVATE="R0lzeWMxRTAxTTZtb1lraG13ZlBQV0lNRmx0Q0c3TmM="
VPS7_WG0_PUBLIC="t+4f9tArVGpO+SZREGdA/v1zSFpnanTEvZfiouIkIFg="

# Install WireGuard
apt-get update -qq && apt-get install -y wireguard -qq

# Detect network interface
ETH=$(ip route | grep default | awk '{print $5}' | head -1)
[ -z "$ETH" ] && ETH="eth0"

# Create wg0.conf
cat > /etc/wireguard/wg0.conf << EOF
# VPS2 (103.109.187.179) - Exit Node Method 1
[Interface]
Address = 10.10.0.3/24
ListenPort = 51820
PrivateKey = $VPS8_WG0_PRIVATE

PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o $ETH -j MASQUERADE
PostUp = iptables -A FORWARD -i wg0 -o $ETH -j ACCEPT
PostUp = iptables -A FORWARD -i $ETH -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

PostDown = iptables -t nat -D POSTROUTING -s 10.10.0.0/24 -o $ETH -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -o $ETH -j ACCEPT
PostDown = iptables -D FORWARD -i $ETH -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

[Peer]
PublicKey = $VPS7_WG0_PUBLIC
AllowedIPs = 10.10.0.1/32, 10.10.0.2/32
EOF

# Open firewall
ufw allow 51820/udp 2>/dev/null || true

# Start WireGuard
wg-quick down wg0 2>/dev/null || true
wg-quick up wg0
systemctl enable wg-quick@wg0 2>/dev/null || true

echo ""
echo "=== VPS8 SETUP DONE ==="
wg show wg0
```

### Block 2: VPS7 (vina7) - Setup SAU

SSH vào vina7 và paste:

```bash
# === SETUP VPS7 (vina7) - Gateway Method 1 ===
set -e

# Keys đã định sẵn
VPS7_WG0_PRIVATE="eFJ1dlBYR01SUDY0SGNIY29PdkF3a0huRGVmZXc9PQ=="
VPS7_WG0_PUBLIC="t+4f9tArVGpO+SZREGdA/v1zSFpnanTEvZfiouIkIFg="
VPS8_WG0_PUBLIC="GIsyc1E01M6moYkhmwfPPWIMFltCG7NcZIZ8b67J0RQ="
PC1_PUBLIC="vafYFdIcwLv0LUseYKDE3c0KHqG2VxhJzN1kKAUnsGQ="

# Install dependencies
apt-get update -qq && apt-get install -y wireguard ipset -qq

# Create SD-WAN directory
mkdir -p /etc/sdwan/scripts

# Create special-ips.txt
cat > /etc/sdwan/special-ips.txt << 'EOF'
# IPs đi thẳng qua VPS1 (không qua VPS2)
8.8.8.8/32
8.8.4.4/32
1.1.1.1/32
1.0.0.1/32
EOF

# Create wg0-up.sh routing script
cat > /etc/sdwan/scripts/wg0-up.sh << 'SCRIPT_EOF'
#!/bin/bash
# VPS1 Routing Script - Method 1 (Single Interface Chain)

set -e

IPSET_NAME="special_ips"
MARK_DIRECT=100
TABLE_DIRECT=100
TABLE_VPN=200
WAN_IF="eth0"
PC1_IP="10.10.0.2"
VPS2_IP="10.10.0.3"
SPECIAL_IPS_FILE="/etc/sdwan/special-ips.txt"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

up() {
    log "Setting up routing..."

    GATEWAY=$(ip route | grep "default via" | grep "$WAN_IF" | awk '{print $3}' | head -1)
    log "Default gateway: $GATEWAY"

    # Create ipset for special IPs
    ipset create "$IPSET_NAME" hash:net 2>/dev/null || ipset flush "$IPSET_NAME"
    if [[ -f "$SPECIAL_IPS_FILE" ]]; then
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            ipset add "$IPSET_NAME" "$line" 2>/dev/null || true
        done < "$SPECIAL_IPS_FILE"
        log "Loaded special IPs"
    fi

    # Routing tables
    ip route replace default via "$GATEWAY" dev "$WAN_IF" table $TABLE_DIRECT
    ip route replace default via "$VPS2_IP" dev wg0 table $TABLE_VPN

    # IP rules
    ip rule add fwmark $MARK_DIRECT table $TABLE_DIRECT priority 100 2>/dev/null || true
    ip rule add from $PC1_IP table $TABLE_VPN priority 150 2>/dev/null || true

    # Mangle: Mark special IP packets
    iptables -t mangle -A PREROUTING -s $PC1_IP -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark $MARK_DIRECT

    # NAT for special IPs going out eth0
    iptables -t nat -A POSTROUTING -s $PC1_IP -o $WAN_IF -j MASQUERADE

    # Forward rules
    iptables -A FORWARD -i wg0 -o wg0 -j ACCEPT
    iptables -A FORWARD -s $PC1_IP -o $WAN_IF -j ACCEPT
    iptables -A FORWARD -i $WAN_IF -d $PC1_IP -m state --state RELATED,ESTABLISHED -j ACCEPT

    log "Routing setup complete"
}

down() {
    log "Cleaning up..."

    iptables -t mangle -D PREROUTING -s $PC1_IP -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark $MARK_DIRECT 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s $PC1_IP -o $WAN_IF -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i wg0 -o wg0 -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -s $PC1_IP -o $WAN_IF -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i $WAN_IF -d $PC1_IP -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

    ip rule del fwmark $MARK_DIRECT table $TABLE_DIRECT 2>/dev/null || true
    ip rule del from $PC1_IP table $TABLE_VPN 2>/dev/null || true

    ip route flush table $TABLE_DIRECT 2>/dev/null || true
    ip route flush table $TABLE_VPN 2>/dev/null || true

    ipset destroy "$IPSET_NAME" 2>/dev/null || true

    log "Cleanup complete"
}

status() {
    echo "=== IPSet ==="
    ipset list "$IPSET_NAME" 2>/dev/null | head -10 || echo "Not found"
    echo ""
    echo "=== Routing Tables ==="
    echo "Table $TABLE_DIRECT (special→eth0):"
    ip route show table $TABLE_DIRECT 2>/dev/null || echo "Empty"
    echo "Table $TABLE_VPN (default→VPS2):"
    ip route show table $TABLE_VPN 2>/dev/null || echo "Empty"
    echo ""
    echo "=== IP Rules ==="
    ip rule show | grep -E "$TABLE_DIRECT|$TABLE_VPN|fwmark" || echo "No rules"
}

reload() {
    log "Reloading special IPs..."
    ipset flush "$IPSET_NAME"
    if [[ -f "$SPECIAL_IPS_FILE" ]]; then
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            ipset add "$IPSET_NAME" "$line" 2>/dev/null || true
        done < "$SPECIAL_IPS_FILE"
    fi
    log "Reloaded"
}

case "$1" in
    up) up ;;
    down) down ;;
    status) status ;;
    reload) reload ;;
    *) echo "Usage: $0 {up|down|status|reload}" ;;
esac
SCRIPT_EOF
chmod +x /etc/sdwan/scripts/wg0-up.sh

# Create wg0-down.sh
ln -sf /etc/sdwan/scripts/wg0-up.sh /etc/sdwan/scripts/wg0-down.sh

# Create wg0.conf
cat > /etc/wireguard/wg0.conf << EOF
# VPS1 (103.109.187.182) - Gateway Method 1
[Interface]
Address = 10.10.0.1/24
ListenPort = 51820
PrivateKey = $VPS7_WG0_PRIVATE
Table = off

PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = /etc/sdwan/scripts/wg0-up.sh up
PostDown = /etc/sdwan/scripts/wg0-up.sh down

# PC1 - Client
[Peer]
PublicKey = $PC1_PUBLIC
AllowedIPs = 10.10.0.2/32

# VPS2 - Exit node
[Peer]
PublicKey = $VPS8_WG0_PUBLIC
Endpoint = 103.109.187.179:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

# Open firewall
ufw allow 51820/udp 2>/dev/null || true

# Start WireGuard
wg-quick down wg0 2>/dev/null || true
wg-quick up wg0
systemctl enable wg-quick@wg0 2>/dev/null || true

echo ""
echo "=== VPS7 SETUP DONE ==="
wg show wg0
echo ""
echo "Test: ping -c 2 10.10.0.3"
echo "Status: /etc/sdwan/scripts/wg0-up.sh status"
```

### Block 3: Tạo PC1 Config (Trên local machine)

```bash
# === PC1 CONFIG ===
PC1_PRIVATE="dmFmWUZkSWN3THYwTFVzZVlLREUzYzBLSHFHMlZ4aEo="
VPS7_WG0_PUBLIC="t+4f9tArVGpO+SZREGdA/v1zSFpnanTEvZfiouIkIFg="

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

# Test Special IP (phải ra VPS1: 103.109.187.182)
echo "Testing Special IP (8.8.8.8)..."
traceroute -n 8.8.8.8 | head -5

# Test non-Special IP (phải ra VPS2: 103.109.187.179)
echo "Testing normal IP..."
curl --connect-timeout 5 -s ifconfig.me

echo ""
echo "Expected:"
echo "  - Special IPs (8.8.8.8, 1.1.1.1) → VPS1 (103.109.187.182)"
echo "  - All other IPs → VPS2 (103.109.187.179)"
```

---

## Quản lý Special IPs

```bash
# Thêm IP mới
echo "1.2.3.4/32" >> /etc/sdwan/special-ips.txt

# Reload (không cần restart WireGuard)
/etc/sdwan/scripts/wg0-up.sh reload

# Xem trạng thái
/etc/sdwan/scripts/wg0-up.sh status
```

---

## Xác Nhận Setup Thành Công

| Kiểm tra         | Command                                           | Expected                  |
| ---------------- | ------------------------------------------------- | ------------------------- |
| VPS7↔VPS8 tunnel | `ssh vina7 "ping -c 2 10.10.0.3"`                 | ping OK                   |
| WireGuard VPS7   | `ssh vina7 "wg show"`                             | 1 interface, 2 peers      |
| WireGuard VPS8   | `ssh vina8 "wg show"`                             | 1 interface, handshake OK |
| Routing status   | `ssh vina7 "/etc/sdwan/scripts/wg0-up.sh status"` | Tables có routes          |
| PC1 IP (Special) | `traceroute 8.8.8.8`                              | Hop qua 103.109.187.182   |
| PC1 IP (Other)   | `curl ifconfig.me`                                | IP = 103.109.187.179      |

---

# PHẦN 2: CLEAR SETUP

## Quick Clear - Copy & Paste Blocks

> **Thứ tự**: Clear VPS8 (vina8) trước, rồi đến VPS7 (vina7).

### Block 1: VPS8 (vina8) - Clear TRƯỚC

```bash
# === CLEAR VPS8 (vina8) - Exit Node Method 1 ===
wg-quick down wg0 2>/dev/null
systemctl disable wg-quick@wg0 2>/dev/null
ETH=$(ip route | grep default | awk '{print $5}' | head -1)
iptables -t nat -D POSTROUTING -s 10.10.0.0/24 -o $ETH -j MASQUERADE 2>/dev/null
iptables -D FORWARD -i wg0 -o $ETH -j ACCEPT 2>/dev/null
iptables -D FORWARD -i $ETH -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
rm -f /etc/wireguard/wg0.conf
echo "=== VPS8 CLEARED ===" && wg show
```

### Block 2: VPS7 (vina7) - Clear SAU

```bash
# === CLEAR VPS7 (vina7) - Gateway Method 1 ===
wg-quick down wg0 2>/dev/null
systemctl disable wg-quick@wg0 2>/dev/null

# Run cleanup script
/etc/sdwan/scripts/wg0-up.sh down 2>/dev/null

# Manual cleanup (in case script failed)
iptables -t mangle -D PREROUTING -s 10.10.0.2 -m set --match-set special_ips dst -j MARK --set-mark 100 2>/dev/null
iptables -t nat -D POSTROUTING -s 10.10.0.2 -o eth0 -j MASQUERADE 2>/dev/null
iptables -D FORWARD -i wg0 -o wg0 -j ACCEPT 2>/dev/null
iptables -D FORWARD -s 10.10.0.2 -o eth0 -j ACCEPT 2>/dev/null
iptables -D FORWARD -i eth0 -d 10.10.0.2 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null

ip rule del fwmark 100 table 100 2>/dev/null
ip rule del from 10.10.0.2 table 200 2>/dev/null
ip route flush table 100 2>/dev/null
ip route flush table 200 2>/dev/null
ipset destroy special_ips 2>/dev/null

# Remove files
rm -f /etc/wireguard/wg0.conf
rm -rf /etc/sdwan

echo "=== VPS7 CLEARED ===" && wg show && ip rule show | grep -E 'fwmark|100|200' || echo "No fwmark rules"
```

---

## One-liner Clear từ Local

### Clear cả 2 VPS từ local:

```bash
# Clear VPS8 trước, rồi VPS7
ssh vina8 'wg-quick down wg0 2>/dev/null; systemctl disable wg-quick@wg0 2>/dev/null; rm -f /etc/wireguard/wg0.conf' && \
ssh vina7 'wg-quick down wg0 2>/dev/null; systemctl disable wg-quick@wg0 2>/dev/null; /etc/sdwan/scripts/wg0-up.sh down 2>/dev/null; rm -f /etc/wireguard/wg0.conf; rm -rf /etc/sdwan' && \
echo "Both VPS cleared successfully!"
```

---

## Checklist Sau Khi Clear

### VPS8:

| Item              | Command                             | Expected        |
| ----------------- | ----------------------------------- | --------------- |
| WireGuard stopped | `wg show`                           | No output       |
| Service disabled  | `systemctl is-enabled wg-quick@wg0` | disabled        |
| Config removed    | `ls /etc/wireguard/wg0.conf`        | No such file    |
| NAT rules cleared | `iptables -t nat -L POSTROUTING -n` | No 10.10.0.0/24 |

### VPS7:

| Item              | Command                             | Expected     |
| ----------------- | ----------------------------------- | ------------ |
| WireGuard stopped | `wg show`                           | No output    |
| Service disabled  | `systemctl is-enabled wg-quick@wg0` | disabled     |
| Config removed    | `ls /etc/wireguard/wg0.conf`        | No such file |
| IP rules cleared  | `ip rule show \| grep fwmark`       | No output    |
| Table 100 empty   | `ip route show table 100`           | No output    |
| Table 200 empty   | `ip route show table 200`           | No output    |
| ipset destroyed   | `ipset list special_ips`            | not exist    |
| SD-WAN removed    | `ls /etc/sdwan`                     | No such dir  |

---

## So Sánh Method 1 vs Method 2

| Aspect               | Method 1 (Single Interface) | Method 2 (Dual Interface)              |
| -------------------- | --------------------------- | -------------------------------------- |
| Interfaces trên VPS1 | 1 (wg0)                     | 2 (wg0 cho PC1, wg1 cho VPS2)          |
| Port sử dụng         | 51820 only                  | 51820 + 51821                          |
| Routing logic        | ipset + fwmark + ip rule    | ipset + fwmark + ip rule               |
| Độ phức tạp          | Đơn giản hơn                | Phức tạp hơn                           |
| IP Space             | Shared (10.10.0.0/24)       | Separate (10.10.0.0/24 + 10.20.0.0/24) |

---

## License

MIT
