# Privileges Extender

A native macOS menu bar app that keeps SAP Privileges admin rights elevated and suppresses related notifications.

## Why

SAP Privileges v2.5.0 with MDM-enforced `ExpirationIntervalMax: 30` revokes admin rights after 30 minutes and shows notification banners. This app re-elevates privileges automatically before the timeout and dismisses those notifications.

## How it works

The app lives in your menu bar with a shield icon that shows your current privilege status:

- Shield outline = standard user
- Filled shield = elevated (admin)

From the menu bar you can:

- Elevate privileges with a predefined reason and chosen duration
- Enter a custom reason via "Other..."
- Pause/resume auto-extend to temporarily stop re-elevation
- Revoke privileges manually
- View logs, edit configuration, toggle start-at-login

When elevated, a background timer re-invokes PrivilegesCLI every 25 minutes (configurable) to keep privileges alive for your chosen duration. You can pause and resume this auto-extend from the menu.

Notifications from SAP Privileges are suppressed by freezing `usernoted` (the macOS notification display daemon) before each elevation call and killing it after, so the banner never renders. launchd restarts it fresh without the queued notification. This is the default and most reliable method. As a fallback, AXUIElement-based dismissal (Accessibility API) can also be enabled to catch any notifications that slip through.

On launch, the app checks for required permissions (PrivilegesCLI, and Accessibility if the dismiss fallback is enabled) and shows a dialog if anything is missing.

## Menu structure

```
[Shield Icon]
├── ● Elevated — Update software (27 min remaining)
├── ─────────────────────
├── Elevate Now ▸
│   ├── Update software ▸
│   │   ├── 30 minutes
│   │   ├── 1 hour
│   │   ├── 2 hours
│   │   ├── 8 hours
│   │   ├── 24 hours
│   │   ├── Until logout
│   │   └── Indefinitely
│   ├── Installing software ▸
│   │   └── (same durations)
│   ├── ...other reasons...
│   ├── ─────────────────────
│   └── Other...               ← text input dialog
├── ↻ Auto-extending — next in 22 min
├── Revoke Privileges
├── ─────────────────────
├── View Logs
├── Open Configuration
├── ─────────────────────
├── ☑ Start at Login
├── Check Permissions
├── ─────────────────────
└── Quit
```

## Install

### Prerequisites

- macOS 13+ (Ventura or later)
- SAP Privileges.app installed at `/Applications/Privileges.app`
- Xcode Command Line Tools (`xcode-select --install`)

### Build and install

```bash
cd PrivilegesExtender

# Build the .app bundle
./scripts/build.sh

# Install to ~/Applications/
./scripts/install.sh
```

### Grant permissions (optional)

Only needed if you enable `dismiss_notifications` in config (disabled by default):

1. Open **System Settings > Privacy & Security > Accessibility**
2. Enable **PrivilegesExtender**

### Launch

```bash
open ~/Applications/PrivilegesExtender.app
```

To start automatically at login, enable "Start at Login" from the menu bar icon.

## Uninstall

```bash
cd PrivilegesExtender

# Remove app (keep config and logs)
./scripts/uninstall.sh

# Remove everything (app, config, and logs)
./scripts/uninstall.sh --all
```

After uninstalling, remove the app from:
- System Settings > Privacy & Security > Accessibility
- System Settings > General > Login Items

## Configuration

Configuration is stored at `~/Library/Application Support/PrivilegesExtender/config.yaml`.

Edit from the app via **Open Configuration** in the menu bar, or edit the file directly. Changes are detected and reloaded automatically.

```yaml
reasons:
  - Update software
  - Installing software
  - Uninstalling software
  - Run script
  - Use software which requires elevation
  - Troubleshooting

durations:
  - label: "30 minutes"
    minutes: 30
  - label: "1 hour"
    minutes: 60
  - label: "2 hours"
    minutes: 120
  - label: "8 hours"
    minutes: 480
  - label: "24 hours"
    minutes: 1440
  - label: "Until logout"
    minutes: -1      # re-elevate until app quits
  - label: "Indefinitely"
    minutes: 0        # re-elevate forever

privileges_cli_path: "/Applications/Privileges.app/Contents/MacOS/PrivilegesCLI"
re_elevation_interval_seconds: 1500   # 25 min — re-elevate before 30-min MDM timeout
suppress_notifications: true          # freeze usernoted to suppress banners
dismiss_notifications: false           # AXUIElement-based dismissal after elevation (fallback, needs Accessibility)
log_file: "~/Library/Logs/privileges-extender.log"
```

### Special durations

- **Until logout** (minutes: -1) — keeps re-elevating until you quit the app
- **Indefinitely** (minutes: 0) — keeps re-elevating forever, even across app restarts

## Logs

Logs are written to `~/Library/Logs/privileges-extender.log`.

View logs from the app via **View Logs** in the menu bar, or:

```bash
tail -f ~/Library/Logs/privileges-extender.log
```

## Architecture

The project uses a two-target Swift Package Manager structure:

- **PrivilegesExtenderCore** (library) — config models, YAML parsing, privilege status parsing, elevation session state machine, duration/timer logic, logging. Uses Foundation + Yams. Cross-platform (macOS and Linux).
- **PrivilegesExtender** (executable) — AppKit menu bar UI, usernoted-based notification suppression, AXUIElement notification dismissal (fallback), SMAppService login items, SwiftUI log viewer. macOS only.

```
PrivilegesExtender/
├── Package.swift
├── Sources/
│   ├── PrivilegesExtenderCore/     # Cross-platform library
│   │   ├── Config.swift            # AppConfig, DurationOption models
│   │   ├── ConfigManager.swift     # YAML loading, file watching, reload
│   │   ├── ElevationSession.swift  # State machine: idle/active/expired
│   │   ├── Logger.swift            # File logger
│   │   └── PrivilegeManager.swift  # PrivilegesCLI wrapper
│   └── PrivilegesExtender/         # macOS menu bar app
│       ├── main.swift              # NSApplication setup
│       ├── AppDelegate.swift       # App lifecycle, timer management
│       ├── StatusBarController.swift
│       ├── MenuBuilder.swift       # Full menu from config
│       ├── NotificationSuppressor.swift # usernoted freeze/kill suppression
│       ├── NotificationDismisser.swift  # AXUIElement-based dismissal (fallback)
│       ├── PermissionChecker.swift
│       ├── LoginItemManager.swift  # SMAppService login items
│       └── LogViewerWindow.swift   # SwiftUI log viewer
├── Resources/
│   └── default-config.yaml
├── scripts/
│   ├── build.sh                    # Build .app bundle
│   ├── install.sh                  # Install to ~/Applications/
│   └── uninstall.sh                # Remove app
└── Tests/
    └── PrivilegesExtenderCoreTests/
```

## Requirements

- macOS 13+ (Ventura or later)
- SAP Privileges.app installed
- Accessibility permission (only needed if `dismiss_notifications` fallback is enabled)

## Legacy PoC

The original proof-of-concept (shell script + LaunchAgent + helper app) is preserved in the `legacy/` directory:

- `legacy/privileges-extend.sh` — main script
- `legacy/com.user.privileges-extender.plist` — LaunchAgent plist
- `legacy/helper/` — Swift helper app and AppleScript
- `legacy/install.sh` / `legacy/uninstall.sh` — old installers
