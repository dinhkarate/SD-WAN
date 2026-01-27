# BÁO CÁO DỰ ÁN SD-WAN SPLIT ROUTING

**Ngày:** 27/01/2026  
**Thực hiện:** Daniel  
**Trạng thái:** ✅ HOÀN THÀNH

---

## 1. MỤC TIÊU DỰ ÁN

### 1.1 Yêu cầu ban đầu

Xây dựng hệ thống SD-WAN với WireGuard cho phép:

- PC kết nối đến VPS1 (WG1) qua WireGuard tunnel
- Traffic đến **Special IPs** (danh sách IP đặc biệt) → đi trực tiếp qua VPS1
- Traffic còn lại → đi qua VPS1 → VPS2 → Internet

### 1.2 Yêu cầu Dynamic

- **Auto-reload**: Tự động cập nhật khi file IP list thay đổi
- **Auto-reconnect**: Tự khởi động lại khi VPS restart
- **API**: Quản lý routes qua REST API

---

## 2. KIẾN TRÚC HỆ THỐNG

### 2.1 Sơ đồ mạng

```
                         ┌─────────────────────┐
                         │  Internet SpecialIP │
                         └──────────▲──────────┘
                                    │ (Match IP list → eth0)
┌──────────┐    wg0      ┌──────────┴──────────┐
│   PC1    │────────────►│       WG1           │
│10.10.0.2 │  Tunnel     │   103.109.187.182   │
└──────────┘             │   (VPS1 - Router)   │
                         │                     │
                         │  wg0: 10.10.0.1     │
                         │  wg1: 10.20.0.1     │
                         └──────────┬──────────┘
                                    │ wg1 (Not Match → tunnel)
                         ┌──────────▼──────────┐
                         │       WG2           │
                         │   103.109.187.179   │
                         │   (VPS2 - Exit)     │
                         │   wg0: 10.20.0.2    │
                         └──────────┬──────────┘
                                    │ eth0
                         ┌──────────▼──────────┐
                         │  Internet (Default) │
                         └─────────────────────┘
```

### 2.2 Logic Routing

| Traffic Type | Destination         | Route Path                            |
| ------------ | ------------------- | ------------------------------------- |
| Special IP   | IP trong list       | PC → WG1 → eth0 VPS1 → Internet       |
| Normal IP    | IP không trong list | PC → WG1 → WG2 → eth0 VPS2 → Internet |

### 2.3 Cơ chế hoạt động

1. **PC1** gửi tất cả traffic qua tunnel `wg0` đến **WG1**
2. **WG1** nhận traffic và kiểm tra destination IP:
   - Dùng `ipset` để match với danh sách Special IPs
   - Dùng `iptables mangle` để đánh dấu (mark) packets
3. **Policy Routing** trên WG1:
   - Mark 100 (Special IP) → Table 100 → ra eth0 (Internet trực tiếp)
   - Mark 200 (Normal IP) → Table 200 → ra wg1 → WG2
4. **WG2** nhận traffic từ WG1 và forward ra Internet

---

## 3. CẤU HÌNH HỆ THỐNG

### 3.1 Thông tin VPS

| Server | IP Public       | Vai trò                      |
| ------ | --------------- | ---------------------------- |
| VPS1   | 103.109.187.182 | WG1 - Router, Policy Routing |
| VPS2   | 103.109.187.179 | WG2 - Exit Node              |

### 3.2 WireGuard Networks

| Tunnel  | Network      | Endpoints        |
| ------- | ------------ | ---------------- |
| PC1↔WG1 | 10.10.0.0/24 | PC1: .2, WG1: .1 |
| WG1↔WG2 | 10.20.0.0/24 | WG1: .1, WG2: .2 |

### 3.3 Cấu trúc thư mục

