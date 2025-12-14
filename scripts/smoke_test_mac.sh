#!/bin/bash
#
# smoke_test_mac.sh - Phase-aware smoke test for Mac
#
# This script runs appropriate tests based on the current development phase.
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================"
echo "ThunderMirror - Mac Smoke Test"
echo "========================================"
echo ""

TESTS_PASSED=0
TESTS_TOTAL=0

# Helper function
run_test() {
    local name="$1"
    local cmd="$2"
    
    ((TESTS_TOTAL++))
    echo -n "[Test] $name... "
    
    if eval "$cmd" > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        return 1
    fi
}

# Phase 0 Tests
echo "=== Phase 0: Infrastructure ===" 
echo ""

# Test: Thunderbolt link
run_test "Thunderbolt Bridge exists" \
    "networksetup -listallnetworkservices 2>/dev/null | grep -qi thunderbolt || ifconfig bridge0 2>/dev/null | grep -q inet"

# Test: Ping Windows
WIN_IP="${THUNDER_WIN_IP:-192.168.50.2}"
run_test "Ping Windows ($WIN_IP)" \
    "ping -c 1 -W 2 '$WIN_IP'"

# Test: SSH connection
run_test "SSH to Windows" \
    "ssh -o BatchMode=yes -o ConnectTimeout=5 blade18-tb 'whoami'"

# Test: logs directory
run_test "logs/ directory exists" \
    "test -d '$PROJECT_DIR/logs'"

# Test: Rust shared crate builds
if [ -d "$PROJECT_DIR/shared" ] && [ -f "$PROJECT_DIR/shared/Cargo.toml" ]; then
    run_test "Rust shared crate builds" \
        "cd '$PROJECT_DIR/shared' && cargo check"
fi

# Test: Swift package builds
if [ -d "$PROJECT_DIR/mac" ] && [ -f "$PROJECT_DIR/mac/Package.swift" ]; then
    run_test "Swift package builds" \
        "cd '$PROJECT_DIR/mac' && swift build"
fi

# Phase 1+ Tests (when implemented)
# TODO: Add streaming tests

echo ""
echo "========================================"

if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
    echo -e "${GREEN}✅ All $TESTS_TOTAL tests passed!${NC}"
    echo "========================================"
    exit 0
else
    TESTS_FAILED=$((TESTS_TOTAL - TESTS_PASSED))
    echo -e "${YELLOW}⚠️  $TESTS_PASSED/$TESTS_TOTAL passed ($TESTS_FAILED failed)${NC}"
    echo "========================================"
    exit 1
fi
