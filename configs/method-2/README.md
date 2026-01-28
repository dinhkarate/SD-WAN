# Method-2: VPS1 Dual WireGuard + VPS2 Exit Node

## Architecture

```
                           ┌─────────────────┐
                           │  Internet (ALL) │
                           └────────▲────────┘
                                    │ eth0 (NAT)
                           ┌────────┴────────┐
                           │      VPS2       │ 103.109.187.179
                           │   (Exit Node)   │
                           │   10.20.0.2     │
                           └────────▲────────┘
                                    │ wg0 (client)
                                    │ connects to VPS1:51821
                                    │
┌──────────┐    wg0:51820   ┌───────┴────────┐
│   PC1    │───────────────►│      VPS1      │ 103.109.187.182
│10.10.0.2 │                │   (Hub/Router) │
└──────────┘                │   wg0: 10.10.0.1 (server, PC1)
                            │   wg1: 10.20.0.1 (server, VPS2)
                            └────────────────┘
```

## Traffic Flow

```
PC1 → VPS1:wg0 → VPS1:wg1 → VPS2:wg0 → Internet
                (routing)   (NAT exit)
```

## Components

| File               | Role   | Purpose                                   |
| ------------------ | ------ | ----------------------------------------- |
| `vps1/wg0.conf`    | Server | Nhận kết nối từ PC1 (port 51820)          |
| `vps1/wg1.conf`    | Server | Nhận kết nối từ VPS2 (port 51821)         |
| `vps2/wg0.conf`    | Client | Kết nối TỚI VPS1:wg1, làm exit node (NAT) |
| `clients/pc1.conf` | Client | PC1 kết nối tới VPS1:wg0                  |
| `routing-setup.sh` | Script | Policy routing trên VPS1                  |

## Subnets

| Tunnel      | Subnet       | Purpose          |
| ----------- | ------------ | ---------------- |
| VPS1 ↔ PC1  | 10.10.0.0/24 | PC1 clients      |
| VPS1 ↔ VPS2 | 10.20.0.0/24 | Exit node tunnel |

## Deployment

### 1. Generate Keys

```bash
# VPS1 - wg0 (for PC1)
wg genkey | tee /etc/wireguard/wg0_privatekey | wg pubkey > /etc/wireguard/wg0_publickey

# VPS1 - wg1 (for VPS2)
wg genkey | tee /etc/wireguard/wg1_privatekey | wg pubkey > /etc/wireguard/wg1_publickey

# VPS2 - wg0 (exit node)
wg genkey | tee /etc/wireguard/wg0_privatekey | wg pubkey > /etc/wireguard/wg0_publickey

# PC1
wg genkey | tee pc1_privatekey | wg pubkey > pc1_publickey
```

### 2. Install on VPS1

```bash
# Copy configs
scp configs/method-2/vps1/*.conf vps1:/etc/wireguard/

# Copy scripts
ssh vps1 "mkdir -p /etc/sdwan/scripts/method-2"
scp scripts/method-2/*.sh vps1:/etc/sdwan/scripts/method-2/
ssh vps1 "chmod +x /etc/sdwan/scripts/method-2/*.sh"

# Edit configs với actual keys
ssh vps1 "nano /etc/wireguard/wg0.conf"
ssh vps1 "nano /etc/wireguard/wg1.conf"

# Start WG interfaces
ssh vps1 "wg-quick up wg0 && wg-quick up wg1"

# Enable on boot
ssh vps1 "systemctl enable wg-quick@wg0 wg-quick@wg1"
```

### 3. Install on VPS2 (Exit Node)

```bash
# Copy config
scp configs/method-2/vps2/wg0.conf vps2:/etc/wireguard/

# Edit với actual keys
ssh vps2 "nano /etc/wireguard/wg0.conf"

# Start WG
ssh vps2 "wg-quick up wg0"

# Enable on boot
ssh vps2 "systemctl enable wg-quick@wg0"
```

### 4. Firewall

```bash
# VPS1
ssh vps1 "ufw allow 51820/udp comment 'WG-PC1'"
ssh vps1 "ufw allow 51821/udp comment 'WG-VPS2'"

# VPS2 không cần mở port (là client, không nhận incoming)
```

## Verification

```bash
# VPS1: Check cả 2 interfaces
ssh vps1 "wg show"
ssh vps1 "ip addr show wg0 wg1"

# VPS2: Check tunnel connected
ssh vps2 "wg show"
# Phải thấy: latest handshake, transfer bytes

# Test từ PC1
ping 10.10.0.1    # VPS1 wg0
ping 10.20.0.1    # VPS1 wg1
ping 10.20.0.2    # VPS2
curl ifconfig.me  # Phải hiện IP của VPS2 (103.109.187.179)
```

## Placeholders

Replace these values:

| Placeholder              | Location      | Description          |
| ------------------------ | ------------- | -------------------- |
| `<VPS1_WG0_PRIVATE_KEY>` | vps1/wg0.conf | wg0 private key      |
| `<VPS1_WG0_PUBLIC_KEY>`  | clients/      | wg0 public key       |
| `<VPS1_WG1_PRIVATE_KEY>` | vps1/wg1.conf | wg1 private key      |
| `<VPS1_WG1_PUBLIC_KEY>`  | vps2/wg0.conf | wg1 public key       |
| `<VPS2_WG0_PRIVATE_KEY>` | vps2/wg0.conf | VPS2 wg0 private key |
| `<VPS2_WG0_PUBLIC_KEY>`  | vps1/wg1.conf | VPS2 wg0 public key  |
| `<PC1_PRIVATE_KEY>`      | clients/      | PC1 private key      |
| `<PC1_PUBLIC_KEY>`       | vps1/wg0.conf | PC1 public key       |

## Troubleshooting

### VPS2 không kết nối được VPS1

```bash
# Check VPS1 đang listen port 51821
ssh vps1 "ss -ulnp | grep 51821"

# Check firewall VPS1
ssh vps1 "ufw status | grep 51821"

# Check từ VPS2
ssh vps2 "wg show"
# Nếu không có handshake → check keys, endpoint, firewall
```

### Traffic không đi qua VPS2

```bash
# Check routing trên VPS1
ssh vps1 "ip route show table 100"
ssh vps1 "ip rule show"

# Check NAT trên VPS2
ssh vps2 "iptables -t nat -L POSTROUTING -v"
```
