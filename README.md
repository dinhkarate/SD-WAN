# SD-WAN: Split Routing với Single Interface Chain (Method 1)

Cấu hình VPN split routing sử dụng **single WireGuard interface** trên mỗi node.

## Kiến trúc

```
                         ┌────────────────────┐
                         │ Internet (Special) │
                         └─────────▲──────────┘
                                   │ eth0 (VPS1 IP: 103.109.187.182)
                                   │
┌──────────┐   wg0    ┌────────────┴────────────┐   wg0    ┌──────────────┐
│          │─────────►│         VPS1            │◄────────►│     VPS2     │
│   PC1    │  :51820  │    103.109.187.182      │  :51820  │103.109.187.179│
│10.10.0.2 │          │       10.10.0.1         │          │  10.10.0.3   │
└──────────┘          └─────────────────────────┘          └───────┬──────┘
                                                                   │
                                                                   ▼
                                                          ┌───────────────┐
                                                          │Internet (ALL) │
                                                          │ IP: VPS2      │
                                                          └───────────────┘
```

## Traffic Flow

| Traffic từ PC1 đến         | Route qua   | IP public       |
| -------------------------- | ----------- | --------------- |
| Special IPs (8.8.8.8, ...) | VPS1 eth0   | 103.109.187.182 |
| Tất cả IP khác             | VPS1 → VPS2 | 103.109.187.179 |

## Cách hoạt động

1. **PC1** kết nối VPS1 qua WireGuard (wg0, port 51820)
2. **VPS1** nhận traffic từ PC1:
   - Nếu destination IP nằm trong **special-ips.txt** → mark packet → route qua eth0 (IP VPS1)
   - Nếu không match → forward qua wg0 tới VPS2
3. **VPS2** nhận traffic từ VPS1 → NAT ra Internet (IP VPS2)

## Routing Logic trên VPS1

```
┌─────────────────────────────────────────────────────────┐
│                    VPS1 Routing                         │
├─────────────────────────────────────────────────────────┤
│  1. ipset "special_ips" chứa danh sách IP đặc biệt      │
│  2. iptables mangle: mark packet nếu dst in special_ips │
│  3. ip rule:                                            │
│     - fwmark 100 → table 100 (eth0, gateway mặc định)   │
│     - from 10.10.0.2 → table 200 (wg0, via 10.10.0.3)   │
│  4. iptables forward: cho phép wg0↔wg0, wg0→eth0        │
│  5. iptables nat: MASQUERADE cho traffic ra eth0        │
└─────────────────────────────────────────────────────────┘
```

## Cấu trúc thư mục

```
configs/
├── pc1/wg0.conf      # PC1 client
├── vps1/wg0.conf     # VPS1: nhận PC1 + kết nối VPS2
└── vps2/wg0.conf     # VPS2: exit node

scripts/
└── wg0-up.sh         # Setup policy routing (up/down/status/reload)
```

## Hướng dẫn cài đặt

### Bước 1: Cài đặt VPS2 (Exit Node)

```bash
ssh vina8

apt update && apt install -y wireguard

cat > /etc/wireguard/wg0.conf << 'EOF'
[Interface]
Address = 10.10.0.3/24
ListenPort = 51820
PrivateKey = <VPS2_PRIVATE_KEY>

PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o eth0 -j MASQUERADE
PostUp = iptables -A FORWARD -i wg0 -o eth0 -j ACCEPT
PostUp = iptables -A FORWARD -i eth0 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s 10.10.0.0/24 -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -o eth0 -j ACCEPT
PostDown = iptables -D FORWARD -i eth0 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

[Peer]
PublicKey = <VPS1_PUBLIC_KEY>
AllowedIPs = 10.10.0.1/32, 10.10.0.2/32
EOF

wg-quick up wg0
systemctl enable wg-quick@wg0
ufw allow 51820/udp
```

### Bước 2: Cài đặt VPS1 (Gateway)

```bash
ssh vina7

apt update && apt install -y wireguard ipset

# Tạo thư mục scripts
mkdir -p /etc/sdwan/scripts

# Copy wg0-up.sh vào /etc/sdwan/scripts/ và chmod +x

# Tạo config
cat > /etc/wireguard/wg0.conf << 'EOF'
[Interface]
Address = 10.10.0.1/24
ListenPort = 51820
PrivateKey = <VPS1_PRIVATE_KEY>
Table = off

PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = /etc/sdwan/scripts/wg0-up.sh up
PostDown = /etc/sdwan/scripts/wg0-up.sh down

[Peer]
PublicKey = <PC1_PUBLIC_KEY>
AllowedIPs = 10.10.0.2/32

[Peer]
PublicKey = <VPS2_PUBLIC_KEY>
Endpoint = 103.109.187.179:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

# Tạo danh sách special IPs
cat > /etc/sdwan/special-ips.txt << 'EOF'
# IPs đi thẳng qua VPS1 (không qua VPS2)
8.8.8.8/32
8.8.4.4/32
1.1.1.1/32
EOF

wg-quick up wg0
systemctl enable wg-quick@wg0
ufw allow 51820/udp
```

### Bước 3: Cấu hình PC1

```ini
[Interface]
Address = 10.10.0.2/24
PrivateKey = <PC1_PRIVATE_KEY>
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = <VPS1_PUBLIC_KEY>
Endpoint = 103.109.187.182:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

## Quản lý Special IPs

```bash
# Thêm IP mới
echo "1.2.3.4/32" >> /etc/sdwan/special-ips.txt

# Reload (không cần restart WG)
/etc/sdwan/scripts/wg0-up.sh reload

# Xem trạng thái
/etc/sdwan/scripts/wg0-up.sh status
```

## Kiểm tra

```bash
# Trên VPS1 - xem trạng thái
wg show wg0
/etc/sdwan/scripts/wg0-up.sh status

# Trên PC1 - verify routing
curl ifconfig.me              # → Nên thấy 103.109.187.179 (VPS2)
traceroute 8.8.8.8            # → Nên thấy 103.109.187.182 (VPS1)
```

## Keys đang sử dụng

| Node | Public Key                                     |
| ---- | ---------------------------------------------- |
| VPS1 | `t+4f9tArVGpO+SZREGdA/v1zSFpnanTEvZfiouIkIFg=` |
| VPS2 | `GIsyc1E01M6moYkhmwfPPWIMFltCG7NcZIZ8b67J0RQ=` |
| PC1  | `vafYFdIcwLv0LUseYKDE3c0KHqG2VxhJzN1kKAUnsGQ=` |

## Xử lý sự cố

| Vấn đề                      | Kiểm tra                                          |
| --------------------------- | ------------------------------------------------- |
| PC1 không kết nối được      | `wg show` trên VPS1, kiểm tra handshake           |
| Traffic không ra VPS2       | `ip rule show`, kiểm tra table 200                |
| Special IPs không hoạt động | `ipset list special_ips`, `iptables -t mangle -L` |

## License

MIT
