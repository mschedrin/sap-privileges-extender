import AppKit
import PrivilegesExtenderCore

/// Callback types for menu actions.
struct MenuCallbacks {
    var onElevate: ((_ reason: String, _ duration: DurationOption) -> Void)?
    var onRevoke: (() -> Void)?
    var onViewLogs: (() -> Void)?
    var onOpenConfiguration: (() -> Void)?
    var onToggleLoginItem: (() -> Void)?
    var onCheckPermissions: (() -> Void)?
}

/// Builds the full NSMenu for the status bar from AppConfig and ElevationSession state.
final class MenuBuilder: NSObject {
    private let config: AppConfig
    private let session: ElevationSession
    private let callbacks: MenuCallbacks
    private let isLoginItemEnabled: () -> Bool

    init(
        config: AppConfig,
        session: ElevationSession,
        callbacks: MenuCallbacks,
        isLoginItemEnabled: @escaping () -> Bool = { false }
    ) {
        self.config = config
        self.session = session
        self.callbacks = callbacks
        self.isLoginItemEnabled = isLoginItemEnabled
    }

    /// Builds and returns the complete NSMenu.
    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Status item
        let statusItem = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(NSMenuItem.separator())

        addElevationItems(to: menu)
        menu.addItem(NSMenuItem.separator())

        addUtilityItems(to: menu)
        menu.addItem(NSMenuItem.separator())

        addSettingsItems(to: menu)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    private func addElevationItems(to menu: NSMenu) {
        let elevateItem = NSMenuItem(title: "Elevate Now", action: nil, keyEquivalent: "")
        elevateItem.submenu = buildElevateSubmenu()
        menu.addItem(elevateItem)

        let revokeItem = NSMenuItem(title: "Revoke Privileges", action: #selector(revokeAction), keyEquivalent: "")
        revokeItem.target = self
        revokeItem.isEnabled = isElevated
        menu.addItem(revokeItem)
    }

    private func addUtilityItems(to menu: NSMenu) {
        let viewLogsItem = NSMenuItem(title: "View Logs", action: #selector(viewLogsAction), keyEquivalent: "")
        viewLogsItem.target = self
        menu.addItem(viewLogsItem)

        let openConfigItem = NSMenuItem(
            title: "Open Configuration", action: #selector(openConfigAction), keyEquivalent: ""
        )
        openConfigItem.target = self
        menu.addItem(openConfigItem)
    }

    private func addSettingsItems(to menu: NSMenu) {
        let loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLoginAction), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(loginItem)

        let checkPermItem = NSMenuItem(
            title: "Check Permissions", action: #selector(checkPermissionsAction), keyEquivalent: ""
        )
        checkPermItem.target = self
        menu.addItem(checkPermItem)
    }

    // MARK: - Status Text

    private var isElevated: Bool {
        if case .active = session.state { return true }
        return false
    }

    private func statusText() -> String {
        switch session.state {
        case .active(let reason, _, let duration):
            if let remaining = session.remainingTime() {
                let formattedTime = formatRemainingTime(remaining)
                return "● Elevated — \(reason) (\(formattedTime) remaining)"
            } else {
                // Special duration (until logout or indefinitely)
                return "● Elevated — \(reason) (\(duration.label))"
            }
        case .idle, .expired:
            return "○ Standard User"
        }
    }

    private func formatRemainingTime(_ seconds: TimeInterval) -> String {
        ElevationSession.formatRemainingTime(seconds)
    }

    // MARK: - Elevate Submenu

    private func buildElevateSubmenu() -> NSMenu {
        let submenu = NSMenu()

        for reason in config.reasons {
            let reasonItem = NSMenuItem(title: reason, action: nil, keyEquivalent: "")
            let durationSubmenu = buildDurationSubmenu(for: reason)
            reasonItem.submenu = durationSubmenu
            submenu.addItem(reasonItem)
        }

        submenu.addItem(NSMenuItem.separator())

        // "Other..." item
        let otherItem = NSMenuItem(
            title: "Other...",
            action: #selector(otherReasonAction),
            keyEquivalent: ""
        )
        otherItem.target = self
        submenu.addItem(otherItem)

        return submenu
    }

    private func buildDurationSubmenu(for reason: String) -> NSMenu {
        let submenu = NSMenu()

        for duration in config.durations {
            let item = NSMenuItem(
                title: duration.label,
                action: #selector(elevateAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = ElevateChoice(reason: reason, duration: duration)
            submenu.addItem(item)
        }

        return submenu
    }

    // MARK: - Actions

    @objc private func elevateAction(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? ElevateChoice else { return }
        callbacks.onElevate?(choice.reason, choice.duration)
    }

    @objc private func revokeAction() {
        callbacks.onRevoke?()
    }

    @objc private func viewLogsAction() {
        callbacks.onViewLogs?()
    }

    @objc private func openConfigAction() {
        callbacks.onOpenConfiguration?()
    }

    @objc private func toggleLoginAction() {
        callbacks.onToggleLoginItem?()
    }

    @objc private func checkPermissionsAction() {
        callbacks.onCheckPermissions?()
    }

    @objc private func otherReasonAction() {
        let alert = NSAlert()
        alert.messageText = "Enter Reason"
        alert.informativeText = "Provide a reason for elevating privileges:"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = "Reason for elevation"
        alert.accessoryView = textField

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let reason = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty, !reason.hasPrefix("-") else { return }

        showDurationPicker(for: reason)
    }

    private func showDurationPicker(for reason: String) {
        let alert = NSAlert()
        alert.messageText = "Select Duration"
        alert.informativeText = "How long should privileges be elevated for \"\(reason)\"?"

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 28), pullsDown: false)
        for duration in config.durations {
            popup.addItem(withTitle: duration.label)
        }
        alert.accessoryView = popup

        alert.addButton(withTitle: "Elevate")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let index = popup.indexOfSelectedItem
        guard index >= 0, index < config.durations.count else { return }

        let duration = config.durations[index]
        callbacks.onElevate?(reason, duration)
    }
}

/// Holds the reason/duration pair for a menu item's representedObject.
private final class ElevateChoice: NSObject {
    let reason: String
    let duration: DurationOption

    init(reason: String, duration: DurationOption) {
        self.reason = reason
        self.duration = duration
    }
}
