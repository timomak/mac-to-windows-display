# SSH and MCP Setup Guide

This guide covers setting up SSH connectivity between your Mac and Windows PC over the Thunderbolt Bridge, and configuring Cursor's MCP (Model Context Protocol) to run commands on Windows remotely.

## Overview

The setup creates:
1. **SSH server** on Windows (OpenSSH)
2. **SSH key pair** on Mac (passwordless auth)
3. **Host alias** (`blade18-tb`) for easy connection
4. **MCP configuration** for Cursor IDE

## Prerequisites

- ✅ Thunderbolt Bridge established (see [SETUP_THUNDERBOLT_BRIDGE.md](SETUP_THUNDERBOLT_BRIDGE.md))
- ✅ Both machines can ping each other
- ✅ Admin access on Windows

## Setup Order (IMPORTANT)

Follow these steps **in order**:

### Step 0: Verify Cable Connection

Before anything else, ensure the Thunderbolt link is working:

```bash
# On Mac
./scripts/check_link_mac.sh
```

```powershell
# On Windows
.\scripts\check_link_win.ps1
```

Both should show the interface, IP, and successful ping.

If ping fails, **STOP** and fix the link first. See [SETUP_THUNDERBOLT_BRIDGE.md](SETUP_THUNDERBOLT_BRIDGE.md).

### Step 1: Windows - Install OpenSSH Server

Open **PowerShell as Administrator** and run:

```powershell
.\scripts\01_setup_ssh_win.ps1
```

The script will:
1. Check for Admin privileges
2. Detect the Thunderbolt network adapter
3. Offer to set a static IP (recommended: 192.168.50.2)
4. Install OpenSSH Server if not present
5. Enable and start the sshd service
6. Open Windows Firewall for SSH (port 22)

**Expected output:**
```
[INFO] Detected Thunderbolt adapter: Thunderbolt Networking
[INFO] Current IP: 192.168.50.2
[INFO] OpenSSH Server installed
[INFO] sshd service started
[INFO] Firewall rule added

✅ SSH server ready!

Next: On Mac, run: ./scripts/01_setup_ssh_mac.sh
Windows IP for Mac script: 192.168.50.2
```

### Step 2: Mac - Configure SSH Key and Host

On Mac, run:

```bash
./scripts/01_setup_ssh_mac.sh
```

The script will prompt for:
- **Windows IP** (default: 192.168.50.2)
- **Windows username** (required - your Windows login name)
- **Set Mac static IP?** (recommended: 192.168.50.1)

The script will:
1. Verify Thunderbolt Bridge exists
2. Create SSH key pair (`~/.ssh/blade18_tb_ed25519`)
3. Add host alias to `~/.ssh/config`
4. Copy public key to Windows (you'll enter password once)
5. Test the connection

**Expected output:**
```
[INFO] Thunderbolt Bridge found with IP 192.168.50.1
[INFO] Creating SSH key...
[INFO] Adding host alias 'blade18-tb' to ~/.ssh/config
[INFO] Copying public key to Windows...
Password: (enter Windows password)
[INFO] Testing connection...

✅ SSH configured successfully!
You can now connect with: ssh blade18-tb
```

### Step 3: Mac - Verify SSH

Run the verification script:

```bash
./scripts/02_verify_ssh_mac.sh
```

**Expected output:**
```
[TEST] Running: ssh blade18-tb "whoami"
your_windows_username

[TEST] Running: ssh blade18-tb "powershell.exe -NoProfile -Command $PSVersionTable.PSVersion"
Major  Minor  Build  Revision
-----  -----  -----  --------
7      4      0      -1

✅ All SSH tests passed!
```

### Step 4: Mac - Configure Cursor MCP

Run the MCP configuration script:

```bash
./scripts/03_write_cursor_mcp_config.sh
```

The script will:
1. Verify SSH connectivity
2. Create `.cursor/mcp.json` with SSH MCP server config
3. Print next steps

**Expected output:**
```
[INFO] Verifying SSH connection...
[INFO] Creating .cursor/mcp.json...

✅ MCP configuration written!

Next steps:
1. Restart Cursor IDE
2. Open Cursor Settings → Features → MCP
3. Verify 'blade18-tb' server shows as connected
```

### Step 5: Verify in Cursor

1. Close and reopen Cursor
2. Open Settings (Cmd+,)
3. Go to Features → MCP Servers
4. You should see `blade18-tb` listed
5. The status should show "Connected" (green)

## SSH Config Reference

After setup, your `~/.ssh/config` will include:

```ssh-config
Host blade18-tb
    HostName 192.168.50.2
    User your_windows_username
    IdentityFile ~/.ssh/blade18_tb_ed25519
    IdentitiesOnly yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

## MCP Config Reference

The `.cursor/mcp.json` file:

```json
{
  "mcpServers": {
    "blade18-tb": {
      "command": "npx",
      "args": [
        "-y",
        "@aiondadotcom/mcp-ssh@latest"
      ]
    }
  }
}
```

## Troubleshooting

### "Connection refused" when SSHing

1. **Check sshd is running on Windows:**
   ```powershell
   Get-Service sshd
   # Should show Status: Running
   ```
   If stopped: `Start-Service sshd`

2. **Check firewall:**
   ```powershell
   Get-NetFirewallRule -DisplayName "*SSH*" | Select-Object DisplayName, Enabled
   ```

### "Permission denied (publickey)"

1. **Verify key was copied:**
   On Windows, check:
   ```powershell
   type $env:USERPROFILE\.ssh\authorized_keys
   ```
   Should contain a line starting with `ssh-ed25519 ...`

2. **Re-run key copy:**
   ```bash
   ssh-copy-id -i ~/.ssh/blade18_tb_ed25519.pub blade18-tb
   ```

### Wrong username

If you entered the wrong Windows username:

1. Edit `~/.ssh/config`
2. Change the `User` line under `Host blade18-tb`
3. Re-run `./scripts/02_verify_ssh_mac.sh`

### SSH works but MCP doesn't

1. **Check Node.js is installed:**
   ```bash
   node --version
   npx --version
   ```
   If not: `brew install node`

2. **Check MCP package availability:**
   ```bash
   npx -y @aiondadotcom/mcp-ssh@latest
   ```

3. **Try project-level config:**
   If Cursor doesn't detect `.cursor/mcp.json`, copy to global config:
   ```bash
   mkdir -p ~/.cursor
   cp .cursor/mcp.json ~/.cursor/mcp.json
   ```

### Windows OpenSSH installation fails

See [RUNBOOK.md](RUNBOOK.md) for manual installation steps.

## Manual SSH Test Commands

```bash
# Basic connection
ssh blade18-tb "whoami"

# Run PowerShell command
ssh blade18-tb "powershell.exe -NoProfile -Command 'Get-Date'"

# Check if a file exists
ssh blade18-tb "powershell.exe -NoProfile -Command 'Test-Path C:\Windows'"

# Run a script
ssh blade18-tb "powershell.exe -NoProfile -File C:\path\to\script.ps1"
```

## Security Notes

- SSH key is stored at `~/.ssh/blade18_tb_ed25519` (private) and `.pub` (public)
- Never commit the private key to git
- The connection is only accessible via the Thunderbolt cable (not internet-exposed)
- Consider adding a passphrase to the SSH key for additional security
