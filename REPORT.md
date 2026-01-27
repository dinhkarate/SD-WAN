# SD-WAN Method-2 Implementation Report

**Date:** 2026-01-28  
**Branch:** `lab-2-with-ip-method-2`  
**Status:** ✅ Completed & Verified

---

## Architecture

```
                         ┌─────────────────────────────────────┐
                         │            INTERNET                 │
                         └──────────▲─────────────▲────────────┘
                                    │             │
                              ┌─────┴─────┐ ┌─────┴─────┐
                              │  eth0     │ │   eth0    │
                              │103.109.   │ │103.109.   │
                              │187.182    │ │187.179    │
                         ┌────┴───────────┴─┴───────────┴────┐
                         │                                    │
┌──────────┐    wg0      │  ┌─────────┐   wg1   ┌─────────┐  │
│   PC     │────────────►│  │  VPS1   │────────►│  VPS2   │  │
│10.10.0.2 │             │  │10.10.0.1│         │10.20.0.1│  │
└──────────┘             │  └────┬────┘         └─────────┘  │
                         │       │                            │
                         │  ┌────▼────┐                       │
                         │  │ ipset   │                       │
                         │  │ fwmark  │                       │
                         │  │ routing │                       │
                         │  └────┬────┘                       │
                         │       │                            │
                         │  ┌────▼──────────────────────┐     │
                         │  │ Special IP? ──► eth0      │     │
                         │  │ Normal IP?  ──► wg1 ──► VPS2    │
                         │  └───────────────────────────┘     │
                         └────────────────────────────────────┘
```

---

## Components

### VPS1 (103.109.187.182)

| Interface | Purpose         | Subnet       |
| --------- | --------------- | ------------ |
| wg0       | Receive from PC | 10.10.0.0/24 |
| wg1       | Tunnel to VPS2  | 10.20.0.0/24 |

**Config Files:**

- `/etc/wireguard/wg0.conf` - PC connection endpoint
- `/etc/wireguard/wg1.conf` - VPS2 tunnel (Table = off)
- `/etc/sdwan/scripts/split-routing.sh` - Policy routing script
- `/etc/sdwan/special-ips.txt` - IPs for direct routing

### VPS2 (103.109.187.179)

| Interface | Purpose   | Subnet       |
| --------- | --------- | ------------ |
| wg0       | Exit node | 10.20.0.0/24 |

**Config Files:**

- `/etc/wireguard/wg0.conf` - Receives traffic from VPS1, NATs to internet

---

## Routing Logic

### Policy-Based Routing (VPS1)

| Traffic Type           | fwmark | Routing Table | Path                   |
| ---------------------- | ------ | ------------- | ---------------------- |
| Special IPs (in ipset) | 100    | table 100     | eth0 → Direct Internet |
| Normal IPs             | 200    | table 200     | wg1 → VPS2 → Internet  |

### Implementation Details

1. **ipset `special_ips`**: Hash set containing IPs for direct routing
2. **fwmark 100**: Traffic matching ipset gets marked
3. **fwmark 200**: All other traffic from wg0
4. **Table 100**: Routes via eth0 (direct)
5. **Table 200**: Routes via wg1 (to VPS2)

---

## Verification Results

### Traceroute Test

**Normal Path (8.8.8.8 - NOT in special_ips):**

```
Hop 1: 10.10.0.1   (VPS1 wg0)
Hop 2: 10.20.0.1   (VPS2 wg0) ← Goes through VPS2
Hop 3: 103.109.187.1 (VPS2 gateway)
...
```

**Direct Path (8.8.4.4 - IN special_ips):**

```
Hop 1: 10.10.0.1   (VPS1 wg0)
Hop 2: 103.109.187.1 (VPS1 gateway) ← Direct, NO VPS2
...
```

### Exit IP Verification

| Route Type | Exit IP         | VPS  |
| ---------- | --------------- | ---- |
| Normal     | 103.109.187.179 | VPS2 |
| Special    | 103.109.187.182 | VPS1 |

---

## Commands Reference

### Check Status

```bash
# WireGuard status
ssh vina7 "wg show"
ssh vina8 "wg show"

# Check ipset
ssh vina7 "ipset list special_ips"

# Check routing rules
ssh vina7 "ip rule show"
ssh vina7 "ip route show table 100"
ssh vina7 "ip route show table 200"
```

### Manage Special IPs

```bash
# Add IP to special list
ssh vina7 "echo '1.2.3.4/32' >> /etc/sdwan/special-ips.txt"

# Reload (zero downtime)
ssh vina7 "/etc/sdwan/scripts/split-routing.sh reload"

# Verify
ssh vina7 "ipset test special_ips 1.2.3.4"
```

### Test Routing

```bash
# From PC - test normal path
traceroute 8.8.8.8

# From PC - test special path (after adding IP)
traceroute <special-ip>
```

---

## Files Created

```
configs/method-2/
├── vps1/
│   ├── wg0.conf          # PC endpoint
│   └── wg1.conf          # VPS2 tunnel
├── clients/
│   ├── client-a.conf     # PC1 config
│   └── client-b.conf     # Client2 config
└── README.md             # Deployment guide

scripts/method-2/
└── routing-setup.sh      # Initial routing script

scripts/
└── cleanup-method1.sh    # Cleanup script for method-1
```

---

## Key Learnings

1. **`Table = off` in wg1.conf** - CRITICAL to prevent wg-quick from adding routes that break SSH
2. **FORWARD chain rules** - Must allow wg0 ↔ wg1 and wg0 ↔ eth0 traffic
3. **ipset atomic swap** - Zero downtime IP list updates
4. **fwmark + policy routing** - Keeps main routing table clean
5. **Start order matters** - VPS2 first, then VPS1 (wg1 before wg0)

---

## VPS Info

| Server | IP              | SSH         | Role                       |
| ------ | --------------- | ----------- | -------------------------- |
| VPS1   | 103.109.187.182 | `ssh vina7` | Entry point, split routing |
| VPS2   | 103.109.187.179 | `ssh vina8` | Exit node                  |

---

**Implementation:** Complete ✅  
**Verification:** Passed ✅  
**Split Routing:** Working ✅
