# SD-WAN Split Routing với WireGuard

## Kiến trúc mới (Split Routing)

```
                         ┌─────────────────────┐
                         │  Internet SpecialIP │
                         └──────────▲──────────┘
                                    │ (Match IP list → eth0)
┌──────────┐    wg0      ┌──────────┴──────────┐
│   PC1    │────────────►│       WG1           │
│          │  10.10.0.x  │   (VPS1 - Router)   │
└──────────┘             │                     │
                         │  Policy Routing:    │
                         │  - Match → eth0     │
                         │  - No Match → wg1   │
                         └──────────┬──────────┘
                                    │ wg1 10.20.0.x
                         ┌──────────▼──────────┐
                         │       WG2           │
                         │   (VPS2 - Exit)     │
                         └──────────┬──────────┘
                                    │ eth0
                         ┌──────────▼──────────┐
                         │  Internet (Default) │
                         └─────────────────────┘
```

**Logic routing:**

- Traffic đến **Special IPs** (từ `special-ips.json`) → đi trực tiếp qua `eth0` của WG1
- Traffic còn lại → đi qua tunnel `wg1` đến WG2 → ra Internet

## Tính năng

- ✅ **Split Routing**: Traffic đến special IPs đi trực tiếp qua WG1, còn lại qua WG2
- ✅ **Auto-reload**: Tự động reload IP list khi file thay đổi (inotify)
- ✅ **Auto-reconnect**: Systemd services tự khởi động lại khi disconnect
- ✅ **REST API**: Quản lý routes động qua HTTP API
- ✅ **ipset**: Hiệu suất cao với 50K+ routes

---

## Cấu trúc thư mục

```
SD-WAN/
├── configs/
│   ├── pc1/wg0.conf         # Config cho PC1
│   ├── wg1/
│   │   ├── wg0.conf         # WG1 tunnel to PC1
│   │   └── wg1.conf         # WG1 tunnel to WG2
│   └── wg2/wg0.conf         # Config cho WG2
├── scripts/
│   ├── wg0-up.sh            # Chạy khi wg0 up (setup routing)
│   ├── wg0-down.sh          # Cleanup khi wg0 down
│   ├── load-special-ips.sh  # Load IP list vào ipset
│   └── file-watcher.sh      # Watch file changes
├── services/
│   ├── wg0.service          # Systemd cho wg0
│   ├── wg1.service          # Systemd cho wg1
│   ├── sdwan-watcher.service  # File watcher service
│   └── sdwan-api.service    # API server service
├── api/
│   └── server.sh            # REST API server
├── documents/               # Tài liệu gốc (screenshots, diagrams)
└── config.env.example       # Template config
```

---

## Hướng dẫn Deploy

### 1. Chuẩn bị (trên cả 2 VPS)

```bash
apt update && apt install -y wireguard wireguard-tools ipset jq inotify-tools socat

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
```

### 2. Generate WireGuard Keys

```bash
# Trên mỗi máy (PC1, WG1, WG2)
wg genkey | tee privatekey | wg pubkey > publickey

# WG1 cần 2 key pairs (cho wg0 và wg1)
wg genkey | tee privatekey-wg1 | wg pubkey > publickey-wg1
```

### 3. Deploy WG2 (VPS2 - Exit Node)

```bash
# Copy config
scp configs/wg2/wg0.conf root@VPS2:/etc/wireguard/wg0.conf

# SSH vào VPS2 và thay thế placeholders
ssh root@VPS2
vim /etc/wireguard/wg0.conf
# Thay: <WG2_PRIVATE_KEY>, <WG1_WG1_PUBLIC_KEY>

# Start
systemctl enable --now wg-quick@wg0
```

### 4. Deploy WG1 (VPS1 - Router)

