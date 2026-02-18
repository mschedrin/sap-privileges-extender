import AppKit
import PrivilegesExtenderCore

/// Checks required system permissions and shows results to the user.
final class PermissionChecker {
    private let cliPath: String
    private let isAccessibilityTrusted: () -> Bool
    private let isFileExecutable: (String) -> Bool

    init(
        cliPath: String,
        isAccessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        isFileExecutable: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.cliPath = cliPath
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.isFileExecutable = isFileExecutable
    }

    /// Returns `true` when both Accessibility and PrivilegesCLI are available.
    func hasAllPermissions() -> Bool {
        isAccessibilityTrusted() && checkCLIAvailable()
    }

    /// Checks all required permissions and displays results in an alert dialog.
    func showPermissionStatus() {
        let accessibilityGranted = isAccessibilityTrusted()
        let cliAvailable = checkCLIAvailable()

        let alert = NSAlert()
        alert.messageText = "Permission Status"
        alert.alertStyle = .informational

        var lines: [String] = []
        let accessStatus = accessibilityGranted ? "Granted" : "Not Granted"
        lines.append("\(statusIcon(accessibilityGranted)) Accessibility: \(accessStatus)")
        lines.append("\(statusIcon(cliAvailable)) PrivilegesCLI: \(cliAvailable ? "Available" : "Not Found")")

        let allGood = accessibilityGranted && cliAvailable
        if allGood {
            lines.append("")
            lines.append("All permissions are configured correctly.")
        } else {
            lines.append("")
            if !accessibilityGranted {
                lines.append("Grant Accessibility in System Settings > Privacy & Security > Accessibility.")
            }
            if !cliAvailable {
                lines.append("PrivilegesCLI not found at: \(cliPath)")
            }
        }

        alert.informativeText = lines.joined(separator: "\n")

        if !accessibilityGranted {
            alert.addButton(withTitle: "Open Accessibility Settings")
            alert.addButton(withTitle: "OK")
        } else {
            alert.addButton(withTitle: "OK")
        }

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        // If user clicked "Open Accessibility Settings"
        if !accessibilityGranted && response == .alertFirstButtonReturn {
            promptForAccessibility()
        }
    }

    /// Checks whether PrivilegesCLI exists and is executable.
    private func checkCLIAvailable() -> Bool {
        let path = (cliPath as NSString).expandingTildeInPath
        return isFileExecutable(path)
    }

    /// Prompts the user to grant Accessibility permission via the system dialog.
    private func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func statusIcon(_ granted: Bool) -> String {
        granted ? "✓" : "✗"
    }
}
