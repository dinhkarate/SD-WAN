# SD-WAN: Dual WireGuard Servers on Single VPS

Cấu hình 2 WireGuard servers độc lập trên cùng 1 VPS, hỗ trợ split routing để định tuyến một số IP đặc biệt đi thẳng ra Internet (bypass VPN).

## Kiến trúc

```
                    ┌─────────────────┐
                    │  Internet (ALL) │
                    └────────▲────────┘
                             │ eth0
┌──────────┐    wg0   ┌──────┴───────┐
│   PC1    │─────────►│    WG-A      │ VPS1 (103.109.187.182)
└──────────┘  :51820  │  10.10.0.1   │
                      └──────────────┘

┌──────────┐    wg1   ┌──────────────┐
│ Client2  │─────────►│    WG-B      │ VPS1 (103.109.187.182)
└──────────┘  :51821  │  10.20.0.1   │
                      └──────┬───────┘
                             │
                      (Split routing)
```

## Tính năng

- **2 WG servers độc lập** trên cùng VPS (khác port)
- **Subnet riêng** cho mỗi server (10.10.0.0/24 và 10.20.0.0/24)
- **Split routing** - chỉ định IP nào đi thẳng, IP nào qua VPN
- **Zero-downtime reload** - cập nhật danh sách IP không cần restart

## Cấu trúc thư mục

```
.
├── README.md
├── configs/method-2/
│   ├── vps1/
│   │   ├── wg0.conf          # WG-A server (port 51820)
│   │   └── wg1.conf          # WG-B server (port 51821)
│   └── clients/
│       ├── client-a.conf     # PC1 config
│       └── client-b.conf     # Client2 config
└── scripts/method-2/
    └── routing-setup.sh      # Policy routing script
```

## Yêu cầu

| Thiết bị | Yêu cầu                                                                          |
| -------- | -------------------------------------------------------------------------------- |
| VPS      | Debian 10+ / Ubuntu 20.04+, root access, IP public tĩnh                          |
| Client   | WireGuard client ([Windows](https://www.wireguard.com/install/) / Linux / macOS) |

## Hướng dẫn cài đặt

### Bước 1: Tạo WireGuard keys

```bash
# Trên VPS - cho wg0
wg genkey | tee /etc/wireguard/wg0_privatekey | wg pubkey > /etc/wireguard/wg0_publickey

# Trên VPS - cho wg1
wg genkey | tee /etc/wireguard/wg1_privatekey | wg pubkey > /etc/wireguard/wg1_publickey

# Trên PC1
wg genkey | tee pc1_privatekey | wg pubkey > pc1_publickey

# Trên Client2
wg genkey | tee client2_privatekey | wg pubkey > client2_publickey
```

### Bước 2: Cài đặt trên VPS

```bash
# Cài WireGuard
apt update && apt install -y wireguard ipset

# Copy configs
scp configs/method-2/vps1/*.conf root@VPS_IP:/etc/wireguard/

# Copy scripts
ssh root@VPS_IP "mkdir -p /etc/sdwan/scripts/method-2"
scp scripts/method-2/*.sh root@VPS_IP:/etc/sdwan/scripts/method-2/
ssh root@VPS_IP "chmod +x /etc/sdwan/scripts/method-2/*.sh"
```

### Bước 3: Thay thế placeholders

Sửa file `/etc/wireguard/wg0.conf` và `/etc/wireguard/wg1.conf` trên VPS:

| Placeholder              | Thay bằng                      |
| ------------------------ | ------------------------------ |
| `<VPS1_WG0_PRIVATE_KEY>` | Nội dung file `wg0_privatekey` |
| `<VPS1_WG1_PRIVATE_KEY>` | Nội dung file `wg1_privatekey` |
| `<PC1_PUBLIC_KEY>`       | Public key của PC1             |
| `<CLIENT2_PUBLIC_KEY>`   | Public key của Client2         |

Sửa file client config:

| Placeholder             | Thay bằng                     |
| ----------------------- | ----------------------------- |
| `<PC1_PRIVATE_KEY>`     | Private key của PC1           |
| `<VPS1_WG0_PUBLIC_KEY>` | Nội dung file `wg0_publickey` |

### Bước 4: Khởi động WireGuard

```bash
# Trên VPS
wg-quick up wg0
wg-quick up wg1

# Enable tự động khởi động
systemctl enable wg-quick@wg0 wg-quick@wg1

# Mở firewall
ufw allow 51820/udp comment 'WG-A'
ufw allow 51821/udp comment 'WG-B'
```

### Bước 5: Cấu hình Split Routing (tuỳ chọn)

Tạo file danh sách IP đi thẳng (bypass VPN):

```bash
cat > /etc/sdwan/special-ips.txt << 'EOF'
# IPs đi thẳng ra Internet (không qua VPN)
8.8.8.8/32
1.1.1.1/32
# Thêm IP khác ở đây
EOF

# Reload (không cần restart WG)
/etc/sdwan/scripts/method-2/routing-setup.sh reload
```

### Bước 6: Kết nối từ Client

Import file `client-a.conf` (hoặc `client-b.conf`) vào WireGuard app và kết nối.

## Kiểm tra

```bash
# Trên VPS - xem trạng thái WG
wg show

# Xem cả 2 interfaces
ip addr show wg0 wg1

# Xem routing rules
ip rule show
ip route show table 100

# Xem danh sách special IPs
ipset list special_ips | head -20
```

```bash
# Trên Client - test routing
traceroute 8.8.8.8   # Nếu trong special_ips → đi thẳng qua eth0
traceroute 1.2.3.4   # Đi qua VPN tunnel
```

## Xử lý sự cố

| Vấn đề                        | Giải pháp                                                        |
| ----------------------------- | ---------------------------------------------------------------- |
| Client không kết nối được     | Kiểm tra firewall: `ufw status`, đảm bảo port 51820/51821 UDP mở |
| Không có Internet qua VPN     | Kiểm tra NAT: `iptables -t nat -L POSTROUTING`                   |
| Split routing không hoạt động | Kiểm tra ipset: `ipset list special_ips`                         |

## Lưu ý bảo mật

- **Không commit private keys** lên git
- Sử dụng firewall chỉ cho phép traffic cần thiết
- Thường xuyên rotate keys

## License

MIT