```bash
# SSH vào VPS1
ssh root@VPS1

# Tạo thư mục
mkdir -p /etc/sdwan/{scripts,api}

# Copy files (từ local)
scp scripts/*.sh root@VPS1:/etc/sdwan/scripts/
scp api/server.sh root@VPS1:/etc/sdwan/api/
scp config.env.example root@VPS1:/etc/sdwan/config.env

chmod +x /etc/sdwan/scripts/*.sh /etc/sdwan/api/*.sh

# Copy WireGuard configs
scp configs/wg1/*.conf root@VPS1:/etc/wireguard/

# Thay thế placeholders trong configs
vim /etc/wireguard/wg0.conf
vim /etc/wireguard/wg1.conf
vim /etc/sdwan/config.env

# Copy IP list
scp documents/260115-chinaip.json root@VPS1:/etc/sdwan/special-ips.json

# Copy systemd services
scp services/*.service root@VPS1:/etc/systemd/system/
systemctl daemon-reload

# Start services
systemctl enable --now wg-quick@wg0 wg-quick@wg1 sdwan-watcher sdwan-api
```

### 5. Deploy PC1

```bash
# Copy config và thay thế placeholders
# Thay: <PC1_PRIVATE_KEY>, <WG1_PUBLIC_KEY>, <IP_VPS1>

# Linux
wg-quick up wg0

# Windows: Import file .conf vào WireGuard app
```

---

## API Usage

### Health Check

```bash
curl http://<WG1_IP>:8080/health
```

### Xem danh sách IP đặc biệt

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" http://<WG1_IP>:8080/api/ips
```

### Thêm IP vào danh sách

```bash
curl -X POST -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"ip":"1.2.3.0/24"}' \
     http://<WG1_IP>:8080/api/ips
```

### Xóa IP khỏi danh sách

```bash
curl -X DELETE -H "Authorization: Bearer YOUR_TOKEN" \
     http://<WG1_IP>:8080/api/ips/1.2.3.0/24
```

### Reload IP list từ file

```bash
curl -X POST -H "Authorization: Bearer YOUR_TOKEN" \
     http://<WG1_IP>:8080/api/reload
```

### Xem status

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" http://<WG1_IP>:8080/api/status
```

---

## Format file IP list

Hỗ trợ các format JSON sau:

```json
// Format 1: Array đơn giản
["1.2.3.0/24", "5.6.7.8", "10.0.0.0/8"]

// Format 2: Object với key "ips"
{"ips": ["1.2.3.0/24", "5.6.7.8"]}

// Format 3: Object với key "routes"
{"routes": ["1.2.3.0/24", "5.6.7.8"]}
```

---

## Troubleshooting

### Kiểm tra WireGuard

```bash
wg show
wg show wg0
wg show wg1
```

### Kiểm tra ipset

```bash
ipset list special_ips | head -20
ipset list special_ips | wc -l   # Đếm số entries
```

### Kiểm tra routing rules

```bash
ip rule show
ip route show table 100   # Special IPs
ip route show table 200   # Default via WG2
```

### Kiểm tra iptables marks

```bash
iptables -t mangle -L PREROUTING -v -n
```

### Xem logs

```bash
journalctl -u wg-quick@wg0 -f
journalctl -u wg-quick@wg1 -f
journalctl -u sdwan-watcher -f
journalctl -u sdwan-api -f
```

---

## Placeholders cần thay thế

| Placeholder             | Mô tả                         |
| ----------------------- | ----------------------------- |
| `<IP_VPS1>`             | IP public của VPS1            |
| `<IP_VPS2>`             | IP public của VPS2            |
| `<PC1_PRIVATE_KEY>`     | Private key của PC1           |
| `<WG1_PRIVATE_KEY>`     | Private key của WG1 (cho wg0) |
| `<WG1_WG1_PRIVATE_KEY>` | Private key của WG1 (cho wg1) |
| `<WG2_PRIVATE_KEY>`     | Private key của WG2           |
| `<PC1_PUBLIC_KEY>`      | Public key của PC1            |
| `<WG1_PUBLIC_KEY>`      | Public key của WG1 (cho wg0)  |
| `<WG1_WG1_PUBLIC_KEY>`  | Public key của WG1 (cho wg1)  |
| `<WG2_PUBLIC_KEY>`      | Public key của WG2            |

---

## Lưu ý bảo mật

- ⚠️ Không commit private keys lên git
- ⚠️ Đổi `API_TOKEN` trong `config.env` thành token mạnh
- ⚠️ Sử dụng firewall để chỉ cho phép traffic cần thiết
- ⚠️ API server chỉ nên bind localhost nếu không cần remote access
