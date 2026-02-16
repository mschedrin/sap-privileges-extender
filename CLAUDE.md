# Privileges Extender

A macOS background service that keeps SAP Privileges admin rights elevated and suppresses related notifications.

## Project structure
- `privileges-extend.sh` — Main script (re-elevates privileges, launches helper app to dismiss notifications)
- `com.user.privileges-extender.plist` — LaunchAgent plist (runs every 15 min)
- `helper/DismissNotifications.swift` — Swift helper app source (compiled to .app during install)
- `helper/dismiss-notifications.applescript` — AppleScript for notification dismissal (loaded at runtime by helper app)
- `install.sh` — Installs the agent, builds helper app, configures notifications
- `uninstall.sh` — Removes everything cleanly

## Key paths
- SAP Privileges CLI: `/Applications/Privileges.app/Contents/MacOS/PrivilegesCLI`
- Privileges Agent bundle ID: `corp.sap.privileges.agent`
- Privileges main bundle ID: `corp.sap.privileges`
- Notification prefs: `~/Library/Preferences/com.apple.ncprefs.plist`
- MDM managed prefs: `/Library/Managed Preferences/com.apple.notificationsettings.plist`
- Script install location: `~/.local/bin/privileges-extend.sh`
- AppleScript install location: `~/.local/bin/dismiss-notifications.scpt`
- Helper app install location: `~/Applications/DismissPrivilegesNotifications.app`
- LaunchAgent location: `~/Library/LaunchAgents/com.user.privileges-extender.plist`
- Log file: `~/Library/Logs/privileges-extender.log`
- Dismiss log: `~/Library/Logs/privileges-extender-dismiss.log`

## Environment
- macOS 26.2 (Tahoe)
- SAP Privileges v2.5.0 (bundle: corp.sap.privileges)
- Admin timeout: 30 minutes (MDM-enforced via ExpirationIntervalMax)
- Notifications: MDM-managed (AlertType: 2 = Banner, NotificationsEnabled: true)

## Technical notes
- MDM enforces notification settings, so user-level ncprefs.plist changes may be re-enforced at Jamf check-in
- Notification flags in ncprefs.plist: entry at index 162, flags bitmask controls alert style
- Raw `osascript` cannot get Accessibility permission when run from launchd (no app identity)
- Solution: a Swift helper app (`DismissPrivilegesNotifications.app`) that runs AppleScript via NSAppleScript — it has its own bundle ID (`com.user.dismiss-privileges-notifications`) and can be granted Accessibility permission
- The helper app loads the AppleScript from an external file (`~/.local/bin/dismiss-notifications.scpt`) at runtime, so the script can be updated without recompiling the app or re-granting permissions
- The helper app must be in `~/Applications/` (not `~/.local/bin/`) for macOS to properly track its Accessibility permission
- NotificationCenter UI hierarchy (macOS 26.2): `window "Notification Center" > group 1 > group 1 > scroll area 1 > groups` — each notification group has static texts (heading, body) and actions (press, Show Details, Close)
- PrivilegesAgent is an LSUIElement (background agent) with AppleScript support via .sdef
