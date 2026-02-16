import AppKit
import PrivilegesExtenderCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var session: ElevationSession?
    private var configManager: ConfigManager?
    private var privilegeManager: PrivilegeManager?
    private var logger: Logger?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load configuration
        let configManager = ConfigManager()
        self.configManager = configManager
        let config = configManager.config

        // Set up logger
        let logPath = (config.logFile as NSString).expandingTildeInPath
        let logger = Logger(filePath: logPath)
        self.logger = logger

        // Set up privilege manager
        let privilegeManager = PrivilegeManager(cliPath: config.privilegesCLIPath, logger: logger)
        self.privilegeManager = privilegeManager

        // Set up elevation session
        let session = ElevationSession(
            reElevationIntervalSeconds: TimeInterval(config.reElevationIntervalSeconds)
        )
        self.session = session

        // Set up menu callbacks
        let callbacks = MenuCallbacks(
            onElevate: { [weak self] reason, duration in
                self?.handleElevate(reason: reason, duration: duration)
            },
            onRevoke: { [weak self] in
                self?.handleRevoke()
            },
            onViewLogs: {
                // Placeholder — wired in Task 11
            },
            onOpenConfiguration: {
                // Placeholder — wired in Task 12
            },
            onToggleLoginItem: {
                // Placeholder — wired in Task 9
            },
            onCheckPermissions: {
                // Placeholder — wired in Task 10
            }
        )

        // Create status bar controller
        statusBarController = StatusBarController(
            config: config,
            session: session,
            callbacks: callbacks
        )
    }

    // MARK: - Actions

    private func handleElevate(reason: String, duration: DurationOption) {
        guard let session = session, let privilegeManager = privilegeManager else { return }

        let result = privilegeManager.elevate(reason: reason)
        switch result {
        case .success:
            session.start(reason: reason, duration: duration)
            statusBarController?.refresh()
            logger?.log("Elevated with reason: \(reason), duration: \(duration.label)")
        case .failure(let error):
            logger?.log("Elevation failed: \(error)")
        }
    }

    private func handleRevoke() {
        guard let session = session, let privilegeManager = privilegeManager else { return }

        let result = privilegeManager.revoke()
        switch result {
        case .success:
            session.stop()
            statusBarController?.refresh()
            logger?.log("Privileges revoked")
        case .failure(let error):
            logger?.log("Revoke failed: \(error)")
        }
    }
}
