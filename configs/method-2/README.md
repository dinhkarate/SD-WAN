# Method-2: Dual WireGuard Servers on Single VPS

## Architecture

```
                    ┌─────────────────┐
                    │  Internet (ALL) │
                    └────────▲────────┘
                             │ eth0
┌──────────┐    wg0   ┌──────┴───────┐
│   PC1    │─────────►│    WG-A      │ VPS1 (103.109.187.182)
└──────────┘  :51820  │  10.10.0.1   │
                      └──────────────┘

┌──────────┐    wg1   ┌──────────────┐
│ Client2  │─────────►│    WG-B      │ VPS1 (103.109.187.182)
└──────────┘  :51821  │  10.20.0.1   │
                      └──────┬───────┘
                             │
                      (Split routing available)
```

## Components

| File                                      | Purpose                                              |
| ----------------------------------------- | ---------------------------------------------------- |
| `vps1/wg0.conf`                           | WG-A server config (port 51820, subnet 10.10.0.0/24) |
| `vps1/wg1.conf`                           | WG-B server config (port 51821, subnet 10.20.0.0/24) |
| `clients/client-a.conf`                   | PC1 client config                                    |
| `clients/client-b.conf`                   | Client2 config                                       |
| `../../scripts/method-2/routing-setup.sh` | Policy routing script                                |

## Key Features

1. **Two independent WG servers** on same VPS (different ports)
2. **Separate subnets** for each server
3. **Split routing** via ipset + fwmark (from method-1)
4. **Shared routing rules** - both servers use same special_ips list

## Deployment

### 1. Generate Keys

```bash
# On VPS1 - for wg0
wg genkey | tee /etc/wireguard/wg0_privatekey | wg pubkey > /etc/wireguard/wg0_publickey

# On VPS1 - for wg1
wg genkey | tee /etc/wireguard/wg1_privatekey | wg pubkey > /etc/wireguard/wg1_publickey

# On PC1
wg genkey | tee pc1_privatekey | wg pubkey > pc1_publickey

# On Client2
wg genkey | tee client2_privatekey | wg pubkey > client2_publickey
```

### 2. Install on VPS1

```bash
# Copy configs
scp configs/method-2/vps1/*.conf vina7:/etc/wireguard/

# Copy scripts
ssh vina7 "mkdir -p /etc/sdwan/scripts/method-2"
scp scripts/method-2/*.sh vina7:/etc/sdwan/scripts/method-2/
ssh vina7 "chmod +x /etc/sdwan/scripts/method-2/*.sh"

# Edit configs with actual keys
ssh vina7 "nano /etc/wireguard/wg0.conf"
ssh vina7 "nano /etc/wireguard/wg1.conf"

# Start WG interfaces
ssh vina7 "wg-quick up wg0"
ssh vina7 "wg-quick up wg1"

# Enable on boot
ssh vina7 "systemctl enable wg-quick@wg0 wg-quick@wg1"
```

### 3. Configure Special IPs (optional)

```bash
# Create IP list
ssh vina7 "cat > /etc/sdwan/special-ips.txt << 'EOF'
# Special IPs that should go direct (not via VPN)
8.8.8.8/32
1.1.1.1/32
# Add your IPs here
EOF"

# Reload (zero downtime)
ssh vina7 "/etc/sdwan/scripts/method-2/routing-setup.sh reload"
```

## Verification

```bash
# Check WG status
ssh vina7 "wg show"

# Check both interfaces are up
ssh vina7 "ip addr show wg0 wg1"

# Check routing rules
ssh vina7 "ip rule show"
ssh vina7 "ip route show table 100"

# Check ipset
ssh vina7 "ipset list special_ips | head -20"

# Test from client
traceroute 8.8.8.8   # Should go via eth0 if in special_ips
traceroute 1.2.3.4   # Should go via normal route
```

## Firewall

```bash
# Allow WG ports
ssh vina7 "ufw allow 51820/udp comment 'WG-A'"
ssh vina7 "ufw allow 51821/udp comment 'WG-B'"
```

## Placeholders

Replace these values:

- `<VPS1_WG0_PRIVATE_KEY>` - wg0 private key
- `<VPS1_WG0_PUBLIC_KEY>` - wg0 public key
- `<VPS1_WG1_PRIVATE_KEY>` - wg1 private key
- `<VPS1_WG1_PUBLIC_KEY>` - wg1 public key
- `<PC1_PRIVATE_KEY>` / `<PC1_PUBLIC_KEY>` - PC1 keys
- `<CLIENT2_PRIVATE_KEY>` / `<CLIENT2_PUBLIC_KEY>` - Client2 keys
