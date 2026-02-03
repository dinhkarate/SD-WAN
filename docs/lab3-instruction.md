# LAB 3 - SD-WAN Split Routing (Reversed)

## Kiến trúc

```
PC1 (10.10.0.2) ──wg0:51820──► VPS1 (103.109.187.182)
                                    │
                          ┌─────────┴─────────┐
                          │                   │
                    Other IPs             China IPs
                          │                   │
                          ▼                   ▼
                    VPS1 eth0               wg1:51821
                  (103.109.187.182)           │
                                              ▼
                                        VPS2 (103.109.187.179)
                                              │
                                              ▼
                                          Internet
```

### Traffic Flow

| Destination           | Route                   | Exit IP         |
| --------------------- | ----------------------- | --------------- |
| China IPs (223.5.5.5) | PC1 → VPS1 → wg1 → VPS2 | 103.109.187.179 |
| Other IPs (8.8.8.8)   | PC1 → VPS1 → eth0       | 103.109.187.182 |

---

## Chuẩn bị

### SSH Config (~/.ssh/config)

```
Host vina7
    HostName 103.109.187.182
    User root

Host vina8
    HostName 103.109.187.179
    User root
```

---

## Deploy VPS2 (Exit Node)

```bash
# 1. Copy script lên VPS2
scp scripts/method-2/deploy-vps2.sh vina8:/tmp/

# 2. SSH vào VPS2 và chạy
ssh vina8
sudo bash /tmp/deploy-vps2.sh

# 3. Lưu lại VPS2 pubkey (hiển thị sau khi chạy script)
# Ví dụ: ABC123...
```

---

## Deploy VPS1 (Hub/Router)

```bash
# 1. Copy các file cần thiết lên VPS1
scp scripts/method-2/routing-setup.sh vina7:/tmp/
scp scripts/method-2/deploy-vps1.sh vina7:/tmp/
scp data/chinaip.txt vina7:/tmp/

# 2. SSH vào VPS1 và chạy (thay VPS2_PUBKEY bằng key thật)
ssh vina7
sudo bash /tmp/deploy-vps1.sh <VPS2_PUBKEY>

# 3. Lưu lại VPS1 wg0 pubkey (cho PC1)
# Ví dụ: t+4f9tArVGpO+SZREGdA/v1zSFpnanTEvZfiouIkIFg=
```

---

## Cấu hình PC1 (Client)

### Config sẵn (Copy-Paste)

```bash
# 1. Down WireGuard cũ nếu đang chạy
sudo wg-quick down wg0 2>/dev/null

# 2. Tạo config mới
sudo tee /etc/wireguard/wg0.conf << 'EOF'
[Interface]
Address = 10.10.0.2/24
PrivateKey = wFtCnu/LU+z196EchEeu2ZbEZPj+Boy+tpYdlEgm4EY=
DNS = 8.8.8.8

[Peer]
PublicKey = t+4f9tArVGpO+SZREGdA/v1zSFpnanTEvZfiouIkIFg=
Endpoint = 103.109.187.182:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

# 3. Kết nối
sudo wg-quick up wg0
```

### Keys Reference

| Key                | Value                                           |
| ------------------ | ----------------------------------------------- |
| PC1 PrivateKey     | `wFtCnu/LU+z196EchEeu2ZbEZPj+Boy+tpYdlEgm4EY=`  |
| PC1 PublicKey      | `ZXQ5NBO4gkp5rnTHUPDQW7zPr0R/A78N62pv4b5BSQg=`  |
| VPS1 wg0 PublicKey | `t+4f9tArVGpO+SZREGdA/v1zSFpananTEvZfiouIkIFg=` |
| VPS1 wg1 PublicKey | `Cr18W31rGw5r8rupi52dCmiFr4ncR16slTOCeT9fYTk=`  |
| VPS2 wg1 PublicKey | `yG1CgXZejfGU7lVQ8Fbaz4ZGzKx6Gx13H3+Oo+WpY2A=`  |

> **Note:** PC1 peer đã được thêm vào VPS1. Chỉ cần chạy config trên là kết nối được.

### Bước 2: Thêm PC1 peer vào VPS1

