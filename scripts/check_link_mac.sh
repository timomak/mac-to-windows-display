#!/bin/bash
#
# check_link_mac.sh - Verify Thunderbolt Bridge network link on macOS
#
# Usage: ./scripts/check_link_mac.sh [windows_ip]
#
# If no IP is provided, will attempt to auto-discover Windows via mDNS.
# Works with both static IPs (192.168.50.x) and link-local IPs (169.254.x.x).
#
# Environment:
#   THUNDER_WIN_IP - Windows Thunderbolt IP (optional, will auto-discover if not set)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "========================================"
echo "ThunderMirror - Mac Link Check"
echo "========================================"
echo ""

# Step 1: Find Thunderbolt Bridge interface
echo "[1/4] Looking for Thunderbolt Bridge interface..."

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

# Last resort: check all interfaces for any private/link-local IP
if [ -z "$TB_INTERFACE" ]; then
    for iface in $(ifconfig -l); do
        # Check for 192.168.50.x (static) or 169.254.x.x (link-local)
        ip=$(ifconfig "$iface" 2>/dev/null | grep "inet " | grep -E "192\.168\.50\.|169\.254\." | awk '{print $2}')
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
echo "[2/4] Checking IP address..."

if [ -z "$TB_IP" ]; then
    TB_IP=$(ifconfig "$TB_INTERFACE" 2>/dev/null | grep "inet " | awk '{print $2}' | head -1)
fi

if [ -z "$TB_IP" ]; then
    echo -e "      ${RED}FAIL: No IPv4 address on $TB_INTERFACE${NC}"
    echo ""
    echo "      The interface exists but has no IP."
    echo "      This should auto-assign a link-local IP (169.254.x.x)."
    echo ""
    echo "      Try waiting a few seconds and running this script again."
    echo "      If it persists, try setting a static IP:"
    echo "      sudo ifconfig $TB_INTERFACE 192.168.50.1 netmask 255.255.255.0"
    exit 1
fi

# Check if using link-local IP
if [[ "$TB_IP" == 169.254.* ]]; then
    echo -e "      ${GREEN}OK: IP address is $TB_IP ${CYAN}(link-local)${NC}"
    echo "      Using automatic link-local addressing (no static IP needed!)"
else
    echo -e "      ${GREEN}OK: IP address is $TB_IP${NC}"
fi

# Step 3: Discover Windows IP
echo ""
echo "[3/4] Finding Windows receiver..."

# Use provided IP, environment variable, or try auto-discovery
WIN_IP="${1:-${THUNDER_WIN_IP:-}}"

if [ -z "$WIN_IP" ]; then
    echo "      No IP provided, attempting mDNS discovery..."
    
    # Try to discover via dns-sd (Bonjour)
    # Run for 3 seconds and capture output
    DISCOVERED=""
    if command -v dns-sd &> /dev/null; then
        # Use timeout to limit discovery time
        MDNS_OUTPUT=$(timeout 3 dns-sd -B _thunder-mirror._udp local. 2>/dev/null || true)
        if echo "$MDNS_OUTPUT" | grep -q "thunder-mirror"; then
            # Found a service, now resolve it
            SERVICE_NAME=$(echo "$MDNS_OUTPUT" | grep "thunder-mirror" | awk '{print $7}' | head -1)
            if [ -n "$SERVICE_NAME" ]; then
                echo "      Found service: $SERVICE_NAME"
                # Try to resolve the service to get IP
                RESOLVE_OUTPUT=$(timeout 3 dns-sd -L "$SERVICE_NAME" _thunder-mirror._udp local. 2>/dev/null || true)
                echo "$RESOLVE_OUTPUT"
            fi
        fi
    fi
    
    # If mDNS didn't work, try ARP table for link-local neighbors
    if [ -z "$DISCOVERED" ]; then
        echo "      Checking ARP table for link-local neighbors..."
        
        # Look for 169.254.x.x entries in ARP table
        ARP_IPS=$(arp -a -i "$TB_INTERFACE" 2>/dev/null | grep "169.254" | awk -F'[()]' '{print $2}' | head -5)
        
        if [ -n "$ARP_IPS" ]; then
            echo "      Found potential peers via ARP:"
            for ip in $ARP_IPS; do
                echo "        - $ip"
            done
            
            # Use the first one found
            WIN_IP=$(echo "$ARP_IPS" | head -1)
            echo -e "      ${CYAN}Auto-selected: $WIN_IP${NC}"
        fi
    fi
    
    # If still no IP, check if we're on link-local and try common patterns
    if [ -z "$WIN_IP" ] && [[ "$TB_IP" == 169.254.* ]]; then
        echo -e "      ${YELLOW}No peer found yet via discovery${NC}"
        echo ""
        echo "      This is normal if Windows receiver isn't running yet."
        echo "      Start the Windows receiver, then run this script again."
        echo ""
        echo "      Or manually find the Windows IP:"
        echo "      1. On Windows PowerShell: Get-NetIPAddress | Where-Object InterfaceAlias -match 'Thunderbolt|Ethernet'"
        echo "      2. Then run: ./scripts/check_link_mac.sh <windows_ip>"
        exit 0
    fi
fi

# Fallback to legacy static IP if nothing else
if [ -z "$WIN_IP" ]; then
    WIN_IP="192.168.50.2"
    echo -e "      ${YELLOW}Using default static IP: $WIN_IP${NC}"
fi

# Step 4: Ping Windows
echo ""
echo "[4/4] Pinging Windows at $WIN_IP..."

if ping -c 3 -W 2 "$WIN_IP" > /dev/null 2>&1; then
    PING_TIME=$(ping -c 1 "$WIN_IP" 2>/dev/null | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1/')
    echo -e "      ${GREEN}OK: Ping successful (${PING_TIME}ms)${NC}"
else
    echo -e "      ${YELLOW}WARN: Cannot ping $WIN_IP${NC}"
    echo ""
    echo "      This might be OK - Windows firewall often blocks ping."
    echo "      The ThunderMirror app should still work."
    echo ""
    echo "      If you need ping to work, on Windows run:"
    echo "      New-NetFirewallRule -Name 'ICMP-Allow' -DisplayName 'Allow ICMP' \\"
    echo "          -Protocol ICMPv4 -IcmpType 8 -Action Allow -Profile Any"
fi

# Summary
echo ""
echo "========================================"
echo -e "${GREEN}✅ Thunderbolt Bridge link detected!${NC}"
echo "========================================"
echo ""
echo "Interface: $TB_INTERFACE"
echo "Mac IP:    $TB_IP"
if [ -n "$WIN_IP" ]; then
    echo "Win IP:    $WIN_IP"
fi

if [[ "$TB_IP" == 169.254.* ]]; then
    echo ""
    echo -e "${CYAN}Using link-local addressing (zero-config)${NC}"
    echo "The ThunderMirror app will auto-discover the receiver."
fi

echo ""
echo "Next step: Start the apps!"
echo "  Windows: Run ThunderReceiver.exe"
echo "  Mac:     Run ThunderMirror.app"
echo ""
echo "The Mac app will auto-discover the Windows receiver."
