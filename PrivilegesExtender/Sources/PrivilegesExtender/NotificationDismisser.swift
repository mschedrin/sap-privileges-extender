import AppKit
import ApplicationServices
import PrivilegesExtenderCore

/// Dismisses SAP Privileges notifications from the macOS Notification Center
/// using the AXUIElement accessibility API.
///
/// Requires Accessibility permission (System Settings > Privacy & Security > Accessibility).
///
/// NotificationCenter UI hierarchy (macOS 26.2):
///   window "Notification Center" > group 1 > group 1 > scroll area 1 > groups
///   Each notification group has static texts (heading, body) and actions (Close, etc.)
final class NotificationDismisser {
    private let logger: Logger?

    init(logger: Logger? = nil) {
        self.logger = logger
    }

    /// Finds and closes all Privileges-related notifications in Notification Center.
    /// Returns the number of notifications dismissed.
    @discardableResult
    func dismissPrivilegesNotifications() -> Int {
        guard let ncPID = notificationCenterPID() else {
            logger?.log("NotificationDismisser: NotificationCenter process not found")
            return 0
        }

        let ncApp = AXUIElementCreateApplication(ncPID)
        let notificationGroups = findNotificationGroups(in: ncApp)

        var found = 0
        var dismissed = 0

        for group in notificationGroups {
            guard let heading = firstStaticTextValue(of: group) else { continue }
            if heading.contains("Privileges") {
                found += 1
                if closeNotification(group) {
                    dismissed += 1
                }
            }
        }

        if found > 0 || dismissed > 0 {
            logger?.log("NotificationDismisser: found=\(found) dismissed=\(dismissed)")
        }

        return dismissed
    }

    // MARK: - Private

    /// Finds the PID of the NotificationCenter process.
    private func notificationCenterPID() -> pid_t? {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications
        return apps.first(where: { $0.bundleIdentifier == "com.apple.notificationcenterui" })?.processIdentifier
    }

    /// Navigates the AXUIElement hierarchy to find notification groups.
    /// Path: app > windows > "Notification Center" window > group 1 > group 1 > scroll areas > groups
    private func findNotificationGroups(in app: AXUIElement) -> [AXUIElement] {
        // Get windows
        guard let windows: [AXUIElement] = getAttribute(app, attribute: kAXWindowsAttribute) else {
            return []
        }

        var allGroups: [AXUIElement] = []

        for window in windows {
            // Check if this is the Notification Center window
            let title: String? = getAttribute(window, attribute: kAXTitleAttribute)
            if let title = title, title != "Notification Center" { continue }

            // Navigate: window > group 1 > group 1 > scroll areas > groups
            guard let topGroups: [AXUIElement] = getAttribute(window, attribute: kAXChildrenAttribute) else {
                continue
            }

            for topGroup in topGroups {
                guard let midGroups: [AXUIElement] = getAttribute(topGroup, attribute: kAXChildrenAttribute) else {
                    continue
                }

                for midGroup in midGroups {
                    // Find scroll areas within this group
                    let scrollAreas = childrenWithRole(midGroup, role: kAXScrollAreaRole as String)

                    for scrollArea in scrollAreas {
                        // Get notification groups within the scroll area
                        let groups = childrenWithRole(scrollArea, role: kAXGroupRole as String)
                        allGroups.append(contentsOf: groups)
                    }
                }
            }
        }

        return allGroups
    }

    /// Gets the value of the first static text child element.
    private func firstStaticTextValue(of element: AXUIElement) -> String? {
        guard let children: [AXUIElement] = getAttribute(element, attribute: kAXChildrenAttribute) else {
            return nil
        }

        for child in children {
            let role: String? = getAttribute(child, attribute: kAXRoleAttribute)
            if role == kAXStaticTextRole as String {
                return getAttribute(child, attribute: kAXValueAttribute)
            }
        }

        return nil
    }

    /// Attempts to close a notification by performing its "Close" action.
    private func closeNotification(_ element: AXUIElement) -> Bool {
        guard let actionNames = getActionNames(element) else { return false }

        for actionName in actionNames where actionName.contains("Close") {
            let result = AXUIElementPerformAction(element, actionName as CFString)
            return result == .success
        }

        // If no Close action found directly, try children for a Close button
        guard let children: [AXUIElement] = getAttribute(element, attribute: kAXChildrenAttribute) else {
            return false
        }

        for child in children where closeNotification(child) {
            return true
        }

        return false
    }

    // MARK: - AXUIElement Helpers

    /// Gets a typed attribute value from an AXUIElement.
    private func getAttribute<T>(_ element: AXUIElement, attribute: String) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }

    /// Gets all action names for an element.
    private func getActionNames(_ element: AXUIElement) -> [String]? {
        var names: CFArray?
        let result = AXUIElementCopyActionNames(element, &names)
        guard result == .success, let names = names else { return nil }
        return names as? [String]
    }

    /// Returns child elements that match a specific AX role.
    private func childrenWithRole(_ element: AXUIElement, role: String) -> [AXUIElement] {
        guard let children: [AXUIElement] = getAttribute(element, attribute: kAXChildrenAttribute) else {
            return []
        }
        return children.filter { child in
            let childRole: String? = getAttribute(child, attribute: kAXRoleAttribute)
            return childRole == role
        }
    }
}
