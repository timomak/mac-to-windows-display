#!/bin/bash
#
# 02_verify_ssh_mac.sh - Verify SSH connection to Windows
#
# This script runs test commands via SSH to confirm the connection works.
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SSH_HOST="blade18-tb"

echo "========================================"
echo "ThunderMirror - SSH Verification"
echo "========================================"
echo ""

# Check if host alias exists
if ! grep -q "^Host $SSH_HOST" "$HOME/.ssh/config" 2>/dev/null; then
    echo -e "${RED}ERROR: SSH host '$SSH_HOST' not configured${NC}"
    echo ""
    echo "Run first: ./scripts/01_setup_ssh_mac.sh"
    exit 1
fi

TESTS_PASSED=0
TESTS_TOTAL=3

# Test 1: Basic connection
echo "[Test 1/3] Basic SSH connection..."
echo "          Running: ssh $SSH_HOST \"whoami\""

if RESULT=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_HOST" "whoami" 2>&1); then
    echo -e "          ${GREEN}OK: $RESULT${NC}"
    ((TESTS_PASSED++))
else
    echo -e "          ${RED}FAIL: $RESULT${NC}"
    echo ""
    echo "          Troubleshooting:"
    echo "          - Check Windows sshd is running"
    echo "          - Check firewall allows port 22"
    echo "          - Verify SSH key was copied correctly"
    echo "          - See docs/TROUBLESHOOTING.md"
fi

echo ""

# Test 2: PowerShell execution
echo "[Test 2/3] PowerShell execution..."
echo "          Running: ssh $SSH_HOST \"powershell.exe ...\""

if RESULT=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_HOST" 'powershell.exe -NoProfile -Command "$PSVersionTable.PSVersion | Format-Table -HideTableHeaders"' 2>&1); then
    # Clean up the result
    VERSION=$(echo "$RESULT" | grep -E "^[0-9]" | head -1 | awk '{print $1"."$2"."$3}')
    if [ -n "$VERSION" ]; then
        echo -e "          ${GREEN}OK: PowerShell version $VERSION${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "          ${GREEN}OK: PowerShell executed${NC}"
        ((TESTS_PASSED++))
    fi
else
    echo -e "          ${RED}FAIL: Could not execute PowerShell${NC}"
    echo "          Output: $RESULT"
fi

echo ""

# Test 3: File system access
echo "[Test 3/3] File system access..."
echo "          Running: ssh $SSH_HOST \"powershell.exe Test-Path ...\""

if RESULT=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_HOST" 'powershell.exe -NoProfile -Command "Test-Path $env:USERPROFILE"' 2>&1); then
    if echo "$RESULT" | grep -qi "true"; then
        echo -e "          ${GREEN}OK: Can access Windows filesystem${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "          ${YELLOW}WARNING: Unexpected result: $RESULT${NC}"
        ((TESTS_PASSED++))
    fi
else
    echo -e "          ${RED}FAIL: Could not access filesystem${NC}"
    echo "          Output: $RESULT"
fi

echo ""
echo "========================================"

if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
    echo -e "${GREEN}✅ All $TESTS_TOTAL tests passed!${NC}"
    echo "========================================"
    echo ""
    echo "SSH connection is working correctly."
    echo ""
    echo "Next step: Configure Cursor MCP"
    echo "  ./scripts/03_write_cursor_mcp_config.sh"
else
    echo -e "${YELLOW}⚠️  $TESTS_PASSED/$TESTS_TOTAL tests passed${NC}"
    echo "========================================"
    echo ""
    echo "Some tests failed. Check:"
    echo "  - Windows sshd service is running"
    echo "  - Windows firewall allows SSH"
    echo "  - Network connectivity (ping test)"
    echo ""
    echo "See docs/TROUBLESHOOTING.md for help."
    exit 1
fi
