# Thunderbolt Bridge Setup

This guide explains how to establish a network connection between your Mac and Windows PC using a Thunderbolt cable.

## What is Thunderbolt Bridge?

When you connect two computers with a Thunderbolt cable, they can communicate over IP networking. This creates a dedicated, high-speed network link between the machines without needing a router or switch.

- **Bandwidth:** Up to 40 Gbps (Thunderbolt 3/4)
- **Latency:** Sub-millisecond (direct connection)
- **Use case:** Perfect for high-bandwidth streaming like screen mirroring

## Requirements

### Cable

You need a **Thunderbolt 3 or Thunderbolt 4** cable:
- USB-C connectors on both ends
- Must be Thunderbolt-certified (not just a USB-C cable)
- Length: 0.5m - 2m recommended (longer cables may reduce performance)

**How to identify a Thunderbolt cable:**
- Look for the ⚡ (lightning bolt) symbol
- Check packaging for "Thunderbolt 3" or "Thunderbolt 4"
- USB-only cables won't work for Thunderbolt Bridge

### Ports

| Machine | Port Requirement |
|---------|-----------------|
| Mac | Thunderbolt 3, Thunderbolt 4, or USB4 port |
| Windows | Thunderbolt 3, Thunderbolt 4, or USB4 port |

Most modern laptops with USB-C ports support Thunderbolt, but verify with your device specs.

## Step-by-Step Setup

### Step 1: Physical Connection

1. **Shut down** both machines (optional but recommended for first connection)
2. Plug one end of the Thunderbolt cable into the Mac
3. Plug the other end into the Windows PC
4. Boot both machines (if shut down)
5. Wait 10-15 seconds for the connection to establish

### Step 2: Verify on macOS

1. Open **System Settings** (or System Preferences on older macOS)
2. Go to **Network**
3. Look for **"Thunderbolt Bridge"** in the list of interfaces
4. It should show as "Connected" or have an IP address

**If you don't see it:**
- The interface might be disabled
- Click the `...` menu and select "Make Service Active"

### Step 3: Verify on Windows

1. Open **Settings → Network & Internet**
2. Look for a new network adapter:
   - "Thunderbolt Networking"
   - "USB4 Networking"
   - Or an unfamiliar "Ethernet" adapter
3. It should show as "Connected"

**Alternative: Device Manager**
1. Open Device Manager
2. Expand "Network adapters"
3. Look for "Thunderbolt" or "USB4" network adapter

### Step 4: Assign IP Addresses

For reliable connectivity, use static IPs instead of DHCP.

**Recommended IPs:**
| Machine | IP Address | Subnet Mask |
|---------|-----------|-------------|
| Mac | 192.168.50.1 | 255.255.255.0 (/24) |
| Windows | 192.168.50.2 | 255.255.255.0 (/24) |

#### On Mac

1. System Settings → Network → Thunderbolt Bridge
2. Click "Details..." (or select and click Advanced)
3. Go to TCP/IP tab
4. Change "Configure IPv4" to "Manually"
5. Enter:
   - IP Address: `192.168.50.1`
   - Subnet Mask: `255.255.255.0`
   - Router: (leave empty)
6. Click OK/Apply

**Or use the setup script:**
```bash
./scripts/01_setup_ssh_mac.sh
# It will offer to set the static IP
```

#### On Windows

1. Settings → Network & Internet → Ethernet (or Advanced network settings)
2. Find the Thunderbolt adapter
3. Click "Edit" next to IP assignment
4. Change to "Manual"
5. Enable IPv4 and enter:
   - IP address: `192.168.50.2`
   - Subnet prefix length: `24`
   - Gateway: (leave empty)
6. Click Save

**Or use the setup script (Admin PowerShell):**
```powershell
.\scripts\01_setup_ssh_win.ps1
# It will offer to set the static IP
```

### Step 5: Test Connectivity

**From Mac:**
```bash
ping 192.168.50.2
```

**From Windows (PowerShell):**
```powershell
ping 192.168.50.1
```

Both should show successful replies with <1ms latency.

## Troubleshooting

### "Thunderbolt Bridge" doesn't appear on Mac

1. **Check cable:** Ensure it's a genuine Thunderbolt cable (⚡ symbol)
2. **Try different port:** Some Macs have multiple Thunderbolt ports
3. **Check System Report:**
   - Apple menu → About This Mac → System Report → Thunderbolt
   - Should show connected device
4. **Restart:** Sometimes a reboot helps

### Windows doesn't detect the adapter

1. **Check Thunderbolt Software:** Some PCs need vendor Thunderbolt software
2. **Authorize connection:**
   - Open Intel Thunderbolt Control Center (if installed)
   - Approve the connection
3. **Driver issues:**
   - Device Manager → Check for driver updates
   - Look for errors (yellow triangle)

### Ping fails

1. **Check IPs:** Ensure both machines have IPs in the same subnet
2. **Firewall:**
   - Mac: System Settings → Network → Firewall → allow ICMP
   - Windows: May need to allow ICMP in Windows Firewall
3. **Wrong interface:** Ensure you're pinging via the Thunderbolt interface

### Connection drops randomly

1. **Cable quality:** Try a different (shorter) cable
2. **Power settings:** Disable USB/Thunderbolt power saving
3. **Heat:** Thunderbolt can throttle under high temps

## Performance Testing (Optional)

To verify you're getting good bandwidth:

### Install iperf3

**Mac:**
```bash
brew install iperf3
```

**Windows:**
Download from https://iperf.fr/iperf-download.php

### Run Test

**Windows (server):**
```powershell
iperf3 -s
```

**Mac (client):**
```bash
iperf3 -c 192.168.50.2
```

Expected: 10+ Gbps for Thunderbolt 3/4

## Next Steps

Once the Thunderbolt Bridge is working:
1. Run `./scripts/check_link_mac.sh` to verify
2. Proceed to SSH setup: `./scripts/01_setup_ssh_win.ps1` (Windows) and `./scripts/01_setup_ssh_mac.sh` (Mac)
