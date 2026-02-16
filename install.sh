#!/bin/bash
# install.sh — Install the Privileges Extender agent

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"
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

# 2. Install the script
echo "Installing script to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/privileges-extend.sh" "$INSTALL_DIR/privileges-extend.sh"
chmod +x "$INSTALL_DIR/privileges-extend.sh"

# 3. Install the LaunchAgent plist
echo "Installing LaunchAgent..."
mkdir -p "$LAUNCH_AGENTS_DIR"
cp "$SCRIPT_DIR/$PLIST_NAME" "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

# 4. Unload if already loaded, then load the agent
echo "Loading agent..."
launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true
launchctl load "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

# 5. Run once immediately
echo "Running initial elevation..."
bash "$INSTALL_DIR/privileges-extend.sh"

echo ""
echo "=== Installation complete ==="
echo "Log: ~/Library/Logs/privileges-extender.log"
echo ""
echo "IMPORTANT: Grant Accessibility permission to Terminal"
echo "  System Settings > Privacy & Security > Accessibility > Terminal (enable)"
echo "  This is needed for notification dismissal via AppleScript."
