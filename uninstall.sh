#!/bin/bash
# uninstall.sh — Remove the Privileges Extender agent (LEGACY PoC)
#
# NOTE: This script removes the legacy LaunchAgent + helper app version.
# For the new native menu bar app, use: PrivilegesExtender/scripts/uninstall.sh

INSTALL_DIR="$HOME/.local/bin"
HELPER_APP="$HOME/Applications/DismissPrivilegesNotifications.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.privileges-extender.plist"
LOG_FILE="$HOME/Library/Logs/privileges-extender.log"
DISMISS_LOG="$HOME/Library/Logs/privileges-extender-dismiss.log"
NCPREFS="$HOME/Library/Preferences/com.apple.ncprefs.plist"
AGENT_BUNDLE_ID="corp.sap.privileges.agent"

echo "=== Privileges Extender Uninstaller ==="

# 1. Unload the agent
echo "Unloading agent..."
launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true

# 2. Remove files
echo "Removing files..."
rm -f "$LAUNCH_AGENTS_DIR/$PLIST_NAME"
rm -f "$INSTALL_DIR/privileges-extend.sh"
rm -f "$INSTALL_DIR/dismiss-notifications.scpt"
rm -rf "$HELPER_APP"
rm -f "$LOG_FILE"
rm -f "$DISMISS_LOG"

# 3. Restore notification flags for Privileges Agent
echo "Restoring notification settings for $AGENT_BUNDLE_ID..."
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
        # Restore alert-style bits (set bits 1-2 for banner style)
        new_flags = flags | 0x6
        if new_flags != flags:
            app['flags'] = new_flags
            modified = True
            print(f'Restored flags: 0x{flags:x} -> 0x{new_flags:x}')
        else:
            print(f'Flags already restored: 0x{flags:x}')
        break
else:
    print(f'{bundle_id} not found in ncprefs.plist (nothing to restore)')

if modified:
    with open(ncprefs_path, 'wb') as f:
        plistlib.dump(prefs, f)
    print('Notification preferences restored')
"

# Restart NotificationCenter to apply
killall NotificationCenter 2>/dev/null || true

echo ""
echo "=== Uninstall complete ==="
echo "Note: You can manually remove DismissPrivilegesNotifications from"
echo "  System Settings > Privacy & Security > Accessibility"
