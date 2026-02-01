# SD-WAN: Split Routing với 2 VPS

Cấu hình VPN split routing: PC1 kết nối VPS1, traffic China IPs ra Internet qua VPS1, traffic còn lại forward qua VPS2.

## Kiến trúc

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

## Traffic Flow

| Traffic từ PC1 đến | Route qua   | IP public       |
| ------------------ | ----------- | --------------- |
| China IPs          | VPS1 eth0   | 103.109.187.182 |
| Tất cả IP khác     | VPS1 → VPS2 | 103.109.187.179 |

## Cấu trúc thư mục

```
configs/method-2/
├── vps1/
│   ├── wg0.conf      # Server nhận PC1
│   └── wg1.conf      # Client kết nối tới VPS2
├── vps2/
│   └── wg1.conf      # Server nhận tunnel từ VPS1
└── clients/
    └── pc1.conf      # Config cho PC1

scripts/method-2/
├── deploy-vps1.sh    # Script deploy VPS1
├── deploy-vps2.sh    # Script deploy VPS2
└── routing-setup.sh  # Policy routing script (chạy trên VPS1)
```

## Yêu cầu

| Thiết bị | Yêu cầu                                         |
| -------- | ----------------------------------------------- |
| VPS1     | Debian 10+ / Ubuntu 20.04+, IP: 103.109.187.182 |
| VPS2     | Debian 10+ / Ubuntu 20.04+, IP: 103.109.187.179 |
| PC1      | WireGuard client                                |

---

## Hướng dẫn cài đặt

### Bước 1: Deploy VPS2 (vina8) - Exit Node

```bash
# SSH vào VPS2
ssh vina8

# Cài WireGuard
apt update && apt install -y wireguard

# Tạo key
wg genkey | tee /etc/wireguard/wg1_private | wg pubkey > /etc/wireguard/wg1_public

# Tạo config
cat > /etc/wireguard/wg1.conf << 'EOF'
[Interface]
Address = 10.20.0.2/24
PrivateKey = <VPS2_WG1_PRIVATE_KEY>

PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o eth0 -j MASQUERADE
PostUp = iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.20.0.0/24 -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.10.0.0/24 -o eth0 -j MASQUERADE

[Peer]
PublicKey = <VPS1_WG1_PUBLIC_KEY>
Endpoint = 103.109.187.182:51821
AllowedIPs = 10.20.0.1/32, 10.10.0.0/24
PersistentKeepalive = 25
EOF

# Thay private key
sed -i "s|<VPS2_WG1_PRIVATE_KEY>|$(cat /etc/wireguard/wg1_private)|" /etc/wireguard/wg1.conf

# Khởi động
wg-quick up wg1
systemctl enable wg-quick@wg1

# Mở firewall (nếu dùng ufw)
ufw allow 51821/udp
```

### Bước 2: Deploy VPS1 (vina7) - Hub/Router

```bash
# SSH vào VPS1
ssh vina7

# Cài WireGuard và ipset
apt update && apt install -y wireguard ipset

# Tạo keys
wg genkey | tee /etc/wireguard/wg0_private | wg pubkey > /etc/wireguard/wg0_public
wg genkey | tee /etc/wireguard/wg1_private | wg pubkey > /etc/wireguard/wg1_public

# Tạo thư mục scripts
mkdir -p /etc/sdwan/scripts/method-2

# Download China IPs list
curl -o /etc/sdwan/chinaip.txt https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt

# Copy routing script từ repo vào VPS1
# scp scripts/method-2/routing-setup.sh vina7:/etc/sdwan/scripts/method-2/
chmod +x /etc/sdwan/scripts/method-2/routing-setup.sh

# Tạo wg0.conf (nhận PC1)
cat > /etc/wireguard/wg0.conf << 'EOF'
[Interface]
Address = 10.10.0.1/24
ListenPort = 51820
PrivateKey = <VPS1_WG0_PRIVATE_KEY>

PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = /etc/sdwan/scripts/method-2/routing-setup.sh up
PostDown = /etc/sdwan/scripts/method-2/routing-setup.sh down
EOF

# Tạo wg1.conf (tunnel đến VPS2)
cat > /etc/wireguard/wg1.conf << 'EOF'
[Interface]
Address = 10.20.0.1/24
ListenPort = 51821
PrivateKey = <VPS1_WG1_PRIVATE_KEY>
Table = off

[Peer]
PublicKey = <VPS2_WG1_PUBLIC_KEY>
AllowedIPs = 10.20.0.2/32, 0.0.0.0/0
PersistentKeepalive = 25
EOF

# Thay private keys
sed -i "s|<VPS1_WG0_PRIVATE_KEY>|$(cat /etc/wireguard/wg0_private)|" /etc/wireguard/wg0.conf
sed -i "s|<VPS1_WG1_PRIVATE_KEY>|$(cat /etc/wireguard/wg1_private)|" /etc/wireguard/wg1.conf

# Khởi động
wg-quick up wg0
wg-quick up wg1
systemctl enable wg-quick@wg0 wg-quick@wg1

# Mở firewall
ufw allow 51820/udp
ufw allow 51821/udp
```

### Bước 3: Trao đổi Public Keys

