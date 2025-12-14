# Troubleshooting Guide

This guide covers common issues and their solutions.

## Quick Diagnostics

Run these commands to identify issues:

**Mac:**
```bash
./scripts/check_link_mac.sh
./scripts/02_verify_ssh_mac.sh
```

**Windows (PowerShell):**
```powershell
.\scripts\check_link_win.ps1
```

---

## Connection Issues

### Thunderbolt Bridge not appearing on Mac

**Symptoms:**
- No "Thunderbolt Bridge" in Network preferences
- `check_link_mac.sh` fails to find interface

**Solutions:**

1. **Verify cable is Thunderbolt:**
   - Look for ⚡ symbol on cable
   - USB-C cables without Thunderbolt won't work

2. **Try different port:**
   - Some Macs have multiple TB ports
   - Try each one

3. **Check System Report:**
   ```bash
   system_profiler SPThunderboltDataType
   ```
   Should show connected device.

4. **Reboot both machines:**
   - With cable connected
   - Wait 30 seconds after boot

5. **Create interface manually:**
   - System Settings → Network → + → Thunderbolt Bridge

### Windows doesn't detect Thunderbolt adapter

**Symptoms:**
- No new network adapter appears
- `check_link_win.ps1` fails

**Solutions:**

1. **Check Thunderbolt software:**
   - Some PCs need vendor Thunderbolt Control Center
   - For Razer: Check Razer Synapse or Intel Thunderbolt app

2. **Authorize connection:**
   - Intel Thunderbolt Control Center → Approve device
   - May need to set to "Always Connect"

3. **Update drivers:**
   - Device Manager → Right-click Thunderbolt controller → Update driver

4. **Check Device Manager for errors:**
   - Look for yellow triangles on Thunderbolt devices

### Ping fails between machines

**Symptoms:**
- Link scripts show interfaces but ping times out
- `Request timed out` or `Destination host unreachable`

**Solutions:**

1. **Verify IP addresses are in same subnet:**
   - Mac: 192.168.50.1/24
   - Windows: 192.168.50.2/24
   - Both masks: 255.255.255.0

2. **Check Windows Firewall:**
   ```powershell
   # Allow ICMP (ping)
   New-NetFirewallRule -DisplayName "Allow ICMPv4" -Protocol ICMPv4 -IcmpType 8 -Action Allow
   ```

3. **Check macOS Firewall:**
   - System Settings → Network → Firewall
   - Ensure ICMP isn't blocked

4. **Verify correct interface:**
   - Make sure you're not pinging via WiFi/Ethernet accidentally

---

## SSH Issues

### "Connection refused" on port 22

**Symptoms:**
```
ssh: connect to host 192.168.50.2 port 22: Connection refused
```

**Solutions:**

1. **Check sshd is running on Windows:**
   ```powershell
   Get-Service sshd
   ```
   If stopped:
   ```powershell
   Start-Service sshd
   ```

2. **Check sshd is enabled:**
   ```powershell
   Set-Service -Name sshd -StartupType Automatic
   ```

3. **Check firewall allows SSH:**
   ```powershell
   Get-NetFirewallRule -DisplayName "*SSH*" | Format-Table DisplayName, Enabled
   ```
   If not present, add:
   ```powershell
   New-NetFirewallRule -Name "OpenSSH-Server" -DisplayName "OpenSSH SSH Server" -Protocol TCP -LocalPort 22 -Action Allow
   ```

### "Permission denied (publickey)"

**Symptoms:**
```
Permission denied (publickey,keyboard-interactive).
```

**Solutions:**

1. **Verify key exists on Mac:**
   ```bash
   ls -la ~/.ssh/blade18_tb_ed25519*
   ```

2. **Verify key is in Windows authorized_keys:**
   ```powershell
   type $env:USERPROFILE\.ssh\authorized_keys
   ```
   Should contain a line starting with `ssh-ed25519 AAAA...`

3. **Re-copy the key:**
   ```bash
   ssh-copy-id -i ~/.ssh/blade18_tb_ed25519.pub blade18-tb
   ```
   Or manually:
   ```bash
   cat ~/.ssh/blade18_tb_ed25519.pub | ssh user@192.168.50.2 "mkdir -p .ssh && cat >> .ssh/authorized_keys"
   ```

4. **Check Windows permissions:**
   For OpenSSH on Windows, `authorized_keys` must have correct permissions:
   ```powershell
   icacls $env:USERPROFILE\.ssh\authorized_keys /inheritance:r
   icacls $env:USERPROFILE\.ssh\authorized_keys /grant:r "$($env:USERNAME):(R)"
   ```

### SSH hangs / very slow

**Symptoms:**
- SSH connection takes 30+ seconds
- Commands hang

**Solutions:**

