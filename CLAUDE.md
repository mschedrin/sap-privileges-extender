# Privileges Extender

A macOS background service that keeps SAP Privileges admin rights elevated and suppresses related notifications.

## Project structure
- `privileges-extend.sh` — Main script (re-elevates + dismisses notifications)
- `com.user.privileges-extender.plist` — LaunchAgent plist
- `install.sh` — Installs the agent and configures notifications
- `uninstall.sh` — Removes everything cleanly

## Key paths
- SAP Privileges CLI: `/Applications/Privileges.app/Contents/MacOS/PrivilegesCLI`
- Privileges Agent bundle ID: `corp.sap.privileges.agent`
- Privileges main bundle ID: `corp.sap.privileges`
- Notification prefs: `~/Library/Preferences/com.apple.ncprefs.plist`
- MDM managed prefs: `/Library/Managed Preferences/com.apple.notificationsettings.plist`
- Script install location: `~/.local/bin/privileges-extend.sh`
- LaunchAgent location: `~/Library/LaunchAgents/com.user.privileges-extender.plist`
- Log file: `~/Library/Logs/privileges-extender.log`

## Environment
- macOS 26.2 (Tahoe)
- SAP Privileges v2.5.0 (bundle: corp.sap.privileges)
- Admin timeout: 30 minutes (MDM-enforced via ExpirationIntervalMax)
- Notifications: MDM-managed (AlertType: 2 = Banner, NotificationsEnabled: true)

## Technical notes
- MDM enforces notification settings, so user-level ncprefs.plist changes may be re-enforced at Jamf check-in
- Notification flags in ncprefs.plist: entry at index 162, flags bitmask controls alert style
- AppleScript notification dismissal requires Accessibility permission for Terminal
- PrivilegesAgent is an LSUIElement (background agent) with AppleScript support via .sdef
