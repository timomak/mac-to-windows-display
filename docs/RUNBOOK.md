# Runbook

This document lists every permission prompt, manual step, and prerequisite needed to run ThunderMirror.

## Prerequisites

### Mac

| Requirement | How to Get It |
|-------------|---------------|
| macOS 13+ (Ventura) | System Settings → General → Software Update |
| Xcode Command Line Tools | `xcode-select --install` |
| Rust toolchain | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| Thunderbolt-capable port | Built into Mac |

### Windows

| Requirement | How to Get It |
|-------------|---------------|
| Windows 10/11 | Windows Update |
| Thunderbolt/USB4 port | Built into laptop (e.g., Razer Blade) |
| Visual Studio 2022 | https://visualstudio.microsoft.com/ (Community edition, free) |
| C++ workload | VS Installer → Modify → Desktop development with C++ |
| Rust toolchain | https://rustup.rs |
| Admin access | For OpenSSH installation and firewall rules |

### Hardware

| Item | Notes |
|------|-------|
| Thunderbolt 3/4 cable | USB-C on both ends, must be Thunderbolt-certified |

---

## One-Time Setup Steps

### 1. Connect the Cable

1. Plug Thunderbolt cable into Mac
2. Plug other end into Windows PC
3. Wait 5-10 seconds for interfaces to appear

**Verification:**
- Mac: System Settings → Network → Should see "Thunderbolt Bridge"
- Windows: Settings → Network → Should see "Thunderbolt Networking" or "Ethernet" adapter

### 2. Windows: Install OpenSSH Server

Run in **elevated (Admin) PowerShell**:

```powershell
.\scripts\01_setup_ssh_win.ps1
```

**Prompts you'll see:**
- "Set static IP?" - Recommended: Yes, use 192.168.50.2
- UAC prompt for Admin elevation (if not already elevated)

**What it does:**
1. Detects Thunderbolt network adapter
2. Optionally sets static IP
3. Installs OpenSSH Server feature
4. Enables and starts sshd service
5. Opens firewall for port 22

### 3. Mac: Configure SSH Key and Host

Run in Terminal:

```bash
./scripts/01_setup_ssh_mac.sh
```

**Prompts you'll see:**
- "Windows Thunderbolt IP?" - Default: 192.168.50.2
- "Windows username?" - Required, enter your Windows username
- "Set static IP on Mac?" - Recommended: Yes, use 192.168.50.1
- SSH password prompt (once, to copy key)

**What it does:**
1. Creates SSH key pair
2. Configures ~/.ssh/config with host alias
3. Copies public key to Windows

### 4. Mac: Verify SSH Connection

```bash
./scripts/02_verify_ssh_mac.sh
```

Should show your Windows username and PowerShell version.

### 5. Mac: Configure Cursor MCP

```bash
./scripts/03_write_cursor_mcp_config.sh
```

Then restart Cursor IDE.

---

## Runtime Permissions

### macOS Screen Recording Permission (Phase 2+)

When you first run the Mac sender with real capture:

1. A system dialog appears: "ThunderMirror would like to record this computer's screen"
2. Click "Open System Settings"
3. In Privacy & Security → Screen Recording, toggle ON for ThunderMirror
4. Restart the app

**To reset (for testing):**
```bash
tccutil reset ScreenCapture com.thundermirror.ThunderMirror
```

### Windows Firewall (Receiver)

The receiver needs inbound connections. The setup script opens port 22 for SSH.

For the actual streaming (Phase 1+), you may see:
1. Windows Firewall dialog when running the receiver
2. Click "Allow" for Private networks

---

## Manual Fallbacks

### If OpenSSH Installation Fails on Windows

1. Open Settings → Apps → Optional Features
2. Click "Add a feature"
3. Search for "OpenSSH Server"
4. Click Install
5. Open Services (services.msc)
6. Find "OpenSSH SSH Server"
7. Set Startup Type to "Automatic"
8. Click Start

### If SSH Key Push Fails

Manually copy the key:

**On Mac:**
```bash
cat ~/.ssh/blade18_tb_ed25519.pub
```

**On Windows (create .ssh folder if needed):**
```powershell
mkdir $env:USERPROFILE\.ssh -Force
notepad $env:USERPROFILE\.ssh\authorized_keys
# Paste the public key, save
```

### If Thunderbolt Bridge Doesn't Appear

1. Disconnect and reconnect the cable
2. Try a different port on each machine
3. Verify the cable is Thunderbolt-certified (not just USB-C)
4. On Windows: Check Device Manager for Thunderbolt controller
5. On Mac: System Report → Thunderbolt → Check connection

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `THUNDER_WIN_IP` | 192.168.50.2 | Windows Thunderbolt IP |
| `THUNDER_MAC_IP` | 192.168.50.1 | Mac Thunderbolt IP |
| `THUNDER_LOG_LEVEL` | info | Logging verbosity (debug/info/warn/error) |

---

## Logs Location

- **Mac:** `./logs/mac_sender_*.log`
- **Windows:** `./logs/win_receiver_*.log`

Logs include timestamps, phase, and detailed error messages.
