#!/bin/bash
#
# install_mac.sh - Install ThunderMirror.app to /Applications
#
# This script builds the app and copies it to the Applications folder.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAC_DIR="$PROJECT_ROOT/mac"
BUILD_DIR="$MAC_DIR/build"
APP_BUNDLE="$BUILD_DIR/ThunderMirror.app"
INSTALL_PATH="/Applications/ThunderMirror.app"

echo "========================================"
echo "Installing ThunderMirror.app"
echo "========================================"
echo ""

# Build the app first
"$SCRIPT_DIR/build_mac_app.sh"
echo ""

# Check if app exists
if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "❌ Error: App bundle not found at $APP_BUNDLE"
    exit 1
fi

# Remove existing installation if present
if [[ -d "$INSTALL_PATH" ]]; then
    echo "🗑️  Removing existing installation..."
    rm -rf "$INSTALL_PATH"
fi

# Copy to Applications
echo "📦 Installing to /Applications..."
cp -R "$APP_BUNDLE" "$INSTALL_PATH"

if [[ -d "$INSTALL_PATH" ]]; then
    echo ""
    echo "========================================"
    echo "✅ Installation complete!"
    echo "========================================"
    echo ""
    echo "ThunderMirror is now installed at: $INSTALL_PATH"
    echo ""
    echo "You can find it in:"
    echo "  • Launchpad"
    echo "  • Spotlight (⌘ + Space, type 'ThunderMirror')"
    echo "  • Finder → Applications"
    echo ""
    echo "To launch now:"
    echo "  open /Applications/ThunderMirror.app"
else
    echo "❌ Error: Installation failed"
    exit 1
fi

