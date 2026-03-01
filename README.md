# SD-WAN Lab 3 — Split Routing với WireGuard (Method 2)

PC kết nối VPS1 (do2, Singapore). VPS1 phân loại traffic theo IP đích:

- **China IPs** → forward qua wg1 tới fominet (OpenWRT, Việt Nam) → ra internet
- **Other IPs** → ra internet trực tiếp từ VPS1

## Kiến trúc

```
                                          ┌──────────────────┐
                                          │   fominet        │
                        WireGuard wg1     │   (OpenWRT)      │
                    ┌─────────────────────│►  10.20.0.2      │
                    │   port 51821        │   DDNS: thathghiep│
                    │                     │   .ddns.net       │
┌──────────┐   WireGuard wg0   ┌─────────┴─────────┐        │  NAT
│   PC0    │   port 51820      │      do2 (VPS1)    │        │──► Internet
│  (vina7) │──────────────────►│   152.42.238.137   │        │   (Vietnam ISP)
│10.10.0.3 │                   │  10.10.0.1 (wg0)   │        └──────────────────┘
└──────────┘                   │  10.20.0.1 (wg1)   │
                               │                    │
┌──────────┐                   │  Split Routing:     │
│   PC1    │──────────────────►│  ┌───────────────┐ │
│10.10.0.2 │   wg0:51820       │  │ipset china_ips│ │
└──────────┘                   │  │ fwmark 200────┼─┼──► wg1 → fominet
                               │  │ fwmark 100────┼─┼──► eth0 → Internet
                               │  └───────────────┘ │      (Singapore)
                               └────────────────────┘
```

## Traffic Flow

| Traffic từ PC | IP đích thuộc | fwmark | Route | Exit IP         | Exit Node         |
| ------------- | ------------- | ------ | ----- | --------------- | ----------------- |
| China IPs     | ipset match   | 200    | wg1   | IP fominet (VN) | fominet (OpenWRT) |
| Other IPs     | không match   | 100    | eth0  | 152.42.238.137  | do2 (Singapore)   |

## Thiết bị

| Thiết bị    | Public IP           | WG Interfaces                  | Vai trò                    |
| ----------- | ------------------- | ------------------------------ | -------------------------- |
| **do2**     | 152.42.238.137      | wg0: 10.10.0.1, wg1: 10.20.0.1 | Hub / Split Router (VPS1)  |
| **fominet** | thatnghiep.ddns.net | wg1: 10.20.0.2                 | Exit Node China IPs (VPS2) |
| **PC0**     | 103.109.187.182     | wg0: 10.10.0.3                 | Test client (vina7)        |
| **PC1**     | (client)            | wg0: 10.10.0.2                 | Client                     |

## Cấu trúc thư mục

```
configs/method-2/
├── do2/
│   ├── wg0.conf           # Server nhận PC (port 51820)
│   └── wg1.conf           # Tunnel tới fominet (port 51821)
├── fominet/
│   ├── wg1.conf           # Reference config (wg-quick format)
│   └── setup-uci.sh       # UCI setup cho OpenWRT
├── pc0/
│   └── wg0.conf           # Config cho vina7 (test client)
├── pc1/
│   └── wg0.conf           # Config template cho PC1
└── README.md              # Hướng dẫn chi tiết

scripts/method-2/
├── routing-setup.sh       # ipset + fwmark + policy routing (chạy trên do2)
├── deploy-do2.sh          # Auto-deploy do2
├── deploy-fominet.sh      # Auto-deploy fominet (OpenWRT)
├── deploy-all.sh          # Deploy toàn bộ từ PC
└── generate-pc1-config.sh # Tạo config PC1
```

## Yêu cầu

| Thiết bị | Yêu cầu                                         |
| -------- | ----------------------------------------------- |
| do2      | Debian 12+, IP: 152.42.238.137, wireguard+ipset |
| fominet  | OpenWRT, DDNS, kmod-wireguard                   |
| PC       | WireGuard client                                |

---

## Hướng dẫn nhanh

### Deploy tự động

```bash
./scripts/method-2/deploy-all.sh
```

### Deploy thủ công

Xem hướng dẫn chi tiết: [`configs/method-2/README.md`](configs/method-2/README.md)

Thứ tự:

1. **fominet** — cài WireGuard, tạo key, UCI config
2. **do2** — cài WireGuard + ipset, tạo key, routing-setup
3. **Trao đổi public keys**
4. **PC** — tạo config, kết nối

### Test

```bash
# Trên PC (sau khi connect wg0):
traceroute 8.8.8.8       # Nên exit qua do2 (152.42.238.137)
traceroute 223.5.5.5     # Nên exit qua fominet (Vietnam ISP)
curl ifconfig.me          # Nên hiện 152.42.238.137
```

---

## Quản lý China IPs

```bash
# Reload danh sách
ssh do2 "/etc/sdwan/routing-setup.sh reload"

# Xem trạng thái
ssh do2 "/etc/sdwan/routing-setup.sh status"

# Thêm IP thủ công
ssh do2 "ipset add china_ips 119.29.29.29/32"

# Kiểm tra 1 IP
ssh do2 "ipset test china_ips 223.5.5.5"
```

---

## Xử lý sự cố

| Vấn đề                           | Kiểm tra                                             |
| -------------------------------- | ---------------------------------------------------- |
| PC không kết nối được            | `wg show wg0` trên do2, firewall port 51820          |
| Traffic không qua fominet        | `ip route show table 200` trên do2, `ipset test`     |
| Tunnel do2↔fominet không kết nối | `wg show wg1` trên do2, `ping 10.20.0.2`             |
| Không có Internet                | `iptables -t nat -L POSTROUTING` trên do2 và fominet |

---

## Tài liệu

- [`configs/method-2/README.md`](configs/method-2/README.md) — Hướng dẫn deploy chi tiết
- [`REPORT.md`](REPORT.md) — Báo cáo test kết quả split routing

## License

MIT
