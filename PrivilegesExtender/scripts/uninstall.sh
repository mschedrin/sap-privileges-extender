#!/bin/bash
# uninstall.sh — Remove PrivilegesExtender menu bar app
#
# Usage:
#   ./scripts/uninstall.sh              # Remove app, keep config and logs
#   ./scripts/uninstall.sh --all        # Remove app, config, and logs
#
# The script:
#   1. Quits the running app if active
#   2. Removes the .app bundle from ~/Applications/
#   3. Optionally removes config directory and log files

set -euo pipefail

APP_NAME="PrivilegesExtender"
INSTALL_DIR="$HOME/Applications"
CONFIG_DIR="$HOME/Library/Application Support/PrivilegesExtender"
LOG_FILE="$HOME/Library/Logs/privileges-extender.log"

REMOVE_ALL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            REMOVE_ALL=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--all]"
            exit 1
            ;;
    esac
done

echo "=== Uninstalling $APP_NAME ==="

# Step 1: Quit the app if it's running
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "Stopping running instance..."
    killall "$APP_NAME" 2>/dev/null || true
    sleep 1
fi

# Step 2: Remove the .app bundle
if [[ -d "$INSTALL_DIR/$APP_NAME.app" ]]; then
    echo "Removing $INSTALL_DIR/$APP_NAME.app..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    echo "  Removed."
else
    echo "App not found at $INSTALL_DIR/$APP_NAME.app (already removed?)"
fi

# Step 3: Optionally remove config and logs
if [[ "$REMOVE_ALL" == true ]]; then
    echo "Removing configuration and logs..."
    if [[ -d "$CONFIG_DIR" ]]; then
        rm -rf "$CONFIG_DIR"
        echo "  Removed config: $CONFIG_DIR"
    fi
    if [[ -f "$LOG_FILE" ]]; then
        rm -f "$LOG_FILE"
        echo "  Removed log: $LOG_FILE"
    fi
else
    echo ""
    echo "Config and logs preserved:"
    echo "  Config: $CONFIG_DIR"
    echo "  Log:    $LOG_FILE"
    echo "  Use --all to remove everything."
fi

echo ""
echo "=== Uninstall complete ==="
echo ""
echo "Note: You may want to remove '$APP_NAME' from:"
echo "  System Settings > Privacy & Security > Accessibility"
echo "  System Settings > General > Login Items"