1. **DNS lookup delay:**
   Add to Windows sshd_config (`C:\ProgramData\ssh\sshd_config`):
   ```
   UseDNS no
   ```
   Restart sshd:
   ```powershell
   Restart-Service sshd
   ```

2. **Wrong interface being used:**
   Verify you're connecting via Thunderbolt IP, not WiFi

---

## Build Issues

### Swift build fails on Mac

**Symptoms:**
```
error: unable to find sdk 'macosx'
```

**Solution:**
```bash
xcode-select --install
# Or if Xcode is installed:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### Rust build fails

**Symptoms:**
```
error: linker `cc` not found
```

**Solutions:**

**Mac:**
```bash
xcode-select --install
```

**Windows:**
- Install Visual Studio 2022 with "Desktop development with C++"

### Missing dependencies

**Rust (shared crate):**
```bash
cd shared
cargo build 2>&1 | grep "could not find"
```

Check `Cargo.toml` has all required dependencies.

---

## Runtime Issues

### Screen Recording permission denied (Mac)

**Symptoms:**
- Black/empty capture
- "Screen recording permission required" error

**Solution:**
1. System Settings → Privacy & Security → Screen Recording
2. Find ThunderMirror and toggle ON
3. Restart the app

**To reset for testing:**
```bash
tccutil reset ScreenCapture com.yourcompany.ThunderMirror
```

### Receiver shows black screen

**Symptoms:**
- Windows app runs but shows only black
- Mac is sending frames

**Solutions:**

1. **Check logs:**
   Look at `logs/win_receiver_*.log` for decode errors

2. **GPU driver issue:**
   - Update graphics drivers
   - Try software rendering (if option exists)

3. **Resolution mismatch:**
   - Mac resolution might be unsupported
   - Try setting Mac to a standard resolution (1920x1080)

### Poor performance / low FPS

**Symptoms:**
- Stats show <30 FPS
- Visible stuttering

**Solutions:**

1. **Check bandwidth:**
   ```bash
   iperf3 -c 192.168.50.2 -t 10
   ```
   Should be >1 Gbps

2. **Reduce resolution:**
   - Lower Mac display resolution
   - Or add a scaling option (future)

3. **Check CPU/GPU usage:**
   - Mac: Activity Monitor
   - Windows: Task Manager
   - High CPU might indicate software fallback instead of HW acceleration

4. **Cable quality:**
   - Try a shorter cable
   - Try a certified Thunderbolt 4 cable

### High latency

**Symptoms:**
- Visible delay between action and display
- Stats show >50ms latency

**Solutions:**

1. **Ensure hardware acceleration:**
   - VideoToolbox on Mac
   - Media Foundation on Windows
   - Check logs for "HW" vs "SW" encoder

2. **Reduce encoder latency settings:**
   - Ultra-low latency mode
   - No B-frames
   - Short GOP

3. **Check network:**
   ```bash
   ping 192.168.50.2
   ```
   Should be <1ms

---

## MCP Issues

### Cursor doesn't detect MCP config

**Symptoms:**
- MCP server not listed in Cursor settings
- `.cursor/mcp.json` exists but ignored

**Solutions:**

1. **Restart Cursor completely:**
   - Quit Cursor
   - Wait 5 seconds
   - Reopen

2. **Check JSON syntax:**
   ```bash
   cat .cursor/mcp.json | python3 -m json.tool
   ```
   Any error means invalid JSON.

3. **Try global config:**
   ```bash
   mkdir -p ~/.cursor
   cp .cursor/mcp.json ~/.cursor/mcp.json
   ```

4. **Verify Node.js:**
   ```bash
   npx --version
   ```
   Should return a version. If not: `brew install node`

### MCP shows disconnected

**Symptoms:**
- Server listed but shows red/disconnected

**Solutions:**

1. **Verify SSH works:**
   ```bash
   ssh blade18-tb "whoami"
   ```

2. **Check MCP package:**
   ```bash
   npx -y @anthropic/mcp-ssh@latest --help
   ```

3. **Check Cursor logs:**
   - Help → Toggle Developer Tools → Console
   - Look for MCP-related errors

---

## Getting Help

If none of the above solutions work:

1. **Collect diagnostics:**
   ```bash
   # Mac
   ./scripts/check_link_mac.sh > diag_mac.txt 2>&1
   
   # Windows
   .\scripts\check_link_win.ps1 > diag_win.txt 2>&1
   ```

2. **Collect logs:**
   - Copy files from `logs/` folder

3. **System info:**
   ```bash
   # Mac
   sw_vers
   system_profiler SPThunderboltDataType
   
   # Windows (PowerShell)
   winver
   Get-ComputerInfo | Select-Object OsName, OsVersion
   ```

4. **Open an issue** with:
   - Steps to reproduce
   - Expected vs actual behavior
   - Diagnostic output
   - Log files
   - System information
