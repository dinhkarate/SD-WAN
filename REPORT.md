# BÁO CÁO DỰ ÁN SD-WAN SPLIT ROUTING

**Ngày:** 28/01/2026  
**Thực hiện:** Daniel  
**Trạng thái:** ✅ HOÀN THÀNH  
**Method:** Method 1 (Single Interface Chain)

---

## 1. MỤC TIÊU DỰ ÁN

### 1.1 Yêu cầu ban đầu

Xây dựng hệ thống SD-WAN với WireGuard cho phép:

- PC kết nối đến VPS1 qua WireGuard tunnel
- Traffic đến **Special IPs** (danh sách IP đặc biệt) → đi trực tiếp qua VPS1
- Traffic còn lại → đi qua VPS1 → VPS2 → Internet

### 1.2 Yêu cầu bổ sung

- **Dynamic reload**: Cập nhật IP list runtime không cần restart
- **Single interface**: Chỉ dùng 1 interface wg0 trên mỗi node
- **Đơn giản**: Dễ maintain và debug

---

## 2. KIẾN TRÚC HỆ THỐNG

### 2.1 Sơ đồ mạng (Method 1 - Single Interface Chain)

```
                         ┌────────────────────┐
                         │ Internet (Special) │
                         └──────────▲─────────┘
                                    │ eth0 (VPS1 IP)
                                    │
┌──────────┐    wg0      ┌──────────┴──────────┐    wg0      ┌─────────────────┐
│   PC1    │────────────►│        VPS1         │◄───────────►│      VPS2       │
│10.10.0.2 │   :51820    │   103.109.187.182   │   :51820    │ 103.109.187.179 │
└──────────┘             │     10.10.0.1       │             │    10.10.0.3    │
                         └─────────────────────┘             └────────┬────────┘
                                                                      │ eth0
                                                             ┌────────▼────────┐
                                                             │Internet (Default)│
                                                             │   IP: VPS2      │
                                                             └─────────────────┘
```

### 2.2 Đặc điểm Method 1

| Đặc điểm               | Giá trị               |
| ---------------------- | --------------------- |
| Số interface trên VPS1 | 1 (`wg0`)             |
| Subnet                 | 1 (`10.10.0.0/24`)    |
| Cách kết nối VPS2      | Peer trong cùng `wg0` |
| Độ phức tạp            | Thấp                  |

### 2.3 Logic Routing

| Traffic Type | Destination                         | Route Path                               |
| ------------ | ----------------------------------- | ---------------------------------------- |
| Special IP   | IP trong list (8.8.8.8, 1.1.1.1...) | PC → VPS1 → eth0 → Internet              |
| Normal IP    | IP không trong list                 | PC → VPS1 → wg0 → VPS2 → eth0 → Internet |

### 2.4 Cơ chế hoạt động

1. **PC1** gửi tất cả traffic qua tunnel `wg0` đến **VPS1**
2. **VPS1** nhận traffic và kiểm tra destination IP:
   - Dùng `ipset special_ips` để match với danh sách Special IPs
   - Dùng `iptables mangle` để đánh dấu (fwmark 100) packets match
3. **Policy Routing** trên VPS1:
   - fwmark 100 → Table 100 → ra eth0 (Internet qua VPS1 IP)
   - from 10.10.0.2 → Table 200 → via 10.10.0.3 (forward tới VPS2)
4. **VPS2** nhận traffic từ VPS1 qua wg0 → NAT ra Internet (VPS2 IP)

---

## 3. CẤU HÌNH HỆ THỐNG

### 3.1 Thông tin VPS

| Server | IP Public       | WG IP     | Vai trò                 |
| ------ | --------------- | --------- | ----------------------- |
| VPS1   | 103.109.187.182 | 10.10.0.1 | Gateway, Policy Routing |
| VPS2   | 103.109.187.179 | 10.10.0.3 | Exit Node               |
| PC1    | (dynamic)       | 10.10.0.2 | Client                  |

### 3.2 WireGuard Network

| Tunnel            | Network      | Các node                    |
| ----------------- | ------------ | --------------------------- |
| PC1 ↔ VPS1 ↔ VPS2 | 10.10.0.0/24 | PC1: .2, VPS1: .1, VPS2: .3 |