```
/etc/sdwan/                    # Trên VPS1
├── config.env                 # Cấu hình chung
├── special-ips.json           # Danh sách IP đặc biệt (3516 entries)
├── scripts/
│   ├── wg0-up.sh              # Setup routing khi wg0 up
│   ├── wg0-down.sh            # Cleanup khi wg0 down
│   ├── load-special-ips.sh    # Load IP list vào ipset
│   └── file-watcher.sh        # Auto-reload khi file thay đổi
└── api/
    └── server.sh              # REST API server

/etc/wireguard/                # Trên cả 2 VPS
├── wg0.conf                   # WireGuard config
└── wg1.conf                   # (chỉ VPS1)
```

---

## 4. KẾT QUẢ KIỂM THỬ

### 4.1 Test Connectivity

```bash
$ wg show
interface: wg0
  public key: YTcdIJDUkBKQ7YFQWxFqQtJ7gk2+obpfc/eBTX8wjSA=
  private key: (hidden)
  listening port: 38945

peer: cqzbmrAjKfbuL1AaangUkq8xkOnWj9TSEJ2ydKWFWio=
  endpoint: 103.109.187.182:51820
  allowed ips: 0.0.0.0/0
  latest handshake: 1 minute, 23 seconds ago
  transfer: 12.5 KiB received, 45.2 KiB sent
```

**Kết quả:** ✅ PASS - Kết nối WireGuard thành công

### 4.2 Test Split Routing

#### Test 1: Special IP (1.0.1.1 - trong list)

```bash
$ traceroute 1.0.1.1
traceroute to 1.0.1.1 (1.0.1.1), 64 hops max
  1   10.10.0.1       31.631ms   # WG1
  2   103.109.187.1   54.072ms   # VPS1 Gateway (TRỰC TIẾP)
  3   172.28.37.25    39.917ms   # Internet
```

**Kết quả:** ✅ PASS - Traffic đi trực tiếp qua VPS1, KHÔNG qua WG2

#### Test 2: Normal IP (8.8.8.8 - không trong list)

```bash
$ traceroute 8.8.8.8
traceroute to 8.8.8.8 (8.8.8.8), 64 hops max
  1   10.10.0.1       28.832ms   # WG1
  2   10.20.0.2       28.597ms   # WG2 (QUA TUNNEL)
  3   103.109.187.1   26.746ms   # VPS2 Gateway
  4   172.28.37.29    27.437ms   # Internet
```

**Kết quả:** ✅ PASS - Traffic đi qua WG1 → WG2 → Internet

### 4.3 Verify ipset

```bash
$ ssh vina7 "ipset test special_ips 1.0.1.1"
Warning: 1.0.1.1 is in set special_ips.

$ ssh vina7 "ipset test special_ips 8.8.8.8"
8.8.8.8 is NOT in set special_ips.
```

**Kết quả:** ✅ PASS - ipset phân loại IP chính xác

### 4.4 Tổng hợp kết quả

| Test Case            | Expected                | Actual                | Status |
| -------------------- | ----------------------- | --------------------- | ------ |
| WG Connection        | Handshake OK            | Handshake OK          | ✅     |
| Special IP (1.0.1.1) | Hop 2 = VPS1 Gateway    | Hop 2 = 103.109.187.1 | ✅     |
| Normal IP (8.8.8.8)  | Hop 2 = WG2 (10.20.0.2) | Hop 2 = 10.20.0.2     | ✅     |
| ipset Match          | 1.0.1.1 in set          | 1.0.1.1 in set        | ✅     |
| ipset No Match       | 8.8.8.8 not in set      | 8.8.8.8 not in set    | ✅     |
| Special IPs Loaded   | > 0 entries             | 3516 entries          | ✅     |

---

## 5. VẤN ĐỀ GẶP PHẢI VÀ GIẢI PHÁP

### 5.1 Mất kết nối SSH khi deploy

**Vấn đề:** Script routing ban đầu làm thay đổi main routing table, khiến SSH bị mất.

**Nguyên nhân:**

