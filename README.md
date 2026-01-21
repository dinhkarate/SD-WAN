# SD-WAN WireGuard Configuration

## Mục tiêu

```
PC (WireGuard Client) → VPS1 (WireGuard Server/Relay) → VPS2 → Internet (IP X)
```

Traffic từ PC sẽ đi qua VPS1, sau đó đến VPS2, và xuất ra Internet với IP public của VPS2 (IP X).

---

## 2 Phương án

| Phương án | Mô tả | Ưu điểm | Nhược điểm |
|-----------|-------|---------|------------|
| **Method 1** | Single WireGuard Tunnel + Port Forward | Đơn giản, nhanh | Ít bảo mật hơn |
| **Method 2** | Double WireGuard Tunnels | Bảo mật cao hơn | Phức tạp hơn |

---

## Sơ đồ

### Method 1: Single Tunnel (Port Forward)
```
┌─────┐      UDP 51820       ┌─────────────────┐     Forward      ┌─────────────────┐
│ PC  │ ──────────────────>  │ VPS1            │ ───────────────> │ VPS2            │
│     │                      │ (Port Forward)  │                  │ (WG Server+NAT) │
└─────┘                      └─────────────────┘                  └─────────────────┘
                                                                          │
                                                                          ▼
                                                                    Internet (IP X)
```

### Method 2: Double Tunnels
```
┌─────┐    WireGuard 1    ┌─────────────────┐    WireGuard 2    ┌─────────────────┐
│ PC  │ ────────────────> │ VPS1            │ ────────────────> │ VPS2            │
│     │                   │ (WG Server +    │                   │ (WG Server+NAT) │
└─────┘                   │  WG Client)     │                   └─────────────────┘
                          └─────────────────┘                           │
                                                                        ▼
                                                                  Internet (IP X)
```

---

## Cấu trúc thư mục

```
.
├── README.md                    # File này
├── method-1-single-tunnel/      # Phương án 1
│   ├── README.md
│   ├── vps1/
│   ├── vps2/
│   └── pc/
└── method-2-double-tunnel/      # Phương án 2
    ├── README.md
    ├── vps1/
    ├── vps2/
    └── pc/
```

---

## Yêu cầu

### VPS (Debian-based)
- Debian 10+ hoặc Ubuntu 20.04+
- Root access
- IP public tĩnh

### PC (Windows)
- WireGuard for Windows: https://www.wireguard.com/install/

---

## Placeholder cần thay thế

Trước khi deploy, thay thế các placeholder sau:

| Placeholder | Mô tả |
|------------|-------|
| `VPS1_PUBLIC_IP` | IP public của VPS1 |
| `VPS2_PUBLIC_IP` | IP public của VPS2 (IP X) |
| `<VPS1_PRIVATE_KEY>` | Private key của VPS1 |
| `<VPS1_PUBLIC_KEY>` | Public key của VPS1 |
| `<VPS2_PRIVATE_KEY>` | Private key của VPS2 |
| `<VPS2_PUBLIC_KEY>` | Public key của VPS2 |
| `<PC_PRIVATE_KEY>` | Private key của PC |
| `<PC_PUBLIC_KEY>` | Public key của PC |

### Tạo key pair:
```bash
wg genkey | tee privatekey | wg pubkey > publickey
```

---

## Quick Start

1. Chọn phương án phù hợp (method-1 hoặc method-2)
2. Đọc README trong thư mục phương án đó
3. Tạo key pairs cho mỗi thiết bị
4. Thay thế placeholders trong các file config
5. Chạy setup scripts theo thứ tự: VPS2 → VPS1 → PC

---

## Lưu ý bảo mật

- Không commit private keys lên git
- Sử dụng firewall để chỉ cho phép traffic cần thiết
- Thường xuyên rotate keys
