# SD-WAN Lab 3 — Split Routing China IP

PC connects to DO2 (Singapore). DO2 checks destination:

- **China IPs** → forward to fominet (Vietnam) → exit with Vietnam IP
- **Everything else** → exit directly from DO2 (Singapore IP)

## Architecture

```
                          ┌──────────────────┐
                     ┌───►│    fominet       │───► Internet (Vietnam ISP)
                     │    │    OpenWRT       │
                     │    │    Việt Nam      │
                     │    └──────────────────┘
                     │    China IPs only
                     │
┌──────────┐    ┌────┴──────────┐
│   PC     │───►│     DO2       │
│  vina7   │    │  Singapore    │
│  Client  │    │  (Hub)        │
└──────────┘    └────┬──────────┘
                     │
                     │    Everything else
                     │
                     └───► Internet (Singapore, DigitalOcean)
```

## Devices

| Name        | Role            | IP                  | WireGuard |
| ----------- | --------------- | ------------------- | --------- |
| **DO2**     | Hub + Router    | 152.42.238.137      | wg0 + wg1 |
| **fominet** | China exit node | thatnghiep.ddns.net | wg1       |
| **PC**      | Client (vina7)  | 103.109.187.182     | wg0       |

## Tunnels

```
PC ◄──── wg0 (port 51820) ────► DO2 ◄──── wg1 (port 51821) ────► fominet

  10.10.0.3                    10.10.0.1   10.20.0.1              10.20.0.2
```

- **wg0**: PC ↔ DO2 — all PC traffic enters here
- **wg1**: DO2 ↔ fominet — China-bound traffic only

## How Split Routing Works

DO2 maintains a list of ~3,500 China IP ranges. When a packet arrives from PC:

1. Check destination IP against China IP list
2. **Match** → send through wg1 → fominet → Vietnam ISP
3. **No match** → send through eth0 → DO2 Singapore

## Project Structure

```
configs/method-2/
├── do2/
│   ├── wg0.conf           # PC-facing server (port 51820)
│   └── wg1.conf           # Tunnel to fominet (port 51821)
├── fominet/
│   ├── wg1.conf           # Reference config
│   └── setup-uci.sh       # OpenWRT UCI setup script
├── pc0/wg0.conf           # vina7 client config
├── pc1/wg0.conf           # PC1 client template
└── README.md              # Detailed deploy guide

scripts/method-2/
├── routing-setup.sh       # China IP list + routing rules (runs on DO2)
├── deploy-do2.sh          # Auto-deploy DO2
├── deploy-fominet.sh      # Auto-deploy fominet
├── deploy-all.sh          # Deploy everything
└── generate-pc1-config.sh # Generate PC1 config
```

## Quick Start

### Deploy

```bash
./scripts/method-2/deploy-all.sh
```

Or manually: see [`configs/method-2/README.md`](configs/method-2/README.md)

Deploy order: fominet → DO2 → exchange keys → PC

### Test

```bash
# On PC after connecting wg0:
curl ifconfig.me          # Should show 152.42.238.137 (DO2)
traceroute 8.8.8.8       # Should go through DO2 (Singapore)
traceroute 223.5.5.5     # Should go through fominet (Vietnam)
```

## Manage China IPs

```bash
ssh do2 "/etc/sdwan/routing-setup.sh status"
ssh do2 "/etc/sdwan/routing-setup.sh reload"
ssh do2 "ipset test china_ips 223.5.5.5"
ssh do2 "ipset add china_ips 119.29.29.29/32"
```

## Troubleshooting

| Problem                   | Check                                      |
| ------------------------- | ------------------------------------------ |
| PC can't connect          | `wg show wg0` on DO2, firewall port 51820  |
| China traffic not via VN  | `ipset test china_ips <ip>`, `wg show wg1` |
| DO2 ↔ fominet tunnel down | `ping 10.20.0.2` from DO2                  |
| No internet               | `iptables -t nat -L POSTROUTING` on DO2    |

## Docs

- [`configs/method-2/README.md`](configs/method-2/README.md) — Detailed deploy guide
- [`REPORT.md`](REPORT.md) — Test results report
