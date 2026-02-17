# Privileges Extender

A native macOS menu bar app that keeps SAP Privileges admin rights elevated and suppresses related notifications.

## Project structure

### Menu bar app (PrivilegesExtender/)
- `Package.swift` — SPM manifest: two targets + Yams dependency
- `Sources/PrivilegesExtenderCore/` — Cross-platform library (Foundation + Yams)
  - `Config.swift` — `AppConfig`, `DurationOption` Codable models
  - `ConfigManager.swift` — YAML loading, default config creation, `reload()` method
  - `ElevationSession.swift` — State machine: `.idle`, `.active`, `.expired`; tracks reason, duration, re-elevation timing
  - `Logger.swift` — Simple file logger (timestamped append)
  - `PrivilegeManager.swift` — Wraps `Foundation.Process` calls to PrivilegesCLI (`--status`, `--add`, `--remove`)
- `Sources/PrivilegesExtender/` — macOS executable (AppKit + SwiftUI)
  - `main.swift` — `NSApplication` setup with `AppDelegate`
  - `AppDelegate.swift` — App lifecycle, re-elevation timer, state coordination
  - `StatusBarController.swift` — `NSStatusItem` with SF Symbol icons (`lock.shield` / `lock.shield.fill`)
  - `MenuBuilder.swift` — Builds full `NSMenu` from `AppConfig` (reasons, durations, actions)
  - `NotificationDismisser.swift` — Dismisses Privileges notifications via `AXUIElement` API
  - `PermissionChecker.swift` — Checks Accessibility permission and PrivilegesCLI availability
  - `LoginItemManager.swift` — `SMAppService.mainApp` login item registration (macOS 13+)
  - `LogViewerWindow.swift` — SwiftUI log viewer hosted in `NSWindow`
- `Resources/default-config.yaml` — Default configuration file
- `scripts/build.sh` — Builds .app bundle with Info.plist and ad-hoc code signing
- `scripts/install.sh` — Installs to ~/Applications/, creates config directory
- `scripts/uninstall.sh` — Removes app, optionally config and logs
- `Tests/PrivilegesExtenderCoreTests/` — Unit tests for Core library

### Legacy PoC (legacy/)
- `legacy/privileges-extend.sh` — Original main script (re-elevates privileges, launches helper app)
- `legacy/com.user.privileges-extender.plist` — LaunchAgent plist (runs every 15 min)
- `legacy/helper/DismissNotifications.swift` — Swift helper app source
- `legacy/helper/dismiss-notifications.applescript` — AppleScript for notification dismissal
- `legacy/install.sh` / `legacy/uninstall.sh` — Old installers for the PoC
- `legacy/README.md` — Description of the legacy PoC

## Two-target architecture
- **PrivilegesExtenderCore** (library) — config models, YAML parsing, privilege status, elevation session, logging. Uses only Foundation + Yams. Compiles on macOS and Linux.
- **PrivilegesExtender** (executable) — AppKit menu bar UI, AXUIElement notification dismissal, SMAppService login items, SwiftUI log viewer. macOS only. Conditionally included in Package.swift via `#if os(macOS)`.
- **PrivilegesExtenderCoreTests** — Unit tests for Core. Runs on both macOS and Linux.

## Key paths
- SAP Privileges CLI: `/Applications/Privileges.app/Contents/MacOS/PrivilegesCLI`
- App bundle ID: `com.user.privileges-extender`
- Privileges Agent bundle ID: `corp.sap.privileges.agent`
- Privileges main bundle ID: `corp.sap.privileges`
- Config file: `~/Library/Application Support/PrivilegesExtender/config.yaml`
- App install location: `~/Applications/PrivilegesExtender.app`
- Log file: `~/Library/Logs/privileges-extender.log`

## Environment
- macOS 13+ (Ventura or later) required
- SAP Privileges v2.5.0 (bundle: corp.sap.privileges)
- Admin timeout: 30 minutes (MDM-enforced via ExpirationIntervalMax)
- Re-elevation interval: 25 minutes (default, configurable)
- Notifications: MDM-managed (AlertType: 2 = Banner, NotificationsEnabled: true)

## Build and test
- Build core library: `cd PrivilegesExtender && swift build --target PrivilegesExtenderCore`
- Run tests: `cd PrivilegesExtender && swift test`
- Build .app bundle: `cd PrivilegesExtender && ./scripts/build.sh`
- Tests run on both macOS and Linux (Core target only on Linux)

## Technical notes
- MDM enforces notification settings; user-level ncprefs.plist changes may be re-enforced at Jamf check-in
- App uses `AXUIElement` API for notification dismissal (not AppleScript) — requires Accessibility permission
- NotificationCenter UI hierarchy (macOS 26.2): `window "Notification Center" > group 1 > group 1 > scroll area 1 > groups`
- LSUIElement: true (background app, no Dock icon)
- Login items use `SMAppService.mainApp` (macOS 13+)
- Config file is watched via `DispatchSource.makeFileSystemObjectSource` and reloaded automatically
- Special duration values: -1 = until logout, 0 = indefinitely
