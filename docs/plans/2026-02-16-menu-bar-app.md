# Privileges Extender — Native macOS Menu Bar App

## Overview
- Replace the current PoC (shell script + LaunchAgent + helper app) with a proper native macOS menu bar application
- SwiftUI + AppKit: NSStatusItem/NSMenu for the menu bar, SwiftUI for any windows (log viewer)
- The app runs in the background with a menu bar icon that visually indicates privilege status
- Users can elevate privileges with predefined reasons and configurable durations
- Auto re-elevation keeps privileges alive for the chosen duration (re-invoking PrivilegesCLI before the 30-min MDM timeout)
- Notification dismissal via native AXUIElement API (no AppleScript)
- YAML configuration file for reasons, durations, and settings

## Context (from discovery)
- **Existing PoC files**: `privileges-extend.sh`, `helper/DismissNotifications.swift`, `helper/dismiss-notifications.applescript`, `com.user.privileges-extender.plist`, `install.sh`, `uninstall.sh`
- **PrivilegesCLI commands**: `--status` (check), `--add --reason "<reason>"` (elevate), `--remove` (revoke)
- **CLI path**: `/Applications/Privileges.app/Contents/MacOS/PrivilegesCLI`
- **MDM timeout**: 30 minutes (enforced via `ExpirationIntervalMax`)
- **Notification UI hierarchy**: `NotificationCenter > window "Notification Center" > group 1 > group 1 > scroll area 1 > groups`
- **Bundle IDs**: `corp.sap.privileges` (main), `corp.sap.privileges.agent` (agent)

## Architecture: Two-Target Split

The project uses two SPM targets to separate platform-independent business logic from macOS UI:

- **`PrivilegesExtenderCore`** (library) — config models, YAML parsing, privilege status parsing, elevation session state machine, duration/timer logic, logging. Uses only `Foundation` + `Yams`. Compiles and tests on both macOS and Linux.
- **`PrivilegesExtender`** (executable) — AppKit menu bar UI, AXUIElement notification dismissal, SMAppService login items, SwiftUI log viewer. Imports Core + macOS frameworks. Builds on macOS only.

Tests target depends on Core — all business logic is testable on both platforms (macOS native and Linux Docker via ralphex).

## Project Structure
```
PrivilegesExtender/
├── Package.swift
├── Sources/
│   ├── PrivilegesExtenderCore/
│   │   ├── Config.swift
│   │   ├── ConfigManager.swift
│   │   ├── PrivilegeManager.swift
│   │   ├── ElevationSession.swift
│   │   └── Logger.swift
│   └── PrivilegesExtender/
│       ├── main.swift
│       ├── AppDelegate.swift
│       ├── StatusBarController.swift
│       ├── MenuBuilder.swift
│       ├── NotificationDismisser.swift
│       ├── PermissionChecker.swift
│       ├── LoginItemManager.swift
│       └── LogViewerWindow.swift
├── Resources/
│   └── default-config.yaml
├── scripts/
│   ├── build.sh
│   └── install.sh
└── Tests/
    └── PrivilegesExtenderCoreTests/
        ├── ConfigTests.swift
        ├── ConfigManagerTests.swift
        ├── PrivilegeManagerTests.swift
        └── ElevationSessionTests.swift
```

## Menu Structure
```
[Shield Icon — filled when elevated, outline when standard]
├── ● Elevated — Update software (27 min remaining)   ← or "○ Standard User"
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
│   ├── Uninstalling software ▸
│   ├── Run script ▸
│   ├── Use software which requires elevation ▸
│   ├── Troubleshooting ▸
│   ├── ─────────────────────
│   └── Other...                ← opens text input dialog
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

## Configuration (~/Library/Application Support/PrivilegesExtender/config.yaml)
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
    minutes: -1      # special: re-elevate until app quits
  - label: "Indefinitely"
    minutes: 0        # special: re-elevate forever

privileges_cli_path: "/Applications/Privileges.app/Contents/MacOS/PrivilegesCLI"
re_elevation_interval_seconds: 1500   # 25 min — re-elevate before 30-min MDM timeout
dismiss_notifications: true
log_file: "~/Library/Logs/privileges-extender.log"
```

## Development Approach
- **Testing approach**: Regular (code first, then tests)
- **Build target**: macOS only (`swift build` / `swift test` on macOS)
- **Bonus**: Core library tests also run on Linux (`swift test --target PrivilegesExtenderCoreTests` in Docker)
- Complete each task fully before moving to the next
- Make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task
- **CRITICAL: all tests must pass before starting next task**
- **CRITICAL: update this plan file when scope changes during implementation**
- Run tests after each change

