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
TESTS_SKIPPED=0

# Helper function for required tests
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

# Helper function for optional tests (network-dependent)
run_optional_test() {
    local name="$1"
    local cmd="$2"
    
    echo -n "[Test] $name... "
    
    if eval "$cmd" > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
        ((TESTS_PASSED++))
        ((TESTS_TOTAL++))
        return 0
    else
        echo -e "${YELLOW}SKIP (network)${NC}"
        ((TESTS_SKIPPED++))
        return 0  # Don't fail on optional tests
    fi
}

# Phase 0 Tests
echo "=== Phase 0: Infrastructure ===" 
echo ""

# Test: Thunderbolt link (optional - may not be connected)
run_optional_test "Thunderbolt Bridge exists" \
    "networksetup -listallnetworkservices 2>/dev/null | grep -qi thunderbolt || ifconfig bridge0 2>/dev/null | grep -q inet"

# Test: Ping Windows (optional - requires connection)
WIN_IP="${THUNDER_WIN_IP:-192.168.50.2}"
run_optional_test "Ping Windows ($WIN_IP)" \
    "ping -c 1 -W 2 '$WIN_IP'"

# Test: SSH connection (optional - requires connection)
run_optional_test "SSH to Windows" \
    "ssh -o BatchMode=yes -o ConnectTimeout=5 blade18-tb 'whoami'"

# Test: logs directory (required)
run_test "logs/ directory exists" \
    "test -d '$PROJECT_DIR/logs'"

# Test: Rust shared crate builds (required)
if [ -d "$PROJECT_DIR/shared" ] && [ -f "$PROJECT_DIR/shared/Cargo.toml" ]; then
    run_test "Rust shared crate builds" \
        "cd '$PROJECT_DIR/shared' && cargo check"
fi

# Test: Swift package builds (required)
if [ -d "$PROJECT_DIR/mac" ] && [ -f "$PROJECT_DIR/mac/Package.swift" ]; then
    run_test "Swift package builds" \
        "cd '$PROJECT_DIR/mac' && swift build"
fi

# Phase 1 Tests: QUIC Transport and Test Patterns
echo ""
echo "=== Phase 1: QUIC Transport ==="
echo ""

# Test: Shared crate QUIC tests pass (required)
if [ -d "$PROJECT_DIR/shared" ] && [ -f "$PROJECT_DIR/shared/Cargo.toml" ]; then
    run_test "Shared crate QUIC tests pass" \
        "cd '$PROJECT_DIR/shared' && cargo test transport --quiet"
fi

# Test: Test pattern generator works (required)
if [ -d "$PROJECT_DIR/shared" ] && [ -f "$PROJECT_DIR/shared/Cargo.toml" ]; then
    run_test "Test pattern generator works" \
        "cd '$PROJECT_DIR/shared' && cargo test test_pattern --quiet"
fi

# Test: Mac sender builds and runs (help only) (required)
if [ -d "$PROJECT_DIR/mac" ] && [ -f "$PROJECT_DIR/mac/Package.swift" ]; then
    run_test "Mac sender --help works" \
        "cd '$PROJECT_DIR/mac' && .build/debug/ThunderMirror --help"
fi

# Phase 2+ Tests (when implemented)
# TODO: Add real capture tests

echo ""
echo "========================================"

if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
    if [ $TESTS_SKIPPED -gt 0 ]; then
        echo -e "${GREEN}✅ All $TESTS_TOTAL required tests passed!${NC} (${TESTS_SKIPPED} network tests skipped)"
    else
        echo -e "${GREEN}✅ All $TESTS_TOTAL tests passed!${NC}"
    fi
    echo "========================================"
    exit 0
else
    TESTS_FAILED=$((TESTS_TOTAL - TESTS_PASSED))
    echo -e "${RED}❌ $TESTS_PASSED/$TESTS_TOTAL passed ($TESTS_FAILED failed)${NC}"
    if [ $TESTS_SKIPPED -gt 0 ]; then
        echo -e "${YELLOW}   ($TESTS_SKIPPED network tests skipped)${NC}"
    fi
    echo "========================================"
    exit 1
fi