```bash
# Trên VPS1 (thay PC1_PUBKEY bằng key thật)
ssh vina7 "sudo wg set wg0 peer <PC1_PUBKEY> allowed-ips 10.10.0.2/32"

# Lưu vĩnh viễn
ssh vina7 "sudo wg-quick save wg0"
```

### Bước 3: Tạo config file trên PC1

```bash
sudo tee /etc/wireguard/wg0.conf << 'EOF'
[Interface]
Address = 10.10.0.2/24
PrivateKey = <PC1_PRIVATEKEY>
DNS = 8.8.8.8

[Peer]
PublicKey = t+4f9tArVGpO+SZREGdA/v1zSFpnanTEvZfiouIkIFg=
Endpoint = 103.109.187.182:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
```

**Thay thế:**

- `<PC1_PRIVATEKEY>`: Private key từ `/etc/wireguard/privatekey`
- PublicKey: Lấy từ VPS1 (`cat /etc/wireguard/wg0_publickey`)

### Bước 4: Kết nối

```bash
sudo wg-quick up wg0
```

---

## Kiểm tra

### Trên VPS1

```bash
# Xem status routing
sudo /etc/sdwan/routing-setup.sh status

# Xem WireGuard connections
sudo wg show
```

### Trên PC1

```bash
# Kiểm tra kết nối VPN
sudo wg show
ping 10.10.0.1

# Test Other IPs → Expect VPS1 (103.109.187.182)
curl -s ifconfig.me

# Test China IP → Expect VPS2 (103.109.187.179)
# Dùng traceroute để xem route
traceroute -n 223.5.5.5 | head -5
```

---

## Troubleshooting

### PC1 không kết nối được VPS1

1. **Kiểm tra port UDP 51820**

   ```bash
   nc -uzv 103.109.187.182 51820
   ```

2. **Kiểm tra public key khớp**

   ```bash
   # PC1 pubkey
   cat /etc/wireguard/publickey

   # VPS1 expected peer
   ssh vina7 "sudo wg show wg0"
   ```

3. **Update peer nếu key không khớp**
   ```bash
   ssh vina7 "sudo wg set wg0 peer <OLD_KEY> remove"
   ssh vina7 "sudo wg set wg0 peer <NEW_KEY> allowed-ips 10.10.0.2/32"
   ```

### VPS1 không forward traffic qua VPS2

1. **Kiểm tra wg1 tunnel**

   ```bash
   ssh vina7 "ping -c 2 10.20.0.2"
   ```

2. **Kiểm tra routing tables**

   ```bash
   ssh vina7 "ip route show table 100; ip route show table 200"
   ```

3. **Reload routing**
   ```bash
   ssh vina7 "sudo /etc/sdwan/routing-setup.sh down && sudo /etc/sdwan/routing-setup.sh up"
   ```

### SSH bị mất kết nối sau khi apply routing

- **Không sao!** SSH traffic đi thẳng vào eth0, không qua wg0
- Chỉ traffic từ PC1 (qua wg0) mới bị policy routing
- Nếu vẫn mất SSH, reboot VPS từ control panel

---

## Ngắt kết nối

### PC1

```bash
sudo wg-quick down wg0
```

### VPS1 - Tắt routing (giữ WireGuard)

```bash
sudo /etc/sdwan/routing-setup.sh down
```

### VPS1 - Tắt hoàn toàn

```bash
sudo wg-quick down wg0
sudo wg-quick down wg1
```

---

## Quick Deploy Commands (Copy-Paste)

### Deploy từ máy local

```bash
# VPS2 first
scp scripts/method-2/deploy-vps2.sh vina8:/tmp/ && \
ssh vina8 "sudo bash /tmp/deploy-vps2.sh"

# Copy VPS2 pubkey, then VPS1
scp scripts/method-2/routing-setup.sh scripts/method-2/deploy-vps1.sh data/chinaip.txt vina7:/tmp/ && \
ssh vina7 "sudo bash /tmp/deploy-vps1.sh <VPS2_PUBKEY>"
```

### Kết nối PC1

```bash
# Add PC1 peer to VPS1
ssh vina7 "sudo wg set wg0 peer $(cat /etc/wireguard/publickey) allowed-ips 10.10.0.2/32"

# Connect
sudo wg-quick up wg0

# Test
curl -s ifconfig.me && echo ""
```
