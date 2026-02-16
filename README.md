# Privileges Extender

A macOS background service that automatically keeps SAP Privileges admin rights elevated and suppresses related notifications.

## Why

SAP Privileges v2.5.0 with MDM-enforced `ExpirationIntervalMax: 30` revokes admin rights after 30 minutes and shows notification banners. This tool re-elevates every 15 minutes and dismisses those notifications.

## How it works

A launchd user agent runs a script every 15 minutes that:

1. Re-elevates admin privileges via `PrivilegesCLI --add`
2. Launches a helper app (`DismissPrivilegesNotifications.app`) that finds and closes any "Privileges" notification banners via the Accessibility API
3. Logs everything to `~/Library/Logs/privileges-extender.log`

The helper app is a small Swift binary that loads an AppleScript from `~/.local/bin/dismiss-notifications.scpt` at runtime. This means the AppleScript can be updated without recompiling the app or re-granting permissions.

On install, notification flags for the Privileges agent are also cleared at the user level (best-effort — MDM may re-enforce at Jamf check-in, so the AppleScript dismissal is the reliable fallback).

## Install

```bash
./install.sh
```

Then grant Accessibility permission to the helper app:

1. **System Settings > Privacy & Security > Accessibility**
2. Click `+`, press `Cmd+Shift+G`, type `~/Applications/`
3. Select `DismissPrivilegesNotifications.app` and enable the toggle

## Uninstall

```bash
./uninstall.sh
```

Removes the agent, scripts, helper app, log files, and restores notification settings.

## Verify

```bash
# Check agent is loaded
launchctl list | grep privileges-extender

# Watch the log
tail -f ~/Library/Logs/privileges-extender.log
```

## Manual control

```bash
# Stop the agent
launchctl unload ~/Library/LaunchAgents/com.user.privileges-extender.plist

# Start the agent
launchctl load ~/Library/LaunchAgents/com.user.privileges-extender.plist

# Trigger a run immediately (without waiting for the 15-min interval)
launchctl start com.user.privileges-extender
```

## Test manually

```bash
# Run the script directly
bash ./privileges-extend.sh

# Check the log
cat ~/Library/Logs/privileges-extender.log
```

## Files

| File | Installed to | Description |
|------|-------------|-------------|
| `privileges-extend.sh` | `~/.local/bin/` | Main script (re-elevate + dismiss notifications) |
| `helper/dismiss-notifications.applescript` | `~/.local/bin/dismiss-notifications.scpt` | AppleScript for finding and closing notification banners |
| `helper/DismissNotifications.swift` | `~/Applications/DismissPrivilegesNotifications.app` | Swift helper app that runs the AppleScript with Accessibility permission |
| `com.user.privileges-extender.plist` | `~/Library/LaunchAgents/` | LaunchAgent plist (runs every 15 min) |
| `install.sh` | — | Installer |
| `uninstall.sh` | — | Uninstaller |

## Requirements

- macOS with SAP Privileges.app installed
- Xcode Command Line Tools (for `swiftc`, used during install)
- Accessibility permission for `~/Applications/DismissPrivilegesNotifications.app`
