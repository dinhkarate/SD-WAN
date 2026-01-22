# Method 2: Double WireGuard Tunnels

## ⚠️ Policy Routing (Table 51821)

Cấu hình này sử dụng **Table routing** để tránh mất kết nối SSH đến VPS1:

- **Table 51821**: Dành riêng cho traffic từ PC → đi qua wg1 → VPS2 → Internet
- **Table main**: Traffic của VPS1 (SSH, updates) → đi trực tiếp Internet

```
┌──────────────────────────────────────────────────────────────────┐
│                           VPS1                                    │
├──────────────────────────────────────────────────────────────────┤
│  Table MAIN (mặc định):                                          │
│  ├── default via x.x.x.1 dev eth0  ← SSH, traffic VPS1           │
│  └── 10.0.0.0/24 dev wg0                                         │
│                                                                   │
│  Table 51821 (riêng cho traffic từ PC):                          │
│  └── default via 10.0.1.1 dev wg1  ← đi qua VPS2 ra Internet     │
├──────────────────────────────────────────────────────────────────┤
│  IP Rule: from 10.0.0.0/24 lookup 51821                          │
│  → CHỈ traffic từ PC (10.0.0.x) mới dùng table 51821             │
└──────────────────────────────────────────────────────────────────┘
```

## Sơ đồ

```
┌─────────┐    WireGuard 1     ┌─────────────────┐    WireGuard 2     ┌─────────────────┐
│   PC    │ ─────────────────> │      VPS1       │ ─────────────────> │      VPS2       │
│ Client  │                    │  WG Server +    │                    │   WG Server     │
│10.0.0.2 │                    │  WG Client      │                    │   10.0.1.1      │
└─────────┘                    │ 10.0.0.1/10.0.1.2│                   └─────────────────┘
                               └─────────────────┘                            │
                                                                              ▼ NAT
                                                                        Internet (IP X)
```

## Sơ đồ IP chi tiết

| Thiết bị | Interface | IP | Vai trò |
|----------|-----------|-----|---------|
| PC | wg0 | 10.0.0.2/24 | WG Client |
| VPS1 | wg0 | 10.0.0.1/24 | WG Server (cho PC) |
| VPS1 | wg1 | 10.0.1.2/24 | WG Client (đến VPS2) |
| VPS2 | wg0 | 10.0.1.1/24 | WG Server + NAT |

## Cách hoạt động

1. **PC** kết nối WireGuard đến **VPS1:51820** (Tunnel 1)
2. **VPS1** nhận traffic, forward qua WireGuard đến **VPS2:51821** (Tunnel 2)
3. **VPS2** nhận traffic và NAT ra Internet
4. Traffic xuất ra với IP của VPS2 (IP X)

## Ưu điểm

- ✅ Mã hóa 2 lớp (PC↔VPS1 và VPS1↔VPS2)
- ✅ Bảo mật cao hơn
- ✅ VPS1 có thể thêm logic xử lý (firewall, logging, etc.)
- ✅ Dễ thay đổi VPS2 mà không ảnh hưởng PC

## Nhược điểm

- ❌ Phức tạp hơn
- ❌ Overhead cao hơn (2 lần mã hóa/giải mã)
- ❌ Latency cao hơn một chút

---

## Thứ tự triển khai

1. **VPS2** - Cài WireGuard Server + NAT
2. **VPS1** - Cài WireGuard Server (wg0) + Client (wg1)
3. **PC** - Cài WireGuard Client

---

## Bước 1: Cấu hình VPS2 (WireGuard Server + NAT)

### 1.1 Tạo keys trên VPS2
```bash
cd /etc/wireguard
wg genkey | tee vps2_privatekey | wg pubkey > vps2_publickey
cat vps2_privatekey  # Lưu lại
cat vps2_publickey   # Lưu lại - cần cho VPS1
```

### 1.2 Copy file cấu hình
```bash
cp vps2/wg0.conf /etc/wireguard/wg0.conf
```

### 1.3 Chỉnh sửa config
Thay thế:
- `<VPS2_PRIVATE_KEY>` bằng private key vừa tạo
- `<VPS1_WG1_PUBLIC_KEY>` bằng public key của wg1 trên VPS1 (tạo ở bước 2)

### 1.4 Chạy setup script
```bash
chmod +x vps2/setup.sh
./vps2/setup.sh
```

---

## Bước 2: Cấu hình VPS1 (WireGuard Server + Client)

