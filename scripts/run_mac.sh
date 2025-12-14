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

# Build
echo "[1/2] Building..."
cd "$MAC_DIR"

if swift build 2>&1; then
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
EXECUTABLE=$(swift build --show-bin-path)/ThunderMirror

if [ -f "$EXECUTABLE" ]; then
    exec "$EXECUTABLE" "$@"
else
    echo "ERROR: Executable not found at $EXECUTABLE"
    echo ""
    echo "This is a scaffold. Full implementation coming in Phase 1+."
    exit 1
fi
