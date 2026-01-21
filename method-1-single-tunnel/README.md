# Method 1: Single WireGuard Tunnel

## Mô tả

Tất cả các thiết bị (PC, VPS1, VPS2) đều nằm trong cùng một WireGuard network (10.0.0.0/24).

```
┌─────────────┐      wg0        ┌─────────────────┐      wg0        ┌─────────────────┐
│     PC      │ ─────────────>  │      VPS1       │ <───────────── │      VPS2       │
│ (WG Client) │                 │  (WG Server)    │                 │  (WG Client)    │
│  10.0.0.2   │                 │   10.0.0.1      │                 │   10.0.0.3      │
└─────────────┘                 └─────────────────┘                 └─────────────────┘
      │                                 │                                   │
      │                                 │         forward traffic           │
      │                                 └──────────────────────────────────>│
      │                                                                     │
      └─────────────────────────────────────────────────────────────────────┤
                                                                            ▼
                                                                      Internet (IP X)
```

## Vai trò

| Thiết bị | Vai trò | IP WireGuard |
|----------|---------|--------------|
| VPS1 | WG Server (hub) | 10.0.0.1 |
| PC | WG Client | 10.0.0.2 |
| VPS2 | WG Client + NAT Gateway | 10.0.0.3 |

## Luồng traffic

1. **PC → VPS1**: PC kết nối đến VPS1 qua WireGuard
2. **VPS2 → VPS1**: VPS2 cũng kết nối đến VPS1 như một client
3. **VPS1 forward**: VPS1 nhận traffic từ PC và forward đến VPS2
4. **VPS2 NAT**: VPS2 nhận traffic và NAT ra Internet

## Thứ tự cài đặt

### 1. VPS1 (WireGuard Server)

```bash
# SSH vào VPS1
ssh root@103.109.187.182

# Copy file wg0.conf vào /etc/wireguard/
# (Hoặc sử dụng GitHub Actions)

# Chạy setup script
chmod +x setup.sh
./setup.sh

# Lưu lại Public Key để cấu hình cho PC và VPS2
```

### 2. VPS2 (WireGuard Client + NAT)

```bash
# SSH vào VPS2
ssh root@103.109.187.179

# Copy file wg0.conf vào /etc/wireguard/

# Cập nhật wg0.conf:
# - Thay <VPS1_PUBLIC_KEY> bằng public key của VPS1
# - VPS1_PUBLIC_IP đã được thay tự động từ config.env

# Chạy setup script
chmod +x setup.sh
./setup.sh

# Lưu lại Public Key để cấu hình cho VPS1
```

### 3. Cập nhật VPS1 với VPS2 Public Key

```bash
# SSH vào VPS1
ssh root@103.109.187.182

# Sửa /etc/wireguard/wg0.conf
# Thay <VPS2_PUBLIC_KEY> bằng public key của VPS2

# Restart WireGuard
wg-quick down wg0
wg-quick up wg0
```

### 4. PC (Windows)

1. Mở WireGuard for Windows
2. Click **Add Tunnel** → **Add empty tunnel...**
3. Copy nội dung từ `pc/wg0.conf`
4. Thay thế:
   - `<PC_PRIVATE_KEY>`: Private key đã tự động tạo
   - `<VPS1_PUBLIC_KEY>`: Public key của VPS1
   - `VPS1_PUBLIC_IP`: IP của VPS1 (103.109.187.182)
5. Click **Save** và **Activate**

### 5. Cập nhật VPS1 với PC Public Key

```bash
# SSH vào VPS1
ssh root@103.109.187.182

# Sửa /etc/wireguard/wg0.conf
# Thay <PC_PUBLIC_KEY> bằng public key của PC

# Restart WireGuard
wg-quick down wg0
wg-quick up wg0
```

## Kiểm tra kết nối

### Trên VPS1
```bash
wg show
# Phải thấy 2 peers: PC và VPS2
```

### Trên VPS2
```bash
wg show
# Phải thấy handshake với VPS1
ping 10.0.0.1  # Ping VPS1
ping 10.0.0.2  # Ping PC (nếu PC đang connected)
```

### Trên PC
```bash
# Kiểm tra IP public
curl ifconfig.me
# Kết quả phải là IP của VPS2 (103.109.187.179)

# Ping test
ping 10.0.0.1  # Ping VPS1
ping 10.0.0.3  # Ping VPS2
```

## Troubleshooting

### Không ping được giữa các peers
1. Kiểm tra firewall trên VPS1 đã mở UDP 51820
2. Kiểm tra IP forwarding đã bật: `sysctl net.ipv4.ip_forward`
3. Kiểm tra iptables rules: `iptables -L -n -v`

### VPS2 không kết nối được VPS1
1. Kiểm tra Endpoint trong wg0.conf của VPS2
2. Kiểm tra public key đã đúng chưa
3. Kiểm tra firewall trên VPS1

### PC không truy cập Internet qua VPN
1. Kiểm tra NAT trên VPS2: `iptables -t nat -L -n -v`
2. Kiểm tra AllowedIPs trong cấu hình
