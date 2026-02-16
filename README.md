# Privileges Extender

A macOS background service that automatically keeps SAP Privileges admin rights elevated and suppresses related notifications.

## Why

SAP Privileges v2.5.0 with MDM-enforced `ExpirationIntervalMax: 30` revokes admin rights after 30 minutes and shows notification banners. This tool re-elevates every 15 minutes and dismisses those notifications.

## How it works

A launchd user agent runs a script every 15 minutes that:

1. Re-elevates admin privileges via `PrivilegesCLI --add`
2. Dismisses any "Privileges" notification banners via AppleScript
3. Logs everything to `~/Library/Logs/privileges-extender.log`

On install, it also disables notifications for the Privileges agent at the user level (best-effort — MDM may re-enforce, so AppleScript dismissal is the reliable fallback).

## Install

```bash
./install.sh
```

Then grant Accessibility permission to Terminal:

**System Settings > Privacy & Security > Accessibility > Terminal (enable)**

This is required for AppleScript notification dismissal.

## Uninstall

```bash
./uninstall.sh
```

Removes the agent, script, log file, and restores notification settings.

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

## Files

| File | Description |
|------|-------------|
| `privileges-extend.sh` | Main script (re-elevate + dismiss notifications) |
| `com.user.privileges-extender.plist` | LaunchAgent plist (runs every 15 min) |
| `install.sh` | Installer |
| `uninstall.sh` | Uninstaller |

## Requirements

- macOS with SAP Privileges.app installed
- Terminal with Accessibility permission (for notification dismissal)
