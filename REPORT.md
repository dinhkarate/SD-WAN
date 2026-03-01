# SD-WAN Lab 3 — Method 2: Split Routing Report

**Ngày:** 2026-03-01
**Branch:** `lab-3-method-2`
**Trạng thái:** ✅ Hoạt động — Split routing China/non-China đã xác nhận

---

## 1. Kiến trúc mạng

```
┌──────────────┐        WireGuard wg0         ┌───────────────┐       WireGuard wg1        ┌──────────────┐
│   PC0        │    10.10.0.3 ◄──► 10.10.0.1  │     VPS1      │   10.20.0.1 ◄──► 10.20.0.2│   fominet    │
│   (vina7)    │═══════════════════════════════│     (do2)     │═══════════════════════════│  (OpenWRT)   │
│  Hà Nội      │        port 51820             │  Singapore    │       port 51821           │  Việt Nam    │
│ 103.109.     │  AllowedIPs=0.0.0.0/0         │ 152.42.238.137│  Table=off                 │ 118.71.95.99 │
│   187.182    │  (full tunnel, fwmark bypass)  │               │  AllowedIPs=0.0.0.0/0      │              │
└──────────────┘                                └───────┬───────┘                            └──────┬───────┘
                                                        │                                          │
                                              ┌─────────┴─────────┐                           ┌────┴────┐
                                              │   Split Routing    │                           │  NAT    │
                                              │   Engine (do2)     │                           │ masq=1  │
                                              ├────────────────────┤                           └────┬────┘
                                              │                    │                                │
                                         non-China IP         China IP                         Internet
                                         fwmark 100           fwmark 200                      (Vietnam ISP)
                                              │                    │
                                         eth0 (NAT)          wg1 (NAT)
                                              │                    │
                                         Internet              fominet
                                        (Singapore DO)        (Vietnam)
```

### Vai trò các thiết bị

| Thiết bị    | IP công khai              | IP tunnel                        | Vai trò                     |
| ----------- | ------------------------- | -------------------------------- | --------------------------- |
| **PC0**     | 103.109.187.182           | 10.10.0.3 (wg0)                  | Client test (vina7, Hà Nội) |
| **VPS1**    | 152.42.238.137            | 10.10.0.1 (wg0), 10.20.0.1 (wg1) | Hub / Bộ phân luồng traffic |
| **fominet** | DDNS: thatnghiep.ddns.net | 10.20.0.2 (wg1)                  | Exit node cho China IP      |

> **Ghi chú:** PC0 (vina7) là một VPS tại Hà Nội, được dùng thay cho PC vật lý để test vì không có PC nào ở ngoài mạng nội bộ.

---

## 2. Luồng traffic chi tiết

### Tổng quan

Mọi traffic từ PC0 đều đi qua WireGuard tunnel tới VPS1 (do2). Tại VPS1, traffic được phân loại dựa trên IP đích:

```
PC0 gửi packet
    │
    ▼
wg0 tunnel tới VPS1 (do2)
    │
    ▼
┌─────────────────────────────────┐
│  iptables mangle PREROUTING     │
│                                 │
│  Bước 1: MARK tất cả → 0x64    │
│          (fwmark 100, non-China)│
│                                 │
│  Bước 2: Nếu IP đích nằm trong │
│          ipset "china_ips"      │
│          → MARK lại → 0xc8     │
│          (fwmark 200, China)    │
└────────────┬────────────────────┘
             │
    ┌────────┴────────┐
    │                 │
fwmark=100        fwmark=200
(non-China)       (China)
    │                 │
    ▼                 ▼
ip rule:          ip rule:
table vps1_direct table vps2_china
prio 100          prio 99
    │                 │
    ▼                 ▼
default via       default via
152.42.224.1      10.20.0.2
dev eth0          dev wg1
    │                 │
    ▼                 ▼
MASQUERADE        MASQUERADE
→ eth0            → wg1
    │                 │
    ▼                 ▼
Internet          fominet (OpenWRT)
(Singapore)       → NAT → Internet
IP: 152.42.238.137     (Vietnam ISP)
                  IP: 118.71.95.99
```

### ipset china_ips

- **3,524 CIDR** được load từ `/etc/sdwan/chinaip.txt`
- Ví dụ: 223.5.5.5 ✅ trong set, 114.114.114.114 ✅ trong set, 8.8.8.8 ❌ không trong set
- Quản lý bằng script: `/etc/sdwan/routing-setup.sh reload|status`

### fwmark bypass trên PC0 (tránh routing loop)

PC0 dùng `AllowedIPs = 0.0.0.0/0` (full tunnel). wg-quick tự động tạo fwmark bypass:

```
Luật trên PC0:
  not fwmark 0xca6c → lookup table 51820 → 0.0.0.0/0 dev wg0

Kết quả:
  - Traffic thường (không có fwmark) → vào wg0 tunnel
  - Packet WireGuard UDP (fwmark 0xca6c) → đi thẳng qua main table → tới endpoint
```

> **Bài học:** KHÔNG dùng `AllowedIPs = 0.0.0.0/1, 128.0.0.0/1` — cách này không trigger fwmark routing của wg-quick, gây routing loop và mất kết nối. Phải dùng `0.0.0.0/0`.

---

## 3. Kết quả test

Tất cả test chạy từ PC0 (vina7), SSH qua `ssh -J do2 root@10.10.0.3`.

### 3.1 Tunnel

| Tunnel               | Kết quả | RTT   | Loss |
| -------------------- | ------- | ----- | ---- |
| PC0 → VPS1 (wg0)     | 3/3     | ~57ms | 0%   |
| VPS1 → fominet (wg1) | 3/3     | ~40ms | 0%   |

