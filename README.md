# SD-WAN WireGuard Configuration

## Mục tiêu

```
PC (WireGuard Client) → VPS1 (WireGuard Server/Relay) → VPS2 (WireGuard Client) → Internet (IP X)
```

Traffic từ PC sẽ đi qua VPS1, sau đó đến VPS2, và xuất ra Internet với IP public của VPS2 (IP X).

---

## 2 Phương án

| Phương án | Mô tả | Ưu điểm | Nhược điểm |
|-----------|-------|---------|------------|
| **Method 1** | Single WireGuard Tunnel (wg0) | Đơn giản, 1 tunnel duy nhất | Tất cả trong 1 network |
| **Method 2** | Double WireGuard Tunnels (wg0 + wg1) | Tách biệt network | Phức tạp hơn |

---

## Sơ đồ

### Method 1: Single Tunnel (1 WireGuard Network)
```
┌─────────────┐      wg0        ┌─────────────────┐      wg0        ┌─────────────────┐
│     PC      │ ─────────────>  │      VPS1       │ <───────────── │      VPS2       │
│ (WG Client) │                 │  (WG Server)    │                 │  (WG Client)    │
│  10.0.0.2   │                 │   10.0.0.1      │                 │   10.0.0.3      │
└─────────────┘                 └─────────────────┘                 └─────────────────┘
                                        │                                   │
                                        │         forward traffic           │
                                        └──────────────────────────────────>│
                                                                            ▼
                                                                      Internet (IP X)
```

**Luồng traffic:**
1. PC (10.0.0.2) → VPS1 (10.0.0.1) qua WireGuard
2. VPS2 (10.0.0.3) kết nối đến VPS1 như một client
3. VPS1 forward traffic từ PC đến VPS2
4. VPS2 NAT traffic ra Internet

### Method 2: Double Tunnels (2 WireGuard Networks)
```
┌─────────────┐      wg0        ┌─────────────────┐      wg1        ┌─────────────────┐
│     PC      │ ─────────────>  │      VPS1       │ ─────────────>  │      VPS2       │
│ (WG Client) │                 │ (WG Server+     │                 │  (WG Server)    │
│  10.0.0.2   │                 │  WG Client)     │                 │   10.0.1.1      │
└─────────────┘                 │  10.0.0.1       │                 └─────────────────┘
                                │  10.0.1.2       │                         │
                                └─────────────────┘                         ▼
                                                                      Internet (IP X)
```

**Luồng traffic:**
1. PC (10.0.0.2) → VPS1 (10.0.0.1) qua wg0
2. VPS1 (10.0.1.2) → VPS2 (10.0.1.1) qua wg1
3. VPS2 NAT traffic ra Internet

---

## Cấu trúc thư mục

```
.
├── README.md                    # File này
├── config.env                   # File cấu hình VPS (IP, user, port)
├── .github/
│   └── workflows/
│       ├── deploy.yml           # GitHub Actions workflow (Method 1)
│       └── deploy-method2.yml   # GitHub Actions workflow (Method 2)
├── method-1-single-tunnel/      # Phương án 1
│   ├── README.md
│   ├── vps1/
│   │   ├── setup.sh
│   │   └── wg0.conf
│   ├── vps2/
│   │   ├── setup.sh
│   │   └── wg0.conf
│   └── pc/
│       └── wg0.conf
└── method-2-double-tunnel/      # Phương án 2
    ├── README.md
    ├── vps1/
    │   ├── setup.sh
    │   ├── wg0.conf
    │   └── wg1.conf
    ├── vps2/
    │   ├── setup.sh
    │   └── wg0.conf
    └── pc/
        └── wg0.conf
```

---

## 🚀 GitHub Actions - Auto Deploy

### Cấu hình

#### 1. Cập nhật file `config.env`
File này chứa thông tin VPS (IP, user, port):
```bash
# VPS1 Configuration
VPS1_HOST="103.109.187.182"
VPS1_USER="root"
VPS1_SSH_PORT="22"

# VPS2 Configuration
VPS2_HOST="103.109.187.179"
VPS2_USER="root"
VPS2_SSH_PORT="22"
```

#### 2. Thêm SSH Keys vào GitHub Secrets
Vào **Settings → Secrets and variables → Actions → New repository secret**

| Secret Name | Giá trị |
|-------------|---------|
| `VPS1_SSH_KEY` | Private key SSH để login VPS1 |
| `VPS2_SSH_KEY` | Private key SSH để login VPS2 |

> **Lưu ý:** Copy toàn bộ nội dung private key bao gồm cả `-----BEGIN OPENSSH PRIVATE KEY-----` và `-----END OPENSSH PRIVATE KEY-----`

#### 3. Chạy Workflow

**Có 2 workflows:**

##### 📌 Method 1: Deploy SD-WAN to VPS
1. Vào tab **Actions** trên GitHub
2. Chọn **Deploy SD-WAN to VPS**
3. Click **Run workflow**
4. Chọn **Method**: `method-1`
5. Click **Run workflow** để bắt đầu

##### 📌 Method 2: Deploy SD-WAN Method 2 (Double Tunnel) ⭐
Workflow riêng cho Method 2 với chain WireGuard hoàn chỉnh:

1. Vào tab **Actions** trên GitHub
2. Chọn **Deploy SD-WAN Method 2 (Double Tunnel)**
3. Click **Run workflow**
4. Chọn **Action**:
   - `deploy-all`: Deploy toàn bộ (VPS2 → VPS1 → Exchange keys → Restart)
   - `restart-wireguard`: Chỉ restart WireGuard trên cả 2 VPS
   - `check-status`: Kiểm tra trạng thái WireGuard
5. Click **Run workflow** để bắt đầu

### Workflow sẽ thực hiện:

**Method 1:**
1. Đọc cấu hình từ `config.env`
2. SSH vào VPS được chọn
3. Upload các file cấu hình WireGuard
4. Chạy script setup tự động

**Method 2 (deploy-all):**
1. Đọc cấu hình từ `config.env`
2. Deploy VPS2 (WireGuard Server + NAT)
3. Deploy VPS1 (WireGuard Server cho PC + Client đến VPS2)
4. Tự động exchange public keys giữa VPS1 và VPS2
5. Restart WireGuard trên cả 2 VPS
6. Kiểm tra kết nối VPS1 ↔ VPS2
7. Hiển thị config cho PC

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
| `<VPS1_PRIVATE_KEY>` | Private key của VPS1 (tự động thay bởi script) |
| `<VPS1_PUBLIC_KEY>` | Public key của VPS1 |
| `<VPS2_PRIVATE_KEY>` | Private key của VPS2 (tự động thay bởi script) |
| `<VPS2_PUBLIC_KEY>` | Public key của VPS2 |
| `<PC_PRIVATE_KEY>` | Private key của PC |
| `<PC_PUBLIC_KEY>` | Public key của PC |

### Tạo key pair:
```bash
wg genkey | tee privatekey | wg pubkey > publickey
```

---

## Quick Start

### Thứ tự deploy:

**Method 1:**
1. Deploy VPS1 trước (tạo keys, lưu public key)
2. Deploy VPS2 (cấu hình kết nối đến VPS1)
3. Cấu hình PC với public keys của VPS1

**Method 2:**
1. Deploy VPS2 trước (tạo keys, lưu public key)
2. Deploy VPS1 (cấu hình kết nối đến VPS2)
3. Cấu hình PC với public keys của VPS1

---

## Lưu ý bảo mật

- Không commit private keys lên git
- Sử dụng firewall để chỉ cho phép traffic cần thiết
- Thường xuyên rotate keys
