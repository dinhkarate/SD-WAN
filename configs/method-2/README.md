# Lab 3 - Method 2: SD-WAN Split Routing (do2 + fominet)

## Tổng quan

PC1 kết nối tới do2 (VPS1). do2 phân loại traffic dựa trên IP đích:

- **China IPs** → chuyển qua tunnel wg1 tới fominet → ra internet bằng IP fominet
- **Other IPs** → đi trực tiếp qua eth0 do2 → ra internet bằng IP do2

---

## Sơ đồ mạng

```
┌──────────┐       ┌─────────────────────────────────────┐       ┌──────────────────────┐
│   PC1    │       │            do2 (VPS1)                │       │   fominet (VPS2)     │
│          │       │         152.42.238.137                │       │   OpenWRT            │
│ 10.10.0.2│──wg0──│►10.10.0.1        10.20.0.1──────wg1──│──────►│ 10.20.0.2            │
│          │:51820 │    │                                  │:51821 │                      │
└──────────┘       │    │ SPLIT ROUTING                    │       │  NAT → WAN           │
                   │    │                                  │       │  (thatnghiep.ddns.net)│
                   │    ├── China IPs ──► wg1 ─────────────┼──────►│──► Internet           │
                   │    │   (fwmark 200, table 200)        │       │    Exit: IP fominet  │
                   │    │                                  │       └──────────────────────┘
                   │    └── Other IPs ──► eth0             │
                   │        (fwmark 100, table 100)        │
                   │             │                         │
                   └─────────────┼─────────────────────────┘
                                 │
                                 ▼
                            Internet
                         Exit: 152.42.238.137
```

---

## Thiết bị & IP

| Thiết bị    | Public IP           | WG Interfaces                  | Vai trò               |
| ----------- | ------------------- | ------------------------------ | --------------------- |
| **PC1**     | (client)            | wg0: 10.10.0.2                 | Client                |
| **do2**     | 152.42.238.137      | wg0: 10.10.0.1, wg1: 10.20.0.1 | Hub / Split Router    |
| **fominet** | thatnghiep.ddns.net | wg1: 10.20.0.2                 | Exit Node (China IPs) |

---

## Subnets

| Subnet       | Kết nối       | Port  |
| ------------ | ------------- | ----- |
| 10.10.0.0/24 | PC1 ↔ do2     | 51820 |
| 10.20.0.0/24 | do2 ↔ fominet | 51821 |

---

## Traffic Flow (IP nào forward đi đâu)

```
                         ┌──────────────────────────────────────┐
                         │         do2 - Split Routing           │
                         │                                       │
  PC1 traffic ──────────►│  1. Mọi packet vào wg0               │
                         │  2. Kiểm tra IP đích trong ipset      │
                         │                                       │
                         │  ┌─────────────────────────────────┐  │
                         │  │ IP đích TRONG ipset china_ips ? │  │
                         │  └──────────┬──────────┬───────────┘  │
                         │          CÓ │          │ KHÔNG        │
                         │             ▼          ▼              │
                         │     fwmark = 200   fwmark = 100       │
                         │     table 200      table 100          │
                         │        │              │               │
                         │        ▼              ▼               │
                         │     → wg1          → eth0             │
                         │     → fominet      → Internet         │
                         │                                       │
                         └───────────────────────────────────────┘
```

### Kết quả kiểm tra IP:

| Destination   | Ví dụ              | fwmark | Route | Exit IP               | Exit Node |
| ------------- | ------------------ | ------ | ----- | --------------------- | --------- |
| **China IPs** | 223.5.5.5 (AliDNS) | 200    | wg1   | IP WAN fominet (DDNS) | fominet   |
| **Other IPs** | 8.8.8.8 (Google)   | 100    | eth0  | 152.42.238.137        | do2       |

---

## Port Forwarding (Router nhà → fominet)

fominet nằm sau NAT: `Internet → Router nhà (192.168.1.1) → fominet (192.168.1.20)`