- `wg-quick` với `AllowedIPs = 0.0.0.0/0` tự động thêm policy routing
- Script thêm rules vào main table thay vì table riêng

**Giải pháp:**

1. Thêm `Table = off` vào `wg1.conf` để tắt auto-routing của wg-quick
2. Sử dụng `fwmark` + custom routing tables (100, 200)
3. Chỉ route traffic từ wg0, không chạm main table

### 5.2 Load IP list thất bại

**Vấn đề:** Script không load được IP từ file JSON.

**Nguyên nhân:** File IP list là plain text, không phải JSON.

**Giải pháp:** Cập nhật script `load-special-ips.sh` để hỗ trợ cả 2 format:

- Plain text (1 IP per line)
- JSON array/object

---

## 6. HƯỚNG DẪN VẬN HÀNH

### 6.1 Khởi động/Dừng WireGuard

```bash
# VPS1
systemctl start wg-quick@wg0 wg-quick@wg1
systemctl stop wg-quick@wg0 wg-quick@wg1

# VPS2
systemctl start wg-quick@wg0
systemctl stop wg-quick@wg0

# PC1
wg-quick up wg0
wg-quick down wg0
```

### 6.2 Cập nhật IP list

```bash
# Sửa file trực tiếp
vim /etc/sdwan/special-ips.json

# Reload thủ công
/etc/sdwan/scripts/load-special-ips.sh

# Hoặc dùng API
curl -X POST -H "Authorization: Bearer sdwan-secret-2026" \
     http://103.109.187.182:8080/api/reload
```

### 6.3 Kiểm tra trạng thái

```bash
# WireGuard status
wg show

# Routing tables
ip rule show
ip route show table 100
ip route show table 200

# ipset
ipset list special_ips | head -20
ipset list special_ips | wc -l

# iptables marks
iptables -t mangle -L PREROUTING -v -n
```

### 6.4 Troubleshooting

```bash
# Xem logs
journalctl -u wg-quick@wg0 -f
journalctl -u wg-quick@wg1 -f

# Test IP trong ipset
ipset test special_ips <IP>

# Debug routing
ip route get <IP>
traceroute <IP>
```

---

## 7. CÁC FILE QUAN TRỌNG

| File                  | Vị trí              | Mô tả                      |
| --------------------- | ------------------- | -------------------------- |
| `wg0.conf`            | /etc/wireguard/     | WireGuard config           |
| `wg1.conf`            | /etc/wireguard/     | WG1↔WG2 tunnel (VPS1 only) |
| `config.env`          | /etc/sdwan/         | Cấu hình chung             |
| `special-ips.json`    | /etc/sdwan/         | Danh sách IP đặc biệt      |
| `wg0-up.sh`           | /etc/sdwan/scripts/ | Setup routing              |
| `wg0-down.sh`         | /etc/sdwan/scripts/ | Cleanup routing            |
| `load-special-ips.sh` | /etc/sdwan/scripts/ | Load IP vào ipset          |

---

## 8. KẾT LUẬN

Dự án SD-WAN Split Routing đã được triển khai thành công với các tính năng:

✅ **Split Routing** - Traffic đến Special IPs đi trực tiếp qua VPS1, còn lại qua VPS2  
✅ **WireGuard VPN** - Kết nối bảo mật giữa PC và các VPS  
✅ **Policy Routing** - Sử dụng fwmark + ipset + custom routing tables  
✅ **Dynamic IP List** - Hỗ trợ 3516+ IP entries, có thể cập nhật runtime  
✅ **Safe Deployment** - Không ảnh hưởng main routing table của VPS

### Đề xuất cải tiến

1. **Monitoring**: Thêm Prometheus/Grafana để giám sát traffic
2. **High Availability**: Thêm VPS backup với failover
3. **Web UI**: Giao diện web để quản lý IP list
4. **Auto-update IP list**: Tự động cập nhật từ nguồn bên ngoài

---

**Kết thúc báo cáo**