### 3.3 Public Keys

| Node | Public Key                                     |
| ---- | ---------------------------------------------- |
| VPS1 | `t+4f9tArVGpO+SZREGdA/v1zSFpnanTEvZfiouIkIFg=` |
| VPS2 | `GIsyc1E01M6moYkhmwfPPWIMFltCG7NcZIZ8b67J0RQ=` |
| PC1  | `vafYFdIcwLv0LUseYKDE3c0KHqG2VxhJzN1kKAUnsGQ=` |

### 3.4 Cấu trúc file

```
/etc/sdwan/                    # Trên VPS1
├── special-ips.txt            # Danh sách IP đặc biệt
└── scripts/
    └── wg0-up.sh              # Setup/teardown policy routing

/etc/wireguard/
└── wg0.conf                   # WireGuard config (cả 2 VPS)
```

---

## 4. KẾT QUẢ KIỂM THỬ

### 4.1 Test Connectivity

```bash
$ wg show wg0
interface: wg0
  public key: t+4f9tArVGpO+SZREGdA/v1zSFpnanTEvZfiouIkIFg=
  listening port: 51820

peer: GIsyc1E01M6moYkhmwfPPWIMFltCG7NcZIZ8b67J0RQ=  # VPS2
  endpoint: 103.109.187.179:51820
  latest handshake: 8 seconds ago
  transfer: 316 B received, 180 B sent

peer: vafYFdIcwLv0LUseYKDE3c0KHqG2VxhJzN1kKAUnsGQ=  # PC1
  latest handshake: 1 minute ago
```

**Kết quả:** ✅ PASS - Kết nối WireGuard thành công

### 4.2 Test Split Routing

#### Test 1: Normal IP (1.0.1.1 - KHÔNG trong special list)

```bash
$ traceroute 1.0.1.1
traceroute to 1.0.1.1 (1.0.1.1), 64 hops max
  1   10.10.0.1       45.124ms   # VPS1
  2   10.10.0.3        5.953ms   # VPS2 (QUA TUNNEL)
  3   103.109.187.1   59.394ms   # VPS2 Gateway
  4   172.28.37.25    66.826ms   # Internet
```

**Kết quả:** ✅ PASS - Traffic đi qua VPS1 → VPS2 → Internet

#### Test 2: Special IP (8.8.8.8 - trong special list)

```bash
$ traceroute 8.8.8.8
traceroute to 8.8.8.8 (8.8.8.8), 64 hops max
  1   10.10.0.1       51.003ms   # VPS1
  2   103.109.187.1    5.079ms   # VPS1 Gateway (TRỰC TIẾP)
  3   172.28.37.29     3.865ms   # Internet
  4   115.165.164.54   3.790ms
  5   101.99.0.90     37.477ms
```

**Kết quả:** ✅ PASS - Traffic đi trực tiếp qua VPS1, KHÔNG qua VPS2

### 4.3 Verify Policy Routing

```bash
$ ssh vina7 "/etc/sdwan/scripts/wg0-up.sh status"

=== IPSet ===
Name: special_ips
Members:
1.1.1.1
8.8.4.4
8.8.8.8

=== Routing Tables ===
Table 100 (special→eth0):
default via 103.109.187.1 dev eth0
Table 200 (default→VPS2):
default via 10.10.0.3 dev wg0

=== IP Rules ===
100:  from all fwmark 0x64 lookup special
150:  from 10.10.0.2 lookup tunnel

=== Mangle ===
MARK  10.10.0.2  0.0.0.0/0  match-set special_ips dst MARK set 0x64
```

**Kết quả:** ✅ PASS - Policy routing hoạt động đúng

### 4.4 Tổng hợp kết quả

| Test Case            | Expected                 | Actual                | Status |
| -------------------- | ------------------------ | --------------------- | ------ |
| WG Connection        | Handshake OK             | Handshake OK          | ✅     |
| Normal IP (1.0.1.1)  | Hop 2 = VPS2 (10.10.0.3) | Hop 2 = 10.10.0.3     | ✅     |
| Special IP (8.8.8.8) | Hop 2 = VPS1 Gateway     | Hop 2 = 103.109.187.1 | ✅     |
| ipset Match          | 8.8.8.8 in set           | 8.8.8.8 in set        | ✅     |
| ipset No Match       | 1.0.1.1 not in set       | 1.0.1.1 not in set    | ✅     |