```
Router nhà (192.168.1.1)
  │
  ├── Port Forward: UDP 51821 → 192.168.1.20:51821
  │   (cho WireGuard tunnel từ do2 ↔ fominet)
  │
  └── fominet WAN: 192.168.1.20
      fominet LAN: 192.168.20.1 (quản lý)
```

### Cần mở trên router nhà:

| Protocol | Port Ngoài | IP trong LAN | Port Trong | Mục đích                |
| -------- | ---------- | ------------ | ---------- | ----------------------- |
| UDP      | 51821      | 192.168.1.20 | 51821      | WG tunnel do2 ↔ fominet |

> **Lưu ý:** Port forward không bắt buộc vì fominet chủ động kết nối ra do2.
> Tuy nhiên, nếu có port forward, do2 cũng có thể khởi tạo lại kết nối
> (hữu ích khi fominet restart mà chưa kịp reconnect).

---

## DDNS

| Hostname            | Trỏ tới           | Cập nhật bởi     |
| ------------------- | ----------------- | ---------------- |
| thatnghiep.ddns.net | IP WAN router nhà | Router / fominet |

Dùng trong: `configs/method-2/do2/wg1.conf` → `Endpoint = thatnghiep.ddns.net:51821`

---

## Cách thêm / xoá IP vào China list

### File IP:

```
/etc/sdwan/chinaip.txt    # Trên do2
```

### Thêm 1 IP:

```bash
# Thêm vào file
echo "119.29.29.29/32" >> /etc/sdwan/chinaip.txt

# Thêm vào ipset (có hiệu lực ngay)
ipset add china_ips 119.29.29.29/32

# Hoặc reload toàn bộ:
/etc/sdwan/routing-setup.sh reload
```

### Thêm 1 subnet:

```bash
echo "223.5.0.0/16" >> /etc/sdwan/chinaip.txt
ipset add china_ips 223.5.0.0/16
```

### Xoá 1 IP:

```bash
# Xoá khỏi ipset (có hiệu lực ngay)
ipset del china_ips 119.29.29.29/32

# Xoá khỏi file (để persist)
sed -i '/119.29.29.29/d' /etc/sdwan/chinaip.txt
```

### Kiểm tra IP hiện tại:

```bash
# Xem tất cả IP trong ipset
ipset list china_ips

# Kiểm tra 1 IP cụ thể
ipset test china_ips 223.5.5.5
```

### Kiểm tra routing hoạt động:

```bash
# Trên do2:
/etc/sdwan/routing-setup.sh status

# Trên PC1 (sau khi connect wg0):
traceroute 8.8.8.8       # Nên thấy exit qua do2 (152.42.238.137)
traceroute 223.5.5.5     # Nên thấy exit qua fominet
curl ifconfig.me          # Nên hiện 152.42.238.137
```

---

## Deploy

### Thứ tự triển khai:

```
1. fominet (exit node)  →  2. do2 (hub)  →  3. Trao đổi keys  →  4. PC1
```

### Deploy tự động (từ PC1):

```bash
./scripts/method-2/deploy-all.sh
```

### Deploy thủ công:

```bash
# 1. fominet
ssh fominet
opkg update && opkg install wireguard-tools luci-proto-wireguard kmod-wireguard
# Chạy: scripts/method-2/deploy-fominet.sh
# → Ghi lại pubkey

# 2. do2
ssh do2
apt install wireguard ipset
# Chạy: scripts/method-2/deploy-do2.sh <FOMINET_PUBKEY>
# → Ghi lại pubkey

# 3. Trao đổi keys
# Trên do2: wg set wg1 peer <FOMINET_PUBKEY> allowed-ips 10.20.0.2/32,0.0.0.0/0
# Trên fominet: uci set network.@wireguard_wg1[0].public_key='<DO2_PUBKEY>'

# 4. Test tunnel
# do2:     ping 10.20.0.2
# fominet: ping 10.20.0.1

# 5. PC1
./scripts/method-2/generate-pc1-config.sh
sudo wg-quick up wg0
```

