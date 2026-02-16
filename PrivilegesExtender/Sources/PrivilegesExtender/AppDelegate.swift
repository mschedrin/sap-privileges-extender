import AppKit
import PrivilegesExtenderCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var session: ElevationSession?
    private var configManager: ConfigManager?
    private var privilegeManager: PrivilegeManager?
    private var logger: Logger?
    private var reElevationTimer: Timer?

    /// How often the timer ticks to check session state (seconds).
    /// Short interval so the UI countdown stays responsive.
    private let timerInterval: TimeInterval = 30

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

    func applicationWillTerminate(_ notification: Notification) {
        stopReElevationTimer()
    }

    // MARK: - Actions

    private func handleElevate(reason: String, duration: DurationOption) {
        guard let session = session, let privilegeManager = privilegeManager else { return }

        let result = privilegeManager.elevate(reason: reason)
        switch result {
        case .success:
            session.start(reason: reason, duration: duration)
            logger?.log("Elevated with reason: \(reason), duration: \(duration.label)")
            startReElevationTimer()
            statusBarController?.refresh()
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
            logger?.log("Privileges revoked")
            stopReElevationTimer()
            statusBarController?.refresh()
        case .failure(let error):
            logger?.log("Revoke failed: \(error)")
        }
    }

    // MARK: - Re-elevation Timer

    private func startReElevationTimer() {
        stopReElevationTimer()
        reElevationTimer = Timer.scheduledTimer(
            timeInterval: timerInterval,
            target: self,
            selector: #selector(timerTick),
            userInfo: nil,
            repeats: true
        )
        // Allow timer to fire even during menu tracking and other modal run loop modes
        RunLoop.current.add(reElevationTimer!, forMode: .common)
    }

    private func stopReElevationTimer() {
        reElevationTimer?.invalidate()
        reElevationTimer = nil
    }

    @objc private func timerTick() {
        guard let session = session, let privilegeManager = privilegeManager else { return }
        let config = configManager?.config

        // Check if the session has expired
        if session.checkExpiry() {
            logger?.log("Session expired, revoking privileges")
            let _ = privilegeManager.revoke()
            stopReElevationTimer()
            statusBarController?.refresh()
            return
        }

        // Check if it's time to re-elevate
        if session.shouldReElevate() {
            if let reason = session.activeReason {
                logger?.log("Re-elevating privileges (reason: \(reason))")
                let result = privilegeManager.elevate(reason: reason)
                switch result {
                case .success:
                    session.recordReElevation()
                    logger?.log("Re-elevation successful")
                case .failure(let error):
                    logger?.log("Re-elevation failed: \(error)")
                }
            }
        }

        // Dismiss notifications if configured
        if config?.dismissNotifications ?? false {
            // NotificationDismisser will be implemented in Task 8
            // For now, just a placeholder call site
        }

        // Refresh the menu to update remaining time display
        statusBarController?.refresh()
    }
}
