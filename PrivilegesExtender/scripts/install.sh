#!/bin/bash
# install.sh — Install PrivilegesExtender menu bar app
#
# Usage:
#   ./scripts/install.sh                    # Install from default build location
#   ./scripts/install.sh --app-path PATH    # Install from custom .app path
#
# The script:
#   1. Copies the .app bundle to ~/Applications/
#   2. Creates the config directory (~/Library/Application Support/PrivilegesExtender/)
#   3. Copies default config if none exists
#   4. Reminds user to grant Accessibility permission

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="PrivilegesExtender"
INSTALL_DIR="$HOME/Applications"
CONFIG_DIR="$HOME/Library/Application Support/PrivilegesExtender"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
DEFAULT_CONFIG="$PROJECT_DIR/Resources/default-config.yaml"
APP_BUNDLE="$PROJECT_DIR/build/$APP_NAME.app"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-path)
            APP_BUNDLE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--app-path PATH]"
            exit 1
            ;;
    esac
done

echo "=== Installing $APP_NAME ==="

# Verify the .app bundle exists
if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Error: App bundle not found at $APP_BUNDLE"
    echo "Run scripts/build.sh first to build the app."
    exit 1
fi

# Step 1: Quit the app if it's running
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "Stopping running instance..."
    killall "$APP_NAME" 2>/dev/null || true
    sleep 1
fi

# Step 2: Copy .app bundle to ~/Applications/
echo "Installing app to $INSTALL_DIR/..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$INSTALL_DIR/$APP_NAME.app"
echo "  Installed: $INSTALL_DIR/$APP_NAME.app"

# Step 3: Create config directory and copy default config if missing
echo "Setting up configuration..."
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_FILE" ]]; then
    if [[ -f "$DEFAULT_CONFIG" ]]; then
        cp "$DEFAULT_CONFIG" "$CONFIG_FILE"
        echo "  Created default config: $CONFIG_FILE"
    else
        # Try to find default config inside the app bundle
        BUNDLE_CONFIG="$INSTALL_DIR/$APP_NAME.app/Contents/Resources/default-config.yaml"
        if [[ -f "$BUNDLE_CONFIG" ]]; then
            cp "$BUNDLE_CONFIG" "$CONFIG_FILE"
            echo "  Created default config from app bundle: $CONFIG_FILE"
        else
            echo "  Warning: No default config found. App will use built-in defaults."
        fi
    fi
else
    echo "  Config already exists: $CONFIG_FILE (keeping existing)"
fi

echo ""
echo "=== Installation complete ==="
echo ""
echo "To launch: open \"$INSTALL_DIR/$APP_NAME.app\""
echo "Config:    $CONFIG_FILE"
echo "Logs:      ~/Library/Logs/privileges-extender.log"
echo ""
echo "IMPORTANT: Grant Accessibility permission to the app:"
echo "  System Settings > Privacy & Security > Accessibility"
echo "  Enable '$APP_NAME'"
echo ""
echo "To start at login, enable 'Start at Login' from the menu bar icon."
