#!/bin/bash
#
# build_mac_app.sh - Build ThunderMirror.app bundle
#
# Creates a proper macOS .app bundle that can be double-clicked to launch.
# The app bundle is created in mac/build/ThunderMirror.app
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAC_DIR="$PROJECT_ROOT/mac"
BUILD_DIR="$MAC_DIR/build"
APP_NAME="ThunderMirror"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "========================================"
echo "Building ThunderMirror.app"
echo "========================================"
echo ""

# Check we're on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ Error: This script must be run on macOS"
    exit 1
fi

# Navigate to mac directory
cd "$MAC_DIR"

# Build the Swift package in release mode
echo "📦 Building Swift package (release)..."
swift build -c release

# Find the built executable
BUILT_EXECUTABLE="$MAC_DIR/.build/release/ThunderMirrorApp"
if [[ ! -f "$BUILT_EXECUTABLE" ]]; then
    echo "❌ Error: Built executable not found at $BUILT_EXECUTABLE"
    echo "   Make sure swift build succeeded."
    exit 1
fi

echo "✅ Swift build complete"
echo ""

# Create app bundle structure
echo "📁 Creating app bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
echo "📋 Copying executable..."
cp "$BUILT_EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/ThunderMirrorApp"

# Copy Info.plist
echo "📋 Copying Info.plist..."
if [[ -f "$MAC_DIR/Resources/Info.plist" ]]; then
    cp "$MAC_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
else
    echo "❌ Error: Info.plist not found at $MAC_DIR/Resources/Info.plist"
    exit 1
fi

# Create PkgInfo
echo "📋 Creating PkgInfo..."
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Copy entitlements (for reference, not embedded in unsigned app)
if [[ -f "$MAC_DIR/Resources/ThunderMirror.entitlements" ]]; then
    cp "$MAC_DIR/Resources/ThunderMirror.entitlements" "$APP_BUNDLE/Contents/Resources/"
fi

# Check if we have an app icon
if [[ -f "$MAC_DIR/Resources/AppIcon.icns" ]]; then
    echo "📋 Copying app icon..."
    cp "$MAC_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
else
    echo "⚠️  No AppIcon.icns found - app will use default icon"
    echo "   Create mac/Resources/AppIcon.icns to add a custom icon"
fi

# Sign the app (ad-hoc signing for local use)
echo ""
echo "🔏 Signing app (ad-hoc for local use)..."
if codesign --sign - --force --deep --preserve-metadata=entitlements "$APP_BUNDLE" 2>/dev/null; then
    echo "✅ App signed successfully (ad-hoc)"
else
    echo "⚠️  Ad-hoc signing skipped (app may require right-click to open)"
fi

# Verify the bundle
echo ""
echo "🔍 Verifying app bundle..."
if [[ -x "$APP_BUNDLE/Contents/MacOS/ThunderMirrorApp" ]]; then
    echo "✅ Executable is present and executable"
else
    echo "❌ Executable missing or not executable"
    exit 1
fi

if [[ -f "$APP_BUNDLE/Contents/Info.plist" ]]; then
    echo "✅ Info.plist is present"
else
    echo "❌ Info.plist missing"
    exit 1
fi

echo ""
echo "========================================"
echo "✅ Build complete!"
echo "========================================"
echo ""
echo "App bundle: $APP_BUNDLE"
echo ""
echo "To run:"
echo "  open \"$APP_BUNDLE\""
echo ""
echo "To install to Applications:"
echo "  cp -R \"$APP_BUNDLE\" /Applications/"
echo ""
echo "Note: On first launch, macOS may ask you to approve the app."
echo "      Right-click → Open, or go to System Preferences → Security & Privacy."