```bash
# Trên VPS1, lấy wg1 public key
cat /etc/wireguard/wg1_public
# Output: Cr18W31rGw5r8rupi52dCmiFr4ncR16slTOCeT9fYTk=

# Trên VPS2, lấy wg1 public key
cat /etc/wireguard/wg1_public
# Output: yG1CgXZejfGU7lVQ8Fbaz4ZGzKx6Gx13H3+Oo+WpY2A=

# Thay vào config tương ứng:
# VPS1 wg1.conf: PublicKey = <VPS2_WG1_PUBLIC_KEY>
# VPS2 wg1.conf: PublicKey = <VPS1_WG1_PUBLIC_KEY>

# Restart WireGuard sau khi thay
wg-quick down wg1 && wg-quick up wg1
```

### Bước 4: Tạo config cho PC1

```bash
# Trên máy local, tạo key
wg genkey | tee pc1_private | wg pubkey > pc1_public

# Thêm PC1 vào VPS1
ssh vina7 "wg set wg0 peer $(cat pc1_public) allowed-ips 10.10.0.2/32"

# Persist peer vào config
ssh vina7 "echo '' >> /etc/wireguard/wg0.conf && \
  echo '[Peer]' >> /etc/wireguard/wg0.conf && \
  echo 'PublicKey = $(cat pc1_public)' >> /etc/wireguard/wg0.conf && \
  echo 'AllowedIPs = 10.10.0.2/32' >> /etc/wireguard/wg0.conf"

# Lấy VPS1 public key
VPS1_PUBKEY=$(ssh vina7 "cat /etc/wireguard/wg0_public")

# Tạo config file cho PC1
cat > pc1.conf << EOF
[Interface]
Address = 10.10.0.2/24
PrivateKey = $(cat pc1_private)
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = $VPS1_PUBKEY
Endpoint = 103.109.187.182:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

echo "Config saved to pc1.conf"
```

### Bước 5: Kết nối và Test

```bash
# Kết nối PC1
sudo cp pc1.conf /etc/wireguard/wg-sdwan.conf
sudo wg-quick up wg-sdwan

# Test China IP → phải thấy VPS1 (103.109.187.182)
traceroute 223.5.5.5
curl --connect-to ::223.5.5.5: ifconfig.me

# Test non-China IP → phải thấy VPS2 (103.109.187.179)
traceroute 8.8.8.8
curl ifconfig.me
# Expected: 103.109.187.179
```

---

## Quản lý China IPs

```bash
# Cập nhật danh sách China IPs
ssh vina7 "curl -o /etc/sdwan/chinaip.txt https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt"

# Reload routing (không cần restart WG)
ssh vina7 "/etc/sdwan/scripts/method-2/routing-setup.sh reload"

# Xem trạng thái
ssh vina7 "/etc/sdwan/scripts/method-2/routing-setup.sh status"
```

---

## Kiểm tra trạng thái

```bash
# Trên VPS1
wg show                    # Xem trạng thái cả 2 interfaces
ip route show table 100    # Routing table cho non-China (→ VPS2)
ip route show table 200    # Routing table cho China (→ VPS1 eth0)
ipset list china_ips | head -20   # Xem danh sách China IPs

# Trên VPS2
wg show wg1                # Xem tunnel status
iptables -t nat -L POSTROUTING   # Xem NAT rules

# Trên PC1
wg show                    # Xem connection status
curl ifconfig.me           # Xem IP public (expected: VPS2)
```

---

## Xử lý sự cố

| Vấn đề                         | Kiểm tra                                                         |
| ------------------------------ | ---------------------------------------------------------------- |
| PC1 không kết nối được         | `wg show wg0` trên VPS1, kiểm tra firewall port 51820            |
| Traffic không forward qua VPS2 | `wg show wg1` trên VPS1, `ip route show table 100`               |
| China IPs không hoạt động      | `ipset list china_ips`, `/etc/sdwan/.../routing-setup.sh status` |
| Không có Internet              | `iptables -t nat -L POSTROUTING` trên VPS2                       |
| Tunnel VPS1-VPS2 không kết nối | Ping test: `ssh vina7 "ping -c 2 10.20.0.2"`                     |

---

## Placeholder Summary

| Config   | Placeholder              | Mô tả                    |
| -------- | ------------------------ | ------------------------ |
| VPS1 wg0 | `<VPS1_WG0_PRIVATE_KEY>` | Private key của VPS1 wg0 |
| VPS1 wg0 | `<PC1_PUBLIC_KEY>`       | Public key của PC1       |
| VPS1 wg1 | `<VPS1_WG1_PRIVATE_KEY>` | Private key của VPS1 wg1 |
| VPS1 wg1 | `<VPS2_WG1_PUBLIC_KEY>`  | Public key của VPS2 wg1  |
| VPS2 wg1 | `<VPS2_WG1_PRIVATE_KEY>` | Private key của VPS2 wg1 |
| VPS2 wg1 | `<VPS1_WG1_PUBLIC_KEY>`  | Public key của VPS1 wg1  |
| PC1      | `<PC1_PRIVATE_KEY>`      | Private key của PC1      |
| PC1      | `<VPS1_WG0_PUBLIC_KEY>`  | Public key của VPS1 wg0  |

---

## Public Keys (đã deploy)

| Interface | Public Key                                     |
| --------- | ---------------------------------------------- |
| VPS1 wg0  | `t+4f9tArVGpO+SZREGdA/v1zSFpnanTEvZfiouIkIFg=` |
| VPS1 wg1  | `Cr18W31rGw5r8rupi52dCmiFr4ncR16slTOCeT9fYTk=` |
| VPS2 wg1  | `yG1CgXZejfGU7lVQ8Fbaz4ZGzKx6Gx13H3+Oo+WpY2A=` |
| PC1       | `2HYvgW2/uQiw1BKxIq4+7+WTJ3bt3ztmmmk9om0xgXk=` |

---

## License

MIT
