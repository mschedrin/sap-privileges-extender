# Legacy PoC — Privileges Extender

This directory contains the original proof-of-concept implementation that has been **superseded** by the native macOS menu bar app in `PrivilegesExtender/`.

## How it worked

- **`privileges-extend.sh`** — Main script that re-elevated admin privileges via SAP PrivilegesCLI and launched a helper app to dismiss notifications.
- **`com.user.privileges-extender.plist`** — LaunchAgent plist that ran the script every 15 minutes.
- **`install.sh` / `uninstall.sh`** — Installers for the LaunchAgent and helper app.
- **`helper/DismissNotifications.swift`** — Swift helper app that dismissed Privileges notifications.
- **`helper/dismiss-notifications.applescript`** — AppleScript alternative for notification dismissal.

## Why it was replaced

The PoC relied on a LaunchAgent polling loop and a separate helper process. The new menu bar app (`PrivilegesExtender/`) is a single native macOS app that provides a proper UI, configurable durations/reasons, real-time status, and uses the `AXUIElement` API directly for notification dismissal.
