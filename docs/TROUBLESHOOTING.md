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
- Mac → Windows fails, but Windows → Mac works

**Solutions:**

1. **Verify IP addresses are in same subnet:**
   - Mac: 192.168.50.1/24
   - Windows: 192.168.50.2/24
   - Both masks: 255.255.255.0

2. **⚠️ IMPORTANT: Thunderbolt adapters often get "Public" network profile!**
   
   Windows assigns new adapters to "Public" by default, which has stricter firewall rules:
   
   ```powershell
   # Check the network profile
   Get-NetConnectionProfile | Where-Object InterfaceAlias -match "Ethernet|Thunderbolt"
   
   # If NetworkCategory shows "Public", add ICMP rule for all profiles:
   New-NetFirewallRule -Name "ThunderMirror-ICMP" `
       -DisplayName "ThunderMirror ICMP Allow" `
       -Enabled True -Direction Inbound -Protocol ICMPv4 `
       -IcmpType 8 -RemoteAddress 192.168.50.0/24 `
       -Action Allow -Profile Any
   ```

3. **Standard ICMP rule (may not work for Public profile):**
   ```powershell
   # Allow ICMP (ping) - works for Private/Domain profiles
   New-NetFirewallRule -DisplayName "Allow ICMPv4" -Protocol ICMPv4 -IcmpType 8 -Action Allow
   ```

4. **Check macOS Firewall:**
   - System Settings → Network → Firewall
   - Ensure ICMP isn't blocked

5. **Verify correct interface:**
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
   Get-NetFirewallRule -DisplayName "*SSH*" | Format-Table DisplayName, Enabled, Profile
   ```
   If not present, add:
   ```powershell
   New-NetFirewallRule -Name "OpenSSH-Server" -DisplayName "OpenSSH SSH Server" -Protocol TCP -LocalPort 22 -Action Allow
   ```

4. **⚠️ IMPORTANT: Default SSH rule only covers "Private" profile!**
   
   Since Thunderbolt adapters often get assigned "Public" profile, you may need an additional rule:
   
   ```powershell
   # Add SSH rule specifically for Public profile
   New-NetFirewallRule -Name "OpenSSH-Server-Public" `
       -DisplayName "OpenSSH SSH Server (Public)" `
       -Enabled True -Direction Inbound -Protocol TCP `
       -Action Allow -LocalPort 22 -Profile Public
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

2. **⚠️ IMPORTANT: Admin users need different authorized_keys file!**
   
   If your Windows user is a member of the Administrators group, OpenSSH ignores `%USERPROFILE%\.ssh\authorized_keys` and uses a system-wide file instead:
   
   ```powershell
   # Check if you're an admin
   net localgroup Administrators | findstr /i "$env:USERNAME"
   
   # If yes, add key to the admin file instead:
   $key = "ssh-ed25519 AAAA... your-key-here"
   Add-Content -Path "C:\ProgramData\ssh\administrators_authorized_keys" -Value $key
   
   # Fix permissions on admin file
   icacls "C:\ProgramData\ssh\administrators_authorized_keys" /inheritance:r
   icacls "C:\ProgramData\ssh\administrators_authorized_keys" /grant "SYSTEM:(R)"
   icacls "C:\ProgramData\ssh\administrators_authorized_keys" /grant "Administrators:(R)"
   
   # Restart SSH
   Restart-Service sshd
   ```

3. **For non-admin users, verify key is in Windows authorized_keys:**
   ```powershell
   type $env:USERPROFILE\.ssh\authorized_keys
   ```
   Should contain a line starting with `ssh-ed25519 AAAA...`

4. **Re-copy the key:**
   ```bash
   ssh-copy-id -i ~/.ssh/blade18_tb_ed25519.pub blade18-tb
   ```
   Or manually:
   ```bash
   cat ~/.ssh/blade18_tb_ed25519.pub | ssh user@192.168.50.2 "mkdir -p .ssh && cat >> .ssh/authorized_keys"
   ```

5. **Check Windows permissions (for non-admin users):**
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

### "'export' is not recognized" error on connect

**Symptoms:**
```
'export' is not recognized as an internal or external command,
operable program or batch file.
Connection to 192.168.50.2 closed.
```

**Explanation:**
This is harmless. Windows OpenSSH defaults to `cmd.exe` as the shell, and your Mac terminal is sending bash initialization commands that cmd.exe doesn't understand.

**Solutions:**

1. **Run commands explicitly with powershell.exe:**
   ```bash
   ssh blade18-tb "powershell.exe -Command Get-Date"
   ```

2. **Or change Windows default shell to PowerShell:**
   ```powershell
   # Run as Admin on Windows
   New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
   Restart-Service sshd
   ```

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
- Error message: `Screen Recording permission denied. Please grant access in System Preferences > Privacy & Security > Screen Recording`

**Understanding the Permission:**
macOS requires explicit user consent for screen capture. When ThunderMirror first tries to capture the screen, macOS will display a permission prompt. The app cannot capture anything until you grant access.

**Solution:**

1. **If prompted automatically:**
   - Click "Open System Settings" when the dialog appears
   - Toggle ThunderMirror ON in the list
   - If ThunderMirror doesn't appear, make sure the app has attempted capture at least once

2. **To grant permission manually:**
   - Open **System Settings** (or System Preferences on older macOS)
   - Navigate to **Privacy & Security → Screen Recording**
   - Find **ThunderMirror** in the list
   - Toggle it **ON**
   - You may need to unlock the padlock (🔒) first

3. **If the app doesn't appear in the list:**
   - Run ThunderMirror once (it will fail but register itself)
   - Then check System Settings again

4. **After granting permission:**
   - Quit ThunderMirror completely
   - Restart the app
   - Permission should now work

**To test with the fallback mode:**
```bash
# Use test pattern mode (no permission required)
cd mac && .build/debug/ThunderMirror --test-pattern -t 192.168.50.2
```

**To reset permission for testing:**
```bash
# Reset Screen Recording permission for Terminal (if running from terminal)
tccutil reset ScreenCapture com.apple.Terminal

# Or for the built app specifically
tccutil reset ScreenCapture com.thundermirror.sender
```

**Note:** After resetting, you'll need to grant permission again when the app next runs.

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
   npx -y @aiondadotcom/mcp-ssh@latest
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
