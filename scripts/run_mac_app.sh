#!/bin/bash
#
# run_mac_app.sh - Build and run the ThunderMirror macOS app
#
# This script builds the .app bundle and launches it.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAC_DIR="$PROJECT_ROOT/mac"
BUILD_DIR="$MAC_DIR/build"
APP_BUNDLE="$BUILD_DIR/ThunderMirror.app"

# Build the app if needed or if --rebuild flag is passed
if [[ "$1" == "--rebuild" ]] || [[ ! -d "$APP_BUNDLE" ]]; then
    "$SCRIPT_DIR/build_mac_app.sh"
    echo ""
fi

# Check if app exists
if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "❌ Error: App bundle not found. Run with --rebuild flag."
    exit 1
fi

echo "🚀 Launching ThunderMirror..."
open "$APP_BUNDLE"
