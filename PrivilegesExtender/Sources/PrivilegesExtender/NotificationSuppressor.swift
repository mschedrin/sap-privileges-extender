import Foundation
import PrivilegesExtenderCore

/// Suppresses SAP Privileges notifications by freezing `usernoted` (the macOS
/// notification display daemon) with SIGSTOP before elevation, then killing it
/// with SIGKILL after. launchd restarts usernoted fresh without the queued
/// notification, so no banner ever appears.
final class NotificationSuppressor {
    private let logger: Logger?

    /// PIDs of usernoted processes frozen by the current suppression cycle.
    private var frozenPIDs: [pid_t] = []

    init(logger: Logger? = nil) {
        self.logger = logger
    }

    /// Freezes usernoted, executes the block, then kills the frozen usernoted
    /// so it restarts fresh without any queued notifications.
    func withSuppressedNotifications(execute block: () -> Void) {
        freezeUsernoted()
        defer { killFrozenUsernoted() }
        block()
    }

    // MARK: - Private

    /// Finds all usernoted processes and freezes them with SIGSTOP.
    private func freezeUsernoted() {
        let pids = pgrepUsernoted()
        guard !pids.isEmpty else {
            logger?.log("NotificationSuppressor: no usernoted process found")
            return
        }

        for pid in pids {
            kill(pid, SIGSTOP)
        }
        frozenPIDs = pids
        logger?.log("NotificationSuppressor: froze usernoted (PIDs: \(pids))")
    }

    /// Kills previously frozen usernoted processes. launchd restarts them fresh
    /// without the queued notification.
    private func killFrozenUsernoted() {
        guard !frozenPIDs.isEmpty else { return }

        for pid in frozenPIDs {
            kill(pid, SIGKILL)
        }
        logger?.log("NotificationSuppressor: killed frozen usernoted (PIDs: \(frozenPIDs))")
        frozenPIDs = []
    }

    /// Returns PIDs of all running usernoted processes.
    private func pgrepUsernoted() -> [pid_t] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["usernoted"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").compactMap { pid_t($0) }
    }
}
