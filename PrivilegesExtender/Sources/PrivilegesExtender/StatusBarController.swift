import AppKit
import PrivilegesExtenderCore

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

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "lock.shield",
                accessibilityDescription: "Privileges Extender"
            )
        }

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

    /// Updates the status bar icon based on the current session state.
    func updateIcon() {
        let symbolName: String
        switch session.state {
        case .active:
            symbolName = "lock.shield.fill"
        case .idle, .expired:
            symbolName = "lock.shield"
        }

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: "Privileges Extender"
            )
        }
    }

    /// Refreshes both the icon and the menu (call after state changes).
    func refresh() {
        updateIcon()
        refreshMenu()
    }
}
