import AppKit
import PrivilegesExtenderCore

/// SF Symbol names for the status bar icon.
enum StatusBarIcon {
    /// Outline shield — displayed when the user has standard (non-elevated) privileges.
    static let standard = "lock.shield"
    /// Filled shield — displayed when privileges are actively elevated.
    static let elevated = "lock.shield.fill"
}

/// Owns the NSStatusItem and manages the menu bar icon and menu via MenuBuilder.
class StatusBarController {
    private let statusItem: NSStatusItem
    private var menuBuilder: MenuBuilder?
    private var config: AppConfig
    private let session: ElevationSession
    private var callbacks: MenuCallbacks
    private var loginItemChecker: () -> Bool

    init(
        config: AppConfig,
        session: ElevationSession,
        callbacks: MenuCallbacks,
        isLoginItemEnabled: @escaping () -> Bool = { false }
    ) {
        self.config = config
        self.session = session
        self.callbacks = callbacks
        self.loginItemChecker = isLoginItemEnabled

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Set initial icon based on current session state
        updateIcon()
        refreshMenu()
    }

    /// Rebuilds the menu to reflect current config and session state.
    func refreshMenu() {
        let builder = MenuBuilder(
            config: config,
            session: session,
            callbacks: callbacks,
            isLoginItemEnabled: loginItemChecker
        )
        // Keep a strong reference so action targets stay alive
        self.menuBuilder = builder
        statusItem.menu = builder.buildMenu()
    }

    /// Updates the config and refreshes the menu.
    func updateConfig(_ newConfig: AppConfig) {
        self.config = newConfig
        refreshMenu()
    }

    /// Updates the status bar icon and optional time label based on the current session state.
    func updateIcon() {
        guard let button = statusItem.button else { return }

        let symbolName: String
        let timeText: String?

        switch session.state {
        case .active:
            symbolName = StatusBarIcon.elevated
            timeText = formattedRemainingTime()
        case .idle, .expired:
            symbolName = StatusBarIcon.standard
            timeText = nil
        }

        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Privileges Extender"
        )

        // Show remaining time as compact text next to the icon (e.g., "27m", "1h 5m")
        button.title = timeText ?? ""
        // Add small spacing between image and title when title is present
        button.imagePosition = timeText != nil ? .imageLeading : .imageOnly
    }

    /// Refreshes both the icon and the menu (call after state changes).
    func refresh() {
        updateIcon()
        refreshMenu()
    }

    // MARK: - Private Helpers

    /// Returns a compact formatted string of the remaining elevation time, or nil for special durations.
    private func formattedRemainingTime() -> String? {
        guard let remaining = session.remainingTime() else {
            return nil
        }
        return ElevationSession.formatRemainingTime(remaining)
    }
}
