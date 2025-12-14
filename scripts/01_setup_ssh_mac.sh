#!/bin/bash
#
# 01_setup_ssh_mac.sh - Set up SSH key and host alias for Windows connection
#
# This script:
# 1. Verifies Thunderbolt Bridge exists
# 2. Prompts for Windows IP and username
# 3. Optionally sets static IP on Mac
# 4. Creates SSH key pair
# 5. Configures ~/.ssh/config with host alias
# 6. Copies public key to Windows
# 7. Tests the connection
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Defaults
DEFAULT_WIN_IP="192.168.50.2"
DEFAULT_MAC_IP="192.168.50.1"
SSH_KEY_PATH="$HOME/.ssh/blade18_tb_ed25519"
SSH_HOST_ALIAS="blade18-tb"

echo "========================================"
echo "ThunderMirror - Mac SSH Setup"
echo "========================================"
echo ""

# Step 1: Check Thunderbolt Bridge
echo "[1/6] Checking Thunderbolt Bridge..."

TB_INTERFACE=""
TB_IP=""

# Find Thunderbolt interface
if networksetup -listallnetworkservices 2>/dev/null | grep -qi "thunderbolt"; then
    TB_SERVICE=$(networksetup -listallnetworkservices | grep -i "thunderbolt" | head -1)
    TB_INTERFACE=$(networksetup -listallhardwareports | grep -A1 "$TB_SERVICE" | grep "Device:" | awk '{print $2}')
fi

# Try to find by interface
if [ -z "$TB_INTERFACE" ]; then
    for iface in bridge0 bridge1 en5 en6 en7 en8 en9; do
        if ifconfig "$iface" 2>/dev/null | grep -q "inet "; then
            if networksetup -listallhardwareports 2>/dev/null | grep -B1 "$iface" | grep -qi "thunderbolt\|bridge"; then
                TB_INTERFACE="$iface"
                break
            fi
        fi
    done
fi

if [ -z "$TB_INTERFACE" ]; then
    echo -e "      ${RED}FAIL: No Thunderbolt Bridge interface found${NC}"
    echo ""
    echo "      Please ensure:"
    echo "      1. Thunderbolt cable is connected"
    echo "      2. Follow scripts/00_connect_first.md"
    echo ""
    exit 1
fi

# Get current IP
TB_IP=$(ifconfig "$TB_INTERFACE" 2>/dev/null | grep "inet " | awk '{print $2}' | head -1)
if [ -n "$TB_IP" ]; then
    echo -e "      ${GREEN}OK: Found $TB_INTERFACE with IP $TB_IP${NC}"
else
    echo -e "      ${YELLOW}WARNING: $TB_INTERFACE has no IP address${NC}"
fi

# Step 2: Get Windows info
echo ""
echo "[2/6] Windows connection details..."
echo ""

read -p "      Windows Thunderbolt IP [$DEFAULT_WIN_IP]: " WIN_IP
WIN_IP="${WIN_IP:-$DEFAULT_WIN_IP}"

read -p "      Windows username (required): " WIN_USER
if [ -z "$WIN_USER" ]; then
    echo -e "      ${RED}ERROR: Username is required${NC}"
    exit 1
fi

# Step 3: Set Mac static IP (optional)
echo ""
echo "[3/6] Mac static IP configuration..."

if [ "$TB_IP" = "$DEFAULT_MAC_IP" ]; then
    echo -e "      ${GREEN}OK: Already has recommended IP $DEFAULT_MAC_IP${NC}"
else
    echo ""
    echo "      Current IP: ${TB_IP:-none}"
    read -p "      Set static IP $DEFAULT_MAC_IP? (Y/n): " SET_IP
    
    if [ "$SET_IP" != "n" ] && [ "$SET_IP" != "N" ]; then
        echo "      Setting static IP (may require password)..."
        
        # Using networksetup for persistent config
        if [ -n "$TB_SERVICE" ]; then
            sudo networksetup -setmanual "$TB_SERVICE" "$DEFAULT_MAC_IP" "255.255.255.0" "" 2>/dev/null || \
            sudo ifconfig "$TB_INTERFACE" "$DEFAULT_MAC_IP" netmask 255.255.255.0 2>/dev/null || true
        else
            sudo ifconfig "$TB_INTERFACE" "$DEFAULT_MAC_IP" netmask 255.255.255.0 2>/dev/null || true
        fi
        
        TB_IP="$DEFAULT_MAC_IP"
        echo -e "      ${GREEN}OK: IP set to $DEFAULT_MAC_IP${NC}"
    else
        echo "      Skipped"
    fi
fi

# Step 4: Create SSH key
echo ""
echo "[4/6] Creating SSH key..."

if [ -f "$SSH_KEY_PATH" ]; then
    echo -e "      ${GREEN}OK: Key already exists at $SSH_KEY_PATH${NC}"