## Testing Strategy
- **Unit tests**: Required for every task — test business logic in Core (config parsing, elevation session state, privilege status parsing, duration calculations)
- **UI testing**: Manual verification of menu structure and icon states
- **Cross-platform tests**: Core tests run on both macOS and Linux (Docker). macOS-specific code in the app target is tested manually.
- **Note**: Some components (AXUIElement, SMAppService, NSMenu) are macOS-only and tested manually, not via unit tests

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Update plan if implementation deviates from original scope

## Implementation Steps

### Task 1: Set up SPM project with two-target architecture
- [x] Create `Package.swift` with:
  - Library target `PrivilegesExtenderCore` (Sources/PrivilegesExtenderCore) with dependency on `Yams`
  - Executable target `PrivilegesExtender` (Sources/PrivilegesExtender) depending on `PrivilegesExtenderCore`, platform restricted to macOS 13+
  - Test target `PrivilegesExtenderCoreTests` depending on `PrivilegesExtenderCore`
- [x] Create `Sources/PrivilegesExtender/main.swift` — set up `NSApplication` with `AppDelegate`
- [x] Create `Sources/PrivilegesExtender/AppDelegate.swift` — `NSApplicationDelegate` that creates an `NSStatusItem` with a placeholder menu (just "Quit")
- [x] Create `Sources/PrivilegesExtender/StatusBarController.swift` — owns the `NSStatusItem`, sets up the status bar button with an SF Symbol icon (`lock.shield`)
- [x] Create placeholder files in `Sources/PrivilegesExtenderCore/` (empty `Config.swift` with a public struct)
- [x] Verify the app builds with `swift build` and shows a menu bar icon when run
- [x] Create `Tests/PrivilegesExtenderCoreTests/` with a placeholder test
- [x] Run `swift test` — must pass before next task

### Task 2: Configuration system (Core)
- [x] Create `Sources/PrivilegesExtenderCore/Config.swift` — public `Codable` structs: `AppConfig` (reasons, durations, cli path, re-elevation interval, dismiss notifications, log file), `DurationOption` (label, minutes)
- [x] Create `Sources/PrivilegesExtenderCore/ConfigManager.swift` — loads config from `~/Library/Application Support/PrivilegesExtender/config.yaml`, creates directory and default config if missing, provides `reload()` method
- [x] Create `Resources/default-config.yaml` with the default configuration (reasons list, duration options, paths)
- [x] Write `Tests/PrivilegesExtenderCoreTests/ConfigTests.swift` — test Config model encoding/decoding (YAML round-trip), default values, special duration values (-1, 0)
- [x] Write `Tests/PrivilegesExtenderCoreTests/ConfigManagerTests.swift` — loading valid config, handling missing file (creates default), handling malformed YAML
- [x] Run `swift test` — must pass before next task

### Task 3: Privilege manager (Core)
- [x] Create `Sources/PrivilegesExtenderCore/PrivilegeManager.swift` — wraps `Foundation.Process` calls to PrivilegesCLI
- [x] Define `PrivilegeStatus` enum: `.elevated`, `.standard`, `.unknown`
- [x] Implement `checkStatus() -> PrivilegeStatus` — runs `--status`, parses output to determine state
- [x] Implement `elevate(reason: String) -> Result<Void, Error>` — runs `--add --reason "<reason>"`
- [x] Implement `revoke() -> Result<Void, Error>` — runs `--remove`
- [x] Create `Sources/PrivilegesExtenderCore/Logger.swift` — simple file logger (append timestamped entries)
- [x] Add logging for all privilege operations
- [x] Write `Tests/PrivilegesExtenderCoreTests/PrivilegeManagerTests.swift` — test status parsing logic (mock CLI output strings), error handling (CLI not found, non-zero exit code)
- [x] Run `swift test` — must pass before next task

### Task 4: Elevation session state machine (Core)
- [x] Create `Sources/PrivilegesExtenderCore/ElevationSession.swift` — tracks active elevation state: reason, start time, chosen duration, re-elevation interval
- [x] Define `ElevationState` enum: `.idle`, `.active(reason, startTime, duration)`, `.expired`
- [x] Implement `start(reason:duration:reElevationInterval:)` — transition to active, record start time
- [x] Implement duration expiry logic: `isExpired` computed property based on elapsed time vs chosen duration
- [x] Handle special durations: "Until logout" (minutes == -1, never expires while running), "Indefinitely" (minutes == 0, never expires)
- [x] Implement `stop()` — transition to idle
- [x] Implement `remainingTime` computed property for UI display (returns `TimeInterval?`)
- [x] Implement `shouldReElevate(now:)` — returns true if enough time passed since last elevation and session not expired
- [x] Write `Tests/PrivilegesExtenderCoreTests/ElevationSessionTests.swift` — test state transitions, expiry logic for all duration types, remaining time calculation, re-elevation timing
- [x] Run `swift test` — must pass before next task

