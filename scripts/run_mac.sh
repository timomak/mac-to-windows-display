#!/bin/bash
#
# run_mac.sh - Build and run the Mac sender CLI
#
# Usage: ./scripts/run_mac.sh [options]
#
# Options passed through to the CLI.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MAC_DIR="$PROJECT_DIR/mac"

echo "========================================"
echo "ThunderMirror - Mac Sender"
echo "========================================"
echo ""

# Ensure logs directory exists
mkdir -p "$PROJECT_DIR/logs"

# Build (default: release for performance; set THUNDERMIRROR_BUILD_CONFIG=debug to override)
echo "[1/2] Building..."
cd "$MAC_DIR"

BUILD_CONFIG="${THUNDERMIRROR_BUILD_CONFIG:-release}"

if swift build -c "$BUILD_CONFIG" 2>&1; then
    echo "      Build successful"
else
    echo "      Build failed"
    exit 1
fi

# Run
echo ""
echo "[2/2] Running..."
echo ""

# Find the built executable
EXECUTABLE=$(swift build -c "$BUILD_CONFIG" --show-bin-path)/ThunderMirror

if [ -f "$EXECUTABLE" ]; then
    exec "$EXECUTABLE" "$@"
else
    echo "ERROR: Executable not found at $EXECUTABLE"
    echo ""
    echo "This is a scaffold. Full implementation coming in Phase 1+."
    exit 1
fi