### 3.2 Traceroute — China IP (223.5.5.5, Alibaba DNS)

```
 1  10.10.0.1      56ms    ← VPS1 (do2, qua wg0)
 2  10.20.0.2     102ms    ← fominet (qua wg1) ✅ ĐƯỜNG CHINA
 3  192.168.1.1   105ms    ← Router nhà fominet
 4  118.69.185.181 113ms   ← ISP Việt Nam (FPT)
 5  42.116.133.10  115ms   ← Backbone Việt Nam
 ...
10  118.69.247.78  134ms   ← Tới mạng Alibaba (Trung Quốc)
```

### 3.3 Traceroute — Non-China IP (8.8.8.8, Google DNS)

```
 1  10.10.0.1      57ms    ← VPS1 (do2, qua wg0)
 2  * * *
 3  10.76.194.68   58ms    ← DigitalOcean internal ✅ ĐƯỜNG TRỰC TIẾP
 4  143.198.252.12 58ms    ← DigitalOcean backbone
 5  143.244.192.178 58ms   ← DigitalOcean peering
 ...
10  8.8.8.8        57ms    ← Google DNS
```

> **So sánh:** Traffic China đi qua **10.20.0.2 (fominet)** → ISP Việt Nam. Traffic non-China đi qua **DigitalOcean Singapore** trực tiếp.

### 3.4 HTTP

| Test                    | Kết quả                                | Exit IP             |
| ----------------------- | -------------------------------------- | ------------------- |
| `curl ifconfig.me`      | 152.42.238.137                         | VPS1 (Singapore) ✅ |
| `curl myip.ipip.net`    | "新加坡 digitalocean.com"              | VPS1 ✅             |
| `curl http://baidu.com` | HTTP 200, remote 45.113.192.102, 0.22s | qua fominet (VN) ✅ |
| `dig google.com`        | Resolve thành công qua 8.8.8.8         | DNS hoạt động ✅    |

### 3.5 Ping

| Target    | Dịch vụ     | Kết quả         | Đường đi       |
| --------- | ----------- | --------------- | -------------- |
| 223.5.5.5 | Alibaba DNS | 3/3, ~139ms, 0% | qua fominet ✅ |
| 8.8.8.8   | Google DNS  | 3/3, ~58ms, 0%  | qua VPS1 ✅    |

### 3.6 Bộ đếm iptables trên VPS1 (do2)

**Mangle (phân loại):**

```
790 packets → fwmark 0x64 (non-China)
 84 packets → fwmark 0xc8 (China)
```

**NAT:**

```
105 packets → MASQUERADE eth0 (non-China qua VPS1)
 44 packets → MASQUERADE wg1  (China qua fominet)
```

**FORWARD:**

```
wg0 → eth0:  215 pkts  (non-China forwarding)
eth0 → wg0:  172 pkts  (return traffic)
wg0 → wg1:   54 pkts  (China → fominet)
wg1 → wg0:   38 pkts  (fominet → PC0 return)
```

---

## 4. Tổng kết

| Thành phần                      | Trạng thái   | Ghi chú                              |
| ------------------------------- | ------------ | ------------------------------------ |
| WG tunnel wg0 (VPS1 ↔ PC0)      | ✅ Hoạt động | Handshake active, 57ms RTT           |
| WG tunnel wg1 (VPS1 ↔ fominet)  | ✅ Hoạt động | Handshake active, 40ms RTT           |
| Full tunnel (PC0 → VPS1)        | ✅ Hoạt động | fwmark bypass tránh routing loop     |
| ipset china_ips                 | ✅ Đã load   | 3,524 CIDRs                          |
| Phân loại traffic (mangle)      | ✅ Hoạt động | fwmark 100 (non-China) / 200 (China) |
| Routing non-China (vps1_direct) | ✅ Hoạt động | Traceroute: VPS1 → DigitalOcean SG   |
| Routing China (vps2_china)      | ✅ Hoạt động | Traceroute: VPS1 → fominet → ISP VN  |
| NAT (cả 2 đường)                | ✅ Hoạt động | MASQUERADE trên eth0 và wg1          |
| DNS                             | ✅ Hoạt động | Resolve qua 8.8.8.8 trong tunnel     |
| HTTP China (baidu.com)          | ✅ Hoạt động | HTTP 200 qua fominet                 |

---

## 5. Lưu ý kỹ thuật

### AllowedIPs trên VPS1 wg1

VPS1 wg1 ban đầu đặt `AllowedIPs = 10.20.0.0/24` cho peer fominet. Điều này khiến WireGuard drop các packet có IP đích China (ví dụ 223.5.5.5) vì không khớp AllowedIPs (cryptokey routing).

**Fix:** Đổi thành `AllowedIPs = 0.0.0.0/0`. An toàn vì `Table = off` — WireGuard không thêm route vào system.

### Docker trên VPS1

VPS1 chạy Docker (FORWARD policy = DROP). Các rule WireGuard được thêm sau Docker rules:

```
iptables -A FORWARD -i wg0 -o wg1 -j ACCEPT
iptables -A FORWARD -i wg1 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

Docker chains (DOCKER-USER, DOCKER-FORWARD) chỉ match docker0/br-\* → không ảnh hưởng traffic WireGuard.

### fominet sau NAT

fominet nằm sau router nhà (192.168.1.1). Không cần port forward vì fominet chủ động kết nối ra VPS1 (`PersistentKeepalive = 25`).

---

## 6. File config đang chạy

Chi tiết config xem phần bên dưới.