else
    echo "      Generating new ED25519 key..."
    ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "thundermirror-blade18"
    echo -e "      ${GREEN}OK: Key created${NC}"
fi

# Step 5: Configure SSH host alias
echo ""
echo "[5/6] Configuring SSH host alias..."

SSH_CONFIG="$HOME/.ssh/config"

# Ensure .ssh directory exists
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Check if alias already exists
if grep -q "^Host $SSH_HOST_ALIAS" "$SSH_CONFIG" 2>/dev/null; then
    echo "      Host alias '$SSH_HOST_ALIAS' already exists in $SSH_CONFIG"
    read -p "      Update it? (Y/n): " UPDATE_CONFIG
    
    if [ "$UPDATE_CONFIG" != "n" ] && [ "$UPDATE_CONFIG" != "N" ]; then
        # Remove existing config block
        sed -i.bak "/^Host $SSH_HOST_ALIAS$/,/^Host /{ /^Host $SSH_HOST_ALIAS$/d; /^Host /!d; }" "$SSH_CONFIG"
        # Clean up empty lines
        sed -i.bak '/^$/N;/^\n$/d' "$SSH_CONFIG"
    else
        echo "      Keeping existing config"
    fi
fi

# Add/update config
if ! grep -q "^Host $SSH_HOST_ALIAS" "$SSH_CONFIG" 2>/dev/null; then
    cat >> "$SSH_CONFIG" << EOF

# ThunderMirror - Windows via Thunderbolt
Host $SSH_HOST_ALIAS
    HostName $WIN_IP
    User $WIN_USER
    IdentityFile $SSH_KEY_PATH
    IdentitiesOnly yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
    StrictHostKeyChecking accept-new
EOF
    chmod 600 "$SSH_CONFIG"
    echo -e "      ${GREEN}OK: Host alias '$SSH_HOST_ALIAS' added to $SSH_CONFIG${NC}"
fi

# Step 6: Copy public key to Windows
echo ""
echo "[6/6] Copying public key to Windows..."
echo ""
echo "      This will use SSH to copy the key to Windows."
echo "      You'll need to enter your Windows password ONCE."
echo ""

# Read the public key
PUB_KEY=$(cat "${SSH_KEY_PATH}.pub")

# Copy to Windows using ssh
echo "      Connecting to $WIN_USER@$WIN_IP..."
ssh -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password,keyboard-interactive \
    "$WIN_USER@$WIN_IP" \
    "powershell.exe -NoProfile -Command \"\$sshDir = \\\"\$env:USERPROFILE\\.ssh\\\"; if (!(Test-Path \$sshDir)) { New-Item -ItemType Directory -Path \$sshDir -Force | Out-Null }; \$authKeys = Join-Path \$sshDir 'authorized_keys'; if (!(Test-Path \$authKeys) -or !(Select-String -Path \$authKeys -Pattern 'thundermirror-blade18' -Quiet)) { Add-Content -Path \$authKeys -Value '$PUB_KEY' }; Write-Host 'Key added successfully'\""

if [ $? -eq 0 ]; then
    echo -e "      ${GREEN}OK: Public key copied to Windows${NC}"
else
    echo -e "      ${RED}FAIL: Could not copy key${NC}"
    echo ""
    echo "      Manual steps:"
    echo "      1. Copy this key:"
    echo "         $(cat ${SSH_KEY_PATH}.pub)"
    echo ""
    echo "      2. On Windows, create/edit:"
    echo "         %USERPROFILE%\\.ssh\\authorized_keys"
    echo ""
    echo "      3. Paste the key and save"
    exit 1
fi

# Test connection
echo ""
echo "========================================"
echo "Testing SSH connection..."
echo "========================================"
echo ""

if ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_HOST_ALIAS" "whoami" 2>/dev/null; then
    echo ""
    echo -e "${GREEN}✅ SSH setup complete!${NC}"
    echo ""
    echo "You can now connect with: ssh $SSH_HOST_ALIAS"
    echo ""
    echo "Next steps:"
    echo "  1. ./scripts/02_verify_ssh_mac.sh"
    echo "  2. ./scripts/03_write_cursor_mcp_config.sh"
else
    echo ""
    echo -e "${YELLOW}⚠️  SSH key authentication not working yet${NC}"
    echo ""
    echo "The key was copied, but passwordless auth isn't working."
    echo "This might be a Windows permissions issue."
    echo ""
    echo "Try on Windows (Admin PowerShell):"
    echo '  icacls $env:USERPROFILE\.ssh\authorized_keys /inheritance:r'
    echo '  icacls $env:USERPROFILE\.ssh\authorized_keys /grant:r "$($env:USERNAME):(R)"'
    echo ""
    echo "Then retry: ./scripts/02_verify_ssh_mac.sh"
fi
