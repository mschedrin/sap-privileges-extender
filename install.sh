#!/bin/bash
# install.sh — Install the Privileges Extender agent (LEGACY PoC)
#
# NOTE: This script installs the legacy LaunchAgent + helper app version.
# For the new native menu bar app, use: PrivilegesExtender/scripts/install.sh
# To build the new app first: PrivilegesExtender/scripts/build.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"
HELPER_APP_DIR="$HOME/Applications"
HELPER_APP="$HELPER_APP_DIR/DismissPrivilegesNotifications.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.privileges-extender.plist"
NCPREFS="$HOME/Library/Preferences/com.apple.ncprefs.plist"
AGENT_BUNDLE_ID="corp.sap.privileges.agent"

echo "=== Privileges Extender Installer ==="

# 1. Suppress notifications for Privileges Agent (best-effort, MDM may re-enforce)
echo "Disabling notifications for $AGENT_BUNDLE_ID..."
python3 -c "
import plistlib, sys

ncprefs_path = '$NCPREFS'
bundle_id = '$AGENT_BUNDLE_ID'

try:
    with open(ncprefs_path, 'rb') as f:
        prefs = plistlib.load(f)
except Exception as e:
    print(f'Warning: Could not read ncprefs.plist: {e}')
    sys.exit(0)

modified = False
for app in prefs.get('apps', []):
    if app.get('bundle-id') == bundle_id:
        flags = app.get('flags', 0)
        # Clear alert-style bits (bits 1-2) to disable banners/alerts
        # 0x1000200e -> 0x10002008: clear bits 1 (0x2) and 2 (0x4)
        new_flags = flags & ~0x6
        if new_flags != flags:
            app['flags'] = new_flags
            modified = True
            print(f'Updated flags: 0x{flags:x} -> 0x{new_flags:x}')
        else:
            print(f'Flags already clear: 0x{flags:x}')
        break
else:
    print(f'Warning: {bundle_id} not found in ncprefs.plist')

if modified:
    with open(ncprefs_path, 'wb') as f:
        plistlib.dump(prefs, f)
    print('Notification preferences updated')
"

# Restart NotificationCenter to apply changes
echo "Restarting NotificationCenter..."
killall NotificationCenter 2>/dev/null || true

# 2. Build and install the helper app for notification dismissal
echo "Building notification dismissal helper app..."
mkdir -p "$HELPER_APP_DIR"
mkdir -p "$HELPER_APP/Contents/MacOS"
swiftc -o "$HELPER_APP/Contents/MacOS/DismissPrivilegesNotifications" \
    -framework Cocoa "$SCRIPT_DIR/helper/DismissNotifications.swift"
cat > "$HELPER_APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.user.dismiss-privileges-notifications</string>
    <key>CFBundleName</key>
    <string>DismissPrivilegesNotifications</string>
    <key>CFBundleExecutable</key>
    <string>DismissPrivilegesNotifications</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>This app needs to control System Events to dismiss notifications.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$HELPER_APP"
echo "Helper app installed to $HELPER_APP"

# 3. Install the main script and AppleScript
echo "Installing scripts to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/privileges-extend.sh" "$INSTALL_DIR/privileges-extend.sh"
chmod +x "$INSTALL_DIR/privileges-extend.sh"
cp "$SCRIPT_DIR/helper/dismiss-notifications.applescript" "$INSTALL_DIR/dismiss-notifications.scpt"

# 4. Install the LaunchAgent plist
echo "Installing LaunchAgent..."
mkdir -p "$LAUNCH_AGENTS_DIR"
cp "$SCRIPT_DIR/$PLIST_NAME" "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

# 5. Unload if already loaded, then load the agent
echo "Loading agent..."
launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true
launchctl load "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

# 6. Run once immediately
echo "Running initial elevation..."
bash "$INSTALL_DIR/privileges-extend.sh"

echo ""
echo "=== Installation complete ==="
echo "Log: ~/Library/Logs/privileges-extender.log"
echo ""
echo "IMPORTANT: Grant Accessibility permission to the helper app:"
echo "  System Settings > Privacy & Security > Accessibility"
echo "  Click '+', press Cmd+Shift+G, type ~/Applications/"
echo "  Select DismissPrivilegesNotifications.app and enable it"
