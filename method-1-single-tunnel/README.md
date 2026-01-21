# Method 1: Single WireGuard Tunnel + Port Forward

## Sơ đồ

```
┌─────────┐                    ┌─────────────────┐                    ┌─────────────────┐
│   PC    │   UDP 51820        │      VPS1       │     Port Forward   │      VPS2       │
│ Client  │ ─────────────────> │  (iptables)     │ ─────────────────> │  (WG Server)    │
│10.0.0.2 │                    │                 │                    │   10.0.0.1      │
└─────────┘                    └─────────────────┘                    └─────────────────┘
                                                                              │
                                                                              ▼ NAT
                                                                        Internet (IP X)
```

## Cách hoạt động

1. **PC** gửi WireGuard packets đến **VPS1:51820**
2. **VPS1** forward tất cả UDP traffic port 51820 đến **VPS2:51820** (DNAT)
3. **VPS2** nhận và xử lý WireGuard tunnel, sau đó NAT traffic ra Internet
4. Response đi ngược lại: Internet → VPS2 → VPS1 → PC

## Ưu điểm

- ✅ Đơn giản, ít cấu hình
- ✅ VPS1 không cần cài WireGuard
- ✅ Tốc độ nhanh (chỉ 1 lớp encryption)
- ✅ Dễ troubleshoot

## Nhược điểm

- ❌ Traffic giữa VPS1-VPS2 không được mã hóa (chỉ port forward)
- ❌ Nếu VPS1-VPS2 trên cùng network thì OK, khác network thì kém bảo mật

---

## Thứ tự triển khai

1. **VPS2** - Cài WireGuard Server + NAT
2. **VPS1** - Cấu hình Port Forward
3. **PC** - Cài WireGuard Client

---

## Bước 1: Cấu hình VPS2 (WireGuard Server)

### 1.1 Tạo keys trên VPS2
```bash
cd /etc/wireguard
wg genkey | tee vps2_privatekey | wg pubkey > vps2_publickey
cat vps2_privatekey  # Lưu lại
cat vps2_publickey   # Lưu lại
```

### 1.2 Copy file cấu hình
```bash
cp vps2/wg0.conf /etc/wireguard/wg0.conf
```

### 1.3 Chỉnh sửa config
Thay thế:
- `<VPS2_PRIVATE_KEY>` bằng private key vừa tạo
- `<PC_PUBLIC_KEY>` bằng public key của PC (tạo ở bước 3)

### 1.4 Chạy setup script
```bash
chmod +x vps2/setup.sh
./vps2/setup.sh
```

---

## Bước 2: Cấu hình VPS1 (Port Forward)

### 2.1 Chỉnh sửa script
Mở `vps1/setup.sh` và thay thế:
- `VPS2_PUBLIC_IP` bằng IP public của VPS2

### 2.2 Chạy setup script
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
- `<PC_PRIVATE_KEY>` - tự động được tạo khi add tunnel
- `<VPS2_PUBLIC_KEY>` bằng public key của VPS2
- `VPS1_PUBLIC_IP` bằng IP public của VPS1

### 3.4 Cập nhật VPS2
Quay lại VPS2, thêm public key của PC vào config:
```bash
nano /etc/wireguard/wg0.conf
# Thay <PC_PUBLIC_KEY> bằng public key của PC
wg-quick down wg0 && wg-quick up wg0
```

---

## Kiểm tra

### Trên PC
```cmd
ping 10.0.0.1
curl ifconfig.me
```
Kết quả `curl ifconfig.me` phải trả về IP của VPS2 (IP X)

### Trên VPS2
```bash
wg show
```

---

## Troubleshooting

### PC không kết nối được
1. Kiểm tra firewall trên VPS1 cho phép UDP 51820
2. Kiểm tra port forward đúng chưa: `iptables -t nat -L -n -v`
3. Kiểm tra WireGuard trên VPS2: `wg show`

### Traffic không đi qua VPS2
1. Kiểm tra NAT trên VPS2: `iptables -t nat -L -n -v`
2. Kiểm tra IP forwarding: `cat /proc/sys/net/ipv4/ip_forward` (phải = 1)