---

## 5. VẤN ĐỀ GẶP PHẢI VÀ GIẢI PHÁP

### 5.1 Route table conflict khi start wg0

**Vấn đề:** `wg-quick` với `AllowedIPs = 0.0.0.0/0` tự động thêm route, gây conflict.

**Giải pháp:** Thêm `Table = off` vào VPS1 wg0.conf để tắt auto-routing.

### 5.2 Traffic không forward qua VPS2

**Vấn đề:** Traffic từ PC1 không đến được VPS2.

**Nguyên nhân:** Thiếu forward rule `wg0 → wg0` và ip rule cho PC1.

**Giải pháp:**

1. Thêm `iptables -A FORWARD -i wg0 -o wg0 -j ACCEPT`
2. Thêm `ip rule add from 10.10.0.2 table 200 priority 150`

### 5.3 PC1 exit qua VPS1 thay vì VPS2

**Vấn đề:** Default traffic của PC1 đi qua eth0 VPS1.

**Nguyên nhân:** Thiếu routing table 200 cho default traffic.

**Giải pháp:** Thêm `ip route add default via 10.10.0.3 dev wg0 table 200`

---

## 6. HƯỚNG DẪN VẬN HÀNH

### 6.1 Khởi động/Dừng WireGuard

```bash
# VPS1 & VPS2
systemctl start wg-quick@wg0
systemctl stop wg-quick@wg0
systemctl enable wg-quick@wg0  # Auto-start

# PC1
wg-quick up wg0
wg-quick down wg0
```

### 6.2 Quản lý Special IPs

```bash
# Thêm IP mới
echo "1.2.3.4/32" >> /etc/sdwan/special-ips.txt

# Reload (không cần restart WG)
/etc/sdwan/scripts/wg0-up.sh reload

# Xem trạng thái
/etc/sdwan/scripts/wg0-up.sh status
```

### 6.3 Kiểm tra trạng thái

```bash
# WireGuard
wg show wg0

# Routing
ip rule show
ip route show table 100
ip route show table 200

# ipset
ipset list special_ips
```

### 6.4 Troubleshooting

```bash
# Test IP trong ipset
ipset test special_ips <IP>

# Debug routing cho IP cụ thể
ip route get <IP>

# Traceroute để verify path
traceroute <IP>
```

---

## 7. SO SÁNH METHOD 1 VS METHOD 2

| Đặc điểm            | Method 1 (Deployed) | Method 2              |
| ------------------- | ------------------- | --------------------- |
| Interface trên VPS1 | 1 (wg0)             | 2 (wg0 + wg1)         |
| Subnet              | 1 (10.10.0.0/24)    | 2 (10.10.x + 10.20.x) |
| Kết nối VPS2        | Peer trong wg0      | Interface riêng wg1   |
| Độ phức tạp         | Thấp ✅             | Cao                   |
| Dễ debug            | Dễ ✅               | Khó                   |

---

## 8. KẾT LUẬN

Dự án SD-WAN Split Routing đã được triển khai thành công với **Method 1 (Single Interface Chain)**:

✅ **Split Routing** - Special IPs đi trực tiếp qua VPS1, còn lại qua VPS2  
✅ **Single Interface** - Chỉ dùng 1 wg0 trên mỗi node, đơn giản hóa cấu hình  
✅ **Policy Routing** - Sử dụng fwmark + ipset + custom routing tables  
✅ **Dynamic Reload** - Cập nhật IP list runtime không cần restart  
✅ **Verified Working** - Đã test và xác nhận hoạt động đúng

### Đề xuất cải tiến

1. **Auto-reload**: File watcher để tự động reload khi special-ips.txt thay đổi
2. **Web UI**: Giao diện web để quản lý IP list
3. **Monitoring**: Prometheus metrics cho traffic stats
4. **Failover**: Backup VPS với health check

---

**Kết thúc báo cáo**
