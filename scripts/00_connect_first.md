# Connect First Checklist

Before running any scripts, ensure the Thunderbolt cable is connected and the network link is established.

## Step 1: Physical Connection

1. [ ] Get a **Thunderbolt 3 or Thunderbolt 4 cable** (USB-C connectors, ⚡ symbol)
2. [ ] Plug one end into your **Mac**
3. [ ] Plug the other end into your **Windows PC**
4. [ ] Wait **10-15 seconds** for the interfaces to appear

## Step 2: Verify on Mac

1. [ ] Open **System Settings → Network**
2. [ ] Look for **"Thunderbolt Bridge"** interface
3. [ ] It should show "Connected" or have an IP address

**If you don't see it:**
- Try a different Thunderbolt port on the Mac
- Verify the cable is Thunderbolt-certified (not just USB-C)
- Check Apple menu → About This Mac → System Report → Thunderbolt

## Step 3: Verify on Windows

1. [ ] Open **Settings → Network & Internet**
2. [ ] Look for a new adapter:
   - "Thunderbolt Networking"
   - "USB4 Networking"  
   - Or a new "Ethernet" adapter
3. [ ] It should show "Connected"

**If you don't see it:**
- Check Device Manager for Thunderbolt controller
- Some PCs need vendor Thunderbolt software (Intel Thunderbolt Control Center)
- May need to "Authorize" the connection in Thunderbolt software

## Step 4: Run Link Check Scripts

**On Mac (Terminal):**
```bash
./scripts/check_link_mac.sh
```

**On Windows (PowerShell):**
```powershell
.\scripts\check_link_win.ps1
```

Both scripts should:
- ✅ Detect the Thunderbolt interface
- ✅ Show an IP address
- ✅ Ping the other machine successfully

## Step 5: If Ping Fails - STOP HERE

Do NOT proceed to SSH setup until ping works in both directions.

**Common fixes:**
1. Set static IPs (recommended):
   - Mac: 192.168.50.1 / 255.255.255.0
   - Windows: 192.168.50.2 / 255.255.255.0

2. Check firewalls:
   - Windows may block ICMP by default
   - Run as Admin: `New-NetFirewallRule -DisplayName "Allow ICMPv4" -Protocol ICMPv4 -IcmpType 8 -Action Allow`

3. Verify correct interface:
   - Ensure ping is using Thunderbolt, not WiFi

## Next Steps

Once ping works in both directions, proceed to:

1. **Windows (Admin PowerShell):** `.\scripts\01_setup_ssh_win.ps1`
2. **Mac:** `./scripts/01_setup_ssh_mac.sh`

See [docs/SSH_MCP_SETUP.md](../docs/SSH_MCP_SETUP.md) for full instructions.