### Task 5: Full menu bar UI with reasons and durations
- [x] Create `Sources/PrivilegesExtender/MenuBuilder.swift` — builds the full `NSMenu` from `AppConfig`
- [x] Build status item at top (shows current state: "Elevated — reason (time remaining)" or "Standard User")
- [x] Build "Elevate Now" submenu: for each reason in config, create a submenu with duration options from config
- [x] Add "Other..." item with text input dialog (NSAlert with NSTextField), then show duration picker
- [x] Add "Revoke Privileges" item
- [x] Add "View Logs", "Open Configuration" items
- [x] Add "Start at Login" toggle item (checkbox)
- [x] Add "Check Permissions" item
- [x] Add "Quit" item
- [x] Wire up `StatusBarController` to use `MenuBuilder` and refresh menu on config/state changes
- [x] Run `swift build` — must compile before next task

### Task 6: Wire elevation flow (app ↔ Core)
- [x] Connect menu item actions to `ElevationSession.start()` and `PrivilegeManager.elevate()`
- [x] Set up `Timer` in `AppDelegate` that checks `ElevationSession.shouldReElevate()` and calls `PrivilegeManager.elevate()` on tick
- [x] On timer tick: also dismiss notifications if configured, update menu bar status
- [x] Connect "Revoke Privileges" to `ElevationSession.stop()` and `PrivilegeManager.revoke()`
- [x] Update `StatusBarController` on state changes (refresh menu and icon)
- [x] Run `swift build` — must compile before next task

### Task 7: Status bar icon states
- [x] Define icon variants: `lock.shield` (standard), `lock.shield.fill` (elevated) — SF Symbols via `NSImage(systemSymbolName:)`
- [x] Update `StatusBarController` to switch icon based on `ElevationSession.state`
- [x] Optionally show remaining time as text next to icon (e.g., "27m") or in the status menu item
- [x] Update icon on timer ticks and on elevation/revoke actions
- [x] Run `swift build` — must compile before next task

### Task 8: Notification dismissal via AXUIElement
- [ ] Create `Sources/PrivilegesExtender/NotificationDismisser.swift`
- [ ] Implement `dismissPrivilegesNotifications()` using `AXUIElement` API:
  - Get `NotificationCenter` process via `NSWorkspace`
  - Navigate UI hierarchy: focused window → groups → scroll areas → notification groups
  - Find notifications with heading containing "Privileges"
  - Perform "Close" action on matching notifications
- [ ] Add logging for found/dismissed counts via `Logger`
- [ ] Call from elevation timer tick after each re-elevation (with configurable delay)
- [ ] Run `swift build` — must compile before next task

### Task 9: Login item management
- [ ] Create `Sources/PrivilegesExtender/LoginItemManager.swift`
- [ ] Implement using `SMAppService.mainApp` (macOS 13+) for login item registration
- [ ] Implement `isEnabled() -> Bool` and `toggle()` methods
- [ ] Wire to "Start at Login" menu item — show checkmark when enabled
- [ ] Run `swift build` — must compile before next task

### Task 10: Permission checker
- [ ] Create `Sources/PrivilegesExtender/PermissionChecker.swift`
- [ ] Check Accessibility permission: `AXIsProcessTrusted()` — prompt with `kAXTrustedCheckOptionPrompt` if not granted
- [ ] Check PrivilegesCLI availability: verify file exists and is executable
- [ ] Show results in an `NSAlert` dialog listing each permission and its status (checkmark/cross)
- [ ] Wire to "Check Permissions" menu item
- [ ] Run `swift build` — must compile before next task

### Task 11: Log viewer
- [ ] Create `Sources/PrivilegesExtender/LogViewerWindow.swift` — SwiftUI view hosted in `NSWindow`
- [ ] Read and display contents of the log file (tail, auto-refresh)
- [ ] Add basic controls: refresh button, clear log, scroll to bottom
- [ ] Wire to "View Logs" menu item — open/bring to front
- [ ] Run `swift build` — must compile before next task

### Task 12: "Open Configuration" and custom reason actions
- [ ] "Open Configuration" — open config.yaml in default editor via `NSWorkspace.shared.open(URL)`
- [ ] Watch config file for changes (`DispatchSource.makeFileSystemObjectSource`) and reload automatically via `ConfigManager.reload()`
- [ ] "Other..." — show `NSAlert` with `NSTextField`, use entered text as reason, then show duration submenu or picker
- [ ] Run `swift build` — must compile before next task

