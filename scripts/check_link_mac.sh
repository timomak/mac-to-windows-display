#!/bin/bash
#
# check_link_mac.sh - Verify Thunderbolt Bridge network link on macOS
#
# Usage: ./scripts/check_link_mac.sh [windows_ip]
#
# Environment:
#   THUNDER_WIN_IP - Windows Thunderbolt IP (default: 192.168.50.2)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
WIN_IP="${1:-${THUNDER_WIN_IP:-192.168.50.2}}"

echo "========================================"
echo "ThunderMirror - Mac Link Check"
echo "========================================"
echo ""

# Step 1: Find Thunderbolt Bridge interface
echo "[1/3] Looking for Thunderbolt Bridge interface..."

# Try to find the interface by name
TB_INTERFACE=""
TB_IP=""

# Check for Thunderbolt Bridge service in networksetup
if networksetup -listallnetworkservices 2>/dev/null | grep -qi "thunderbolt"; then
    TB_SERVICE=$(networksetup -listallnetworkservices | grep -i "thunderbolt" | head -1)
    echo "      Found service: $TB_SERVICE"
    
    # Get the interface name
    TB_INTERFACE=$(networksetup -listallhardwareports | grep -A1 "$TB_SERVICE" | grep "Device:" | awk '{print $2}')
fi

# If not found by service, try by interface naming convention
if [ -z "$TB_INTERFACE" ]; then
    # Look for bridge interfaces
    for iface in bridge0 bridge1 en5 en6 en7 en8 en9; do
        if ifconfig "$iface" 2>/dev/null | grep -q "inet "; then
            # Check if this looks like a Thunderbolt interface
            if networksetup -listallhardwareports 2>/dev/null | grep -B1 "$iface" | grep -qi "thunderbolt\|bridge"; then
                TB_INTERFACE="$iface"
                break
            fi
        fi
    done
fi

# Last resort: check all interfaces for our expected IP range
if [ -z "$TB_INTERFACE" ]; then
    for iface in $(ifconfig -l); do
        ip=$(ifconfig "$iface" 2>/dev/null | grep "inet " | grep "192.168.50" | awk '{print $2}')
        if [ -n "$ip" ]; then
            TB_INTERFACE="$iface"
            TB_IP="$ip"
            break
        fi
    done
fi

if [ -z "$TB_INTERFACE" ]; then
    echo -e "      ${RED}FAIL: No Thunderbolt Bridge interface found${NC}"
    echo ""
    echo "      Possible causes:"
    echo "      - Thunderbolt cable not connected"
    echo "      - Cable is USB-C only (not Thunderbolt)"
    echo "      - Interface not configured"
    echo ""
    echo "      Try:"
    echo "      1. Check System Settings → Network for 'Thunderbolt Bridge'"
    echo "      2. Run: networksetup -listallnetworkservices"
    echo "      3. See docs/SETUP_THUNDERBOLT_BRIDGE.md"
    exit 1
fi

echo -e "      ${GREEN}OK: Found interface $TB_INTERFACE${NC}"

# Step 2: Get IP address
echo ""
echo "[2/3] Checking IP address..."

if [ -z "$TB_IP" ]; then
    TB_IP=$(ifconfig "$TB_INTERFACE" 2>/dev/null | grep "inet " | awk '{print $2}' | head -1)
fi

if [ -z "$TB_IP" ]; then
    echo -e "      ${RED}FAIL: No IPv4 address on $TB_INTERFACE${NC}"
    echo ""
    echo "      The interface exists but has no IP. Try:"
    echo "      1. Set a static IP in System Settings → Network → Thunderbolt Bridge"
    echo "      2. Recommended: 192.168.50.1 / 255.255.255.0"
    echo ""
    echo "      Or run:"
    echo "      sudo ifconfig $TB_INTERFACE 192.168.50.1 netmask 255.255.255.0"
    exit 1
fi

echo -e "      ${GREEN}OK: IP address is $TB_IP${NC}"

# Step 3: Ping Windows
echo ""
echo "[3/3] Pinging Windows at $WIN_IP..."

if ping -c 3 -W 2 "$WIN_IP" > /dev/null 2>&1; then
    PING_TIME=$(ping -c 1 "$WIN_IP" 2>/dev/null | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1/')
    echo -e "      ${GREEN}OK: Ping successful (${PING_TIME}ms)${NC}"
else
    echo -e "      ${RED}FAIL: Cannot ping $WIN_IP${NC}"
    echo ""
    echo "      Possible causes:"
    echo "      - Windows doesn't have IP $WIN_IP"
    echo "      - Windows firewall blocking ICMP"
    echo "      - Different subnet"
    echo ""
    echo "      Try:"
    echo "      1. On Windows, run: ipconfig"
    echo "      2. Check Windows has IP in 192.168.50.x subnet"
    echo "      3. Disable Windows Firewall temporarily for testing"
    echo ""
    echo "      If Windows IP is different, run:"
    echo "      ./scripts/check_link_mac.sh <correct_windows_ip>"
    exit 1
fi

# Summary
echo ""
echo "========================================"
echo -e "${GREEN}✅ Thunderbolt Bridge link is working!${NC}"
echo "========================================"
echo ""
echo "Interface: $TB_INTERFACE"
echo "Mac IP:    $TB_IP"
echo "Win IP:    $WIN_IP"
echo ""
echo "Next step: Run SSH setup"
echo "  Windows: .\\scripts\\01_setup_ssh_win.ps1"
echo "  Mac:     ./scripts/01_setup_ssh_mac.sh"
