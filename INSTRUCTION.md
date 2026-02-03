# Hướng Dẫn Clear Setup VPS1 (vina7) và VPS2 (vina8)

## Tổng Quan

Tài liệu này hướng dẫn xóa toàn bộ cấu hình WireGuard SD-WAN đã được deploy trên:

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
