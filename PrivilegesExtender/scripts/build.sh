#!/bin/bash
# build.sh — Build PrivilegesExtender and create .app bundle
#
# Usage (from PrivilegesExtender/):
#   ./scripts/build.sh              # Release build (default)
#   ./scripts/build.sh --debug      # Debug build
#   ./scripts/build.sh --output DIR # Custom output directory
#
# The script:
#   1. Runs `swift build -c release` to compile the executable
#   2. Creates a proper .app bundle with Info.plist and resources
#   3. Ad-hoc code signs the bundle

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
BUILD_CONFIG="release"
OUTPUT_DIR="$PROJECT_DIR/build"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            BUILD_CONFIG="debug"
            shift
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--debug] [--output DIR]"
            exit 1
            ;;
    esac
done

APP_NAME="PrivilegesExtender"
BUNDLE_ID="com.user.privileges-extender"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "=== Building $APP_NAME ($BUILD_CONFIG) ==="

# Step 1: Build with SPM
echo "Running swift build -c $BUILD_CONFIG..."
cd "$PROJECT_DIR"
swift build -c "$BUILD_CONFIG"

# Find the built binary
BINARY_PATH=$(swift build -c "$BUILD_CONFIG" --show-bin-path)/"$APP_NAME"

if [[ ! -f "$BINARY_PATH" ]]; then
    echo "Error: Built binary not found at $BINARY_PATH"
    exit 1
fi

echo "Binary built at: $BINARY_PATH"

# Step 2: Create .app bundle structure
echo "Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy the binary
cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Privileges Extender</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Copy default config resource
if [[ -f "$PROJECT_DIR/Resources/default-config.yaml" ]]; then
    cp "$PROJECT_DIR/Resources/default-config.yaml" "$RESOURCES_DIR/default-config.yaml"
fi

# Step 3: Ad-hoc code signing
echo "Code signing (ad-hoc)..."
codesign --force --sign - "$APP_BUNDLE"

echo ""
echo "=== Build complete ==="
echo "App bundle: $APP_BUNDLE"
echo ""
echo "Contents:"
find "$APP_BUNDLE" -type f | sort | while read -r f; do
    echo "  ${f#$APP_BUNDLE/}"
done