---

## Components

| File                                      | Ở đâu   | Chức năng                       |
| ----------------------------------------- | ------- | ------------------------------- |
| `configs/method-2/do2/wg0.conf`           | do2     | Server nhận PC1                 |
| `configs/method-2/do2/wg1.conf`           | do2     | Tunnel tới fominet              |
| `configs/method-2/fominet/wg1.conf`       | fominet | Ref config (wg-quick format)    |
| `configs/method-2/fominet/setup-uci.sh`   | fominet | UCI setup cho OpenWRT           |
| `configs/method-2/pc1/wg0.conf`           | PC1     | Client config                   |
| `scripts/method-2/routing-setup.sh`       | do2     | ipset + fwmark + policy routing |
| `scripts/method-2/deploy-do2.sh`          | do2     | Auto-deploy do2                 |
| `scripts/method-2/deploy-fominet.sh`      | fominet | Auto-deploy fominet (OpenWRT)   |
| `scripts/method-2/deploy-all.sh`          | PC1     | Deploy toàn bộ từ PC1           |
| `scripts/method-2/generate-pc1-config.sh` | PC1     | Tạo config PC1                  |

---

## Placeholders

Replace these values:

| Placeholder                 | Location         | Description             |
| --------------------------- | ---------------- | ----------------------- |
| `<DO2_WG0_PRIVATE_KEY>`     | do2/wg0.conf     | do2 wg0 private key     |
| `<DO2_WG0_PUBLIC_KEY>`      | pc1/wg0.conf     | do2 wg0 public key      |
| `<DO2_WG1_PRIVATE_KEY>`     | do2/wg1.conf     | do2 wg1 private key     |
| `<DO2_WG1_PUBLIC_KEY>`      | fominet/wg1.conf | do2 wg1 public key      |
| `<FOMINET_WG1_PRIVATE_KEY>` | fominet/wg1.conf | fominet wg1 private key |
| `<FOMINET_WG1_PUBLIC_KEY>`  | do2/wg1.conf     | fominet wg1 public key  |
| `<PC1_WG0_PRIVATE_KEY>`     | pc1/wg0.conf     | PC1 private key         |
| `<PC1_WG0_PUBLIC_KEY>`      | do2/wg0.conf     | PC1 public key          |

---

## Troubleshooting

### do2 (VPS1)

```bash
wg show                              # WireGuard status
/etc/sdwan/routing-setup.sh status   # Routing tables & ipset
ip rule show                         # Policy routing rules
ipset list china_ips | head -20      # China IPs loaded?
journalctl -u wg-quick@wg0 -n 20    # Logs
ss -ulnp | grep 5182                 # Ports listening?
```

### fominet (VPS2/OpenWRT)

```bash
wg show wg1                          # WireGuard status
ping 10.20.0.1                       # Tunnel to do2?
logread | grep wireguard             # Logs
uci show network.wg1                 # UCI config check
```

### PC1

```bash
wg show wg0                          # Connection status
ping 10.10.0.1                       # Reach do2?
ping 10.20.0.2                       # Reach fominet?
traceroute 8.8.8.8                   # Exit via do2?
traceroute 223.5.5.5                 # Exit via fominet?
```

### VPS2 (fominet) không kết nối được

```bash
# Check do2 đang listen port 51821
ssh do2 "ss -ulnp | grep 51821"

# Check firewall do2
ssh do2 "ufw status | grep 51821"

# Check từ fominet
ssh fominet "wg show wg1"
# Nếu không có handshake → check keys, endpoint, firewall, port forwarding
```

### Traffic không đi qua fominet

```bash
# Check routing trên do2
ssh do2 "ip route show table 200"
ssh do2 "ip rule show"
ssh do2 "ipset test china_ips 223.5.5.5"

# Check NAT trên fominet
ssh fominet "iptables -t nat -L POSTROUTING -v"
```
