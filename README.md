# SD-WAN: Split Routing với 2 VPS

Cấu hình VPN split routing: PC1 kết nối VPS1, traffic special IPs ra Internet qua VPS1, traffic còn lại forward qua VPS2.

## Kiến trúc

```
                         ┌────────────────────┐
                         │ Internet (Special) │
                         └─────────▲──────────┘
                                   │ eth0 (VPS1 IP)
                                   │
┌──────────┐   wg0    ┌────────────┴────────────┐   wg1    ┌──────────────┐
│          │─────────►│         VPS1            │─────────►│     VPS2     │
│   PC1    │  :51820  │    103.109.187.182      │  :51820  │103.109.187.179│
│10.10.0.2 │          │ wg0: 10.10.0.1 (server) │          │ wg0: 10.20.0.1│
└──────────┘          │ wg1: 10.20.0.2 (client) │          └───────┬───────┘
                      └─────────────────────────┘                  │
                                                                   ▼
                                                          ┌───────────────┐
                                                          │Internet (ALL) │
                                                          └───────────────┘
```

## Traffic Flow

| Traffic từ PC1 đến         | Route qua   | IP public       |
| -------------------------- | ----------- | --------------- |
| Special IPs (configurable) | VPS1 eth0   | 103.109.187.182 |
| Tất cả IP khác             | VPS1 → VPS2 | 103.109.187.179 |

## Cấu trúc thư mục

```
configs/method-2/
├── vps1/
│   ├── wg0.conf      # Server nhận PC1
│   └── wg1.conf      # Client kết nối tới VPS2
├── vps2/
│   └── wg0.conf      # Server nhận tunnel từ VPS1
└── clients/
    └── pc1.conf      # Config cho PC1

scripts/method-2/
└── routing-setup.sh  # Policy routing script (chạy trên VPS1)
```

## Yêu cầu

| Thiết bị | Yêu cầu                                         |
| -------- | ----------------------------------------------- |
| VPS1     | Debian 10+ / Ubuntu 20.04+, IP: 103.109.187.182 |
| VPS2     | Debian 10+ / Ubuntu 20.04+, IP: 103.109.187.179 |
| PC1      | WireGuard client                                |

## Hướng dẫn cài đặt

### Bước 1: Tạo WireGuard keys

```bash
# Trên VPS1
wg genkey | tee /etc/wireguard/wg0_private | wg pubkey > /etc/wireguard/wg0_public
wg genkey | tee /etc/wireguard/wg1_private | wg pubkey > /etc/wireguard/wg1_public

# Trên VPS2
wg genkey | tee /etc/wireguard/wg0_private | wg pubkey > /etc/wireguard/wg0_public

# Trên PC1
wg genkey | tee pc1_private | wg pubkey > pc1_public
```

### Bước 2: Cài đặt VPS2 (làm trước)

```bash
# SSH vào VPS2
ssh vina8

# Cài WireGuard
apt update && apt install -y wireguard

# Copy config
# Thay <VPS2_WG0_PRIVATE_KEY> bằng nội dung /etc/wireguard/wg0_private
# Thay <VPS1_WG1_PUBLIC_KEY> bằng public key của VPS1 wg1
cat > /etc/wireguard/wg0.conf << 'EOF'
[Interface]
Address = 10.20.0.1/24
ListenPort = 51820
PrivateKey = <VPS2_WG0_PRIVATE_KEY>

PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.20.0.0/24 -o eth0 -j MASQUERADE

[Peer]
PublicKey = <VPS1_WG1_PUBLIC_KEY>
AllowedIPs = 10.20.0.2/32, 10.10.0.0/24
EOF

# Khởi động
wg-quick up wg0
systemctl enable wg-quick@wg0

# Mở firewall
ufw allow 51820/udp
```

### Bước 3: Cài đặt VPS1

```bash
# SSH vào VPS1
ssh vina7

# Cài WireGuard và ipset
apt update && apt install -y wireguard ipset

# Copy configs từ repo
# (thay placeholders bằng keys thực)

# Copy routing script
mkdir -p /etc/sdwan/scripts/method-2
# Copy scripts/method-2/routing-setup.sh vào /etc/sdwan/scripts/method-2/
chmod +x /etc/sdwan/scripts/method-2/routing-setup.sh

# Tạo file special IPs
mkdir -p /etc/sdwan
cat > /etc/sdwan/special-ips.txt << 'EOF'
# IPs sẽ đi thẳng qua VPS1 (không qua VPS2)
# Ví dụ: Google DNS
8.8.8.8/32
8.8.4.4/32
# Thêm IP khác ở đây
EOF

# Khởi động WireGuard
wg-quick up wg0
wg-quick up wg1

systemctl enable wg-quick@wg0 wg-quick@wg1

# Mở firewall
ufw allow 51820/udp
```

### Bước 4: Cấu hình PC1

Import file `configs/method-2/clients/pc1.conf` vào WireGuard app.

Thay placeholders:

- `<PC1_PRIVATE_KEY>`: Private key của PC1
- `<VPS1_WG0_PUBLIC_KEY>`: Public key của VPS1 wg0

## Quản lý Special IPs

```bash
# Thêm IP mới
echo "1.2.3.4/32" >> /etc/sdwan/special-ips.txt

# Reload (không cần restart WG)
/etc/sdwan/scripts/method-2/routing-setup.sh reload

# Xem trạng thái
/etc/sdwan/scripts/method-2/routing-setup.sh status
```

## Kiểm tra

```bash
# Trên VPS1
wg show           # Xem trạng thái cả 2 interfaces
ip route show table 100   # Xem routing table cho special IPs
ipset list special_ips    # Xem danh sách special IPs

# Trên PC1
# Test IP đi qua VPS1 (special)
curl ifconfig.me   # Nếu không trong special list → VPS2 IP
curl --interface wg0 https://api.ipify.org

# Traceroute để verify
traceroute 8.8.8.8  # Nếu trong special list → qua VPS1
traceroute 1.2.3.4  # Không trong list → qua VPS2
```

## Xử lý sự cố

| Vấn đề                         | Kiểm tra                                       |
| ------------------------------ | ---------------------------------------------- |
| PC1 không kết nối được         | `wg show` trên VPS1, kiểm tra firewall         |
| Traffic không forward qua VPS2 | `wg show wg1` trên VPS1, kiểm tra tunnel       |
| Special IPs không hoạt động    | `ipset list special_ips`, `ip rule show`       |
| Không có Internet              | Kiểm tra NAT: `iptables -t nat -L POSTROUTING` |

## Placeholder Summary

| Config   | Placeholder              | Mô tả                    |
| -------- | ------------------------ | ------------------------ |
| VPS1 wg0 | `<VPS1_WG0_PRIVATE_KEY>` | Private key của VPS1 wg0 |
| VPS1 wg0 | `<PC1_PUBLIC_KEY>`       | Public key của PC1       |
| VPS1 wg1 | `<VPS1_WG1_PRIVATE_KEY>` | Private key của VPS1 wg1 |
| VPS1 wg1 | `<VPS2_WG0_PUBLIC_KEY>`  | Public key của VPS2 wg0  |
| VPS2 wg0 | `<VPS2_WG0_PRIVATE_KEY>` | Private key của VPS2 wg0 |
| VPS2 wg0 | `<VPS1_WG1_PUBLIC_KEY>`  | Public key của VPS1 wg1  |
| PC1      | `<PC1_PRIVATE_KEY>`      | Private key của PC1      |
| PC1      | `<VPS1_WG0_PUBLIC_KEY>`  | Public key của VPS1 wg0  |

## License

MIT