### 2.1 Tạo keys trên VPS1
```bash
cd /etc/wireguard
# Key cho wg0 (server cho PC)
wg genkey | tee vps1_wg0_privatekey | wg pubkey > vps1_wg0_publickey
# Key cho wg1 (client đến VPS2)
wg genkey | tee vps1_wg1_privatekey | wg pubkey > vps1_wg1_publickey

cat vps1_wg0_publickey   # Lưu lại - cần cho PC
cat vps1_wg1_publickey   # Lưu lại - cần cho VPS2
```

### 2.2 Copy files cấu hình
```bash
cp vps1/wg0.conf /etc/wireguard/wg0.conf
cp vps1/wg1.conf /etc/wireguard/wg1.conf
```

### 2.3 Chỉnh sửa config
**wg0.conf:**
- `<VPS1_WG0_PRIVATE_KEY>` bằng vps1_wg0_privatekey
- `<PC_PUBLIC_KEY>` bằng public key của PC

**wg1.conf:**
- `<VPS1_WG1_PRIVATE_KEY>` bằng vps1_wg1_privatekey
- `<VPS2_PUBLIC_KEY>` bằng public key của VPS2
- `VPS2_PUBLIC_IP` bằng IP public của VPS2

### 2.4 Quay lại VPS2 cập nhật public key
```bash
# Trên VPS2
nano /etc/wireguard/wg0.conf
# Thay <VPS1_WG1_PUBLIC_KEY> bằng vps1_wg1_publickey
wg-quick down wg0 && wg-quick up wg0
```

### 2.5 Chạy setup script trên VPS1
```bash
chmod +x vps1/setup.sh
./vps1/setup.sh
```

---

## Bước 3: Cấu hình PC (Windows)

### 3.1 Cài WireGuard
Download từ: https://www.wireguard.com/install/

### 3.2 Tạo tunnel mới
1. Mở WireGuard
2. Click "Add Tunnel" → "Add empty tunnel..."
3. Lưu lại **Public key** hiển thị
4. Paste nội dung từ `pc/wg0.conf`

### 3.3 Chỉnh sửa config
Thay thế:
- `<PC_PRIVATE_KEY>` - tự động được tạo
- `<VPS1_WG0_PUBLIC_KEY>` bằng public key wg0 của VPS1
- `VPS1_PUBLIC_IP` bằng IP public của VPS1

### 3.4 Cập nhật VPS1
```bash
# Trên VPS1
nano /etc/wireguard/wg0.conf
# Thay <PC_PUBLIC_KEY> bằng public key của PC
wg-quick down wg0 && wg-quick up wg0
```

---

## Kiểm tra

### Trên PC
```cmd
ping 10.0.0.1
ping 10.0.1.1
curl ifconfig.me
```
Kết quả `curl ifconfig.me` phải trả về IP của VPS2 (IP X)

### Trên VPS1
```bash
wg show wg0
wg show wg1
ping 10.0.1.1
```

### Trên VPS2
```bash
wg show
```

---

## Troubleshooting

### PC không ping được VPS1
1. Kiểm tra WireGuard trên VPS1: `wg show wg0`
2. Kiểm tra firewall: `iptables -L -n`
3. Kiểm tra keys đúng chưa

### VPS1 không ping được VPS2
1. Kiểm tra WireGuard wg1: `wg show wg1`
2. Kiểm tra kết nối: `ping VPS2_PUBLIC_IP`
3. Kiểm tra firewall trên VPS2

### Traffic không đi qua VPS2
1. Kiểm tra routing trên VPS1: `ip route`
2. Kiểm tra NAT trên VPS2: `iptables -t nat -L -n -v`
3. Kiểm tra IP forwarding trên cả VPS1 và VPS2

### Kiểm tra Table Routing (VPS1)

```bash
# Xem routing table 51821 (wg1)
ip route show table 51821
# Phải có: default dev wg1 ...

# Xem ip rules
ip rule show
# Phải có: from 10.0.0.0/24 lookup 51821

# Nếu thiếu rule, thêm thủ công:
ip rule add from 10.0.0.0/24 lookup 51821 priority 100
```

### VPS1 mất SSH sau khi bật WireGuard
Điều này xảy ra nếu không dùng Table routing. Giải pháp:
1. Đảm bảo `Table = 51821` có trong [Interface] của wg1.conf
2. Đảm bảo có `ip rule add from 10.0.0.0/24 lookup 51821` trong PostUp của wg0.conf