### Task 13: Build and bundle script
- [ ] Create `scripts/build.sh` — runs `swift build -c release`, creates `.app` bundle structure:
  - `PrivilegesExtender.app/Contents/MacOS/PrivilegesExtender` (binary)
  - `PrivilegesExtender.app/Contents/Info.plist` (bundle ID: `com.user.privileges-extender`, LSUIElement: true)
  - `PrivilegesExtender.app/Contents/Resources/default-config.yaml`
- [ ] Add `codesign --force --sign -` for ad-hoc code signing
- [ ] Verify built app runs correctly from the bundle
- [ ] Run `swift test` — must pass before next task

### Task 14: Install and uninstall scripts
- [ ] Create `scripts/install.sh` — copies `.app` to `~/Applications/`, creates config directory, copies default config if none exists
- [ ] Create `scripts/uninstall.sh` — removes app, optionally removes config and logs
- [ ] Update old `install.sh` / `uninstall.sh` or replace them
- [ ] Verify install/uninstall cycle works
- [ ] Run `swift test` — must pass before next task

### Task 15: Verify acceptance criteria
- [ ] Verify menu bar icon appears and changes state (elevated vs standard)
- [ ] Verify "Elevate Now" submenu shows all reasons from config with duration options
- [ ] Verify privilege elevation works with each duration option
- [ ] Verify auto re-elevation fires before 30-min timeout
- [ ] Verify duration expiry stops re-elevation
- [ ] Verify "Revoke Privileges" works
- [ ] Verify notification dismissal works (requires Accessibility permission)
- [ ] Verify "View Logs" opens log viewer
- [ ] Verify "Open Configuration" opens config file in editor
- [ ] Verify "Start at Login" toggle works
- [ ] Verify "Check Permissions" shows correct status
- [ ] Verify "Other..." shows text input dialog
- [ ] Run full test suite (`swift test`)
- [ ] Run `swiftlint` — all issues must be fixed

### Task 16: [Final] Update documentation
- [ ] Update `README.md` with new app usage, installation, and configuration docs
- [ ] Update `CLAUDE.md` with new project structure, two-target architecture, and technical details

*Note: ralphex automatically moves completed plans to `docs/plans/completed/`*

## Technical Details

### Two-Target Architecture
```swift
// Package.swift
let package = Package(
    name: "PrivilegesExtender",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "PrivilegesExtenderCore",
            dependencies: ["Yams"]
        ),
        .executableTarget(
            name: "PrivilegesExtender",
            dependencies: ["PrivilegesExtenderCore"]
        ),
        .testTarget(
            name: "PrivilegesExtenderCoreTests",
            dependencies: ["PrivilegesExtenderCore"]
        ),
    ]
)
```

**Core** (Foundation + Yams, cross-platform): Config, ConfigManager, PrivilegeManager, ElevationSession, Logger
**App** (AppKit + SwiftUI + ServiceManagement, macOS-only): AppDelegate, StatusBarController, MenuBuilder, NotificationDismisser, PermissionChecker, LoginItemManager, LogViewerWindow

### Elevation Flow
1. User clicks reason → duration in menu
2. `ElevationSession.start(reason, duration)` called
3. `PrivilegeManager.elevate(reason)` invoked (runs PrivilegesCLI `--add --reason`)
4. Timer scheduled at `re_elevation_interval_seconds` (default 25 min = 1500s)
5. On each tick: check `session.shouldReElevate()`, re-elevate, dismiss notifications, update UI
6. When `session.isExpired`: stop timer, revoke privileges, update UI
7. Special: "Until logout" (minutes == -1) → stop only on app quit; "Indefinitely" (minutes == 0) → never stop

### AXUIElement Notification Dismissal
```swift
// Pseudocode for notification dismissal
let nc = AXUIElementCreateApplication(notificationCenterPID)
// Navigate: window → group 1 → group 1 → scroll area → groups
// For each group: check static text for "Privileges"
// If match: find "Close" action and perform it
```

### Status Bar Icon
- Standard: `lock.shield` (outline)
- Elevated: `lock.shield.fill` (filled)
- Both use `NSImage(systemSymbolName:accessibilityDescription:)`

### Login Item (macOS 13+)
```swift
import ServiceManagement
let service = SMAppService.mainApp
try service.register()   // enable
service.unregister()     // disable
service.status == .enabled  // check
```

## Post-Completion

**Manual verification:**
- Grant Accessibility permission to the app in System Settings → Privacy & Security → Accessibility
- Test with actual SAP Privileges elevation and notification dismissal
- Verify re-elevation cycle over 30+ minutes
- Test "Until logout" by quitting and relaunching the app
- Test config file editing and auto-reload

**Migration from PoC:**
- Run `uninstall.sh` (old) to remove LaunchAgent and old helper app
- Install new app via `scripts/install.sh`
- Old PoC files can remain in repo for reference or be moved to `legacy/`
