import AppKit
import PrivilegesExtenderCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var session: ElevationSession?
    private var configManager: ConfigManager?
    private var privilegeManager: PrivilegeManager?
    private var logger: Logger?
    private var reElevationTimer: Timer?
    private var notificationDismisser: NotificationDismisser?
    private var loginItemManager: LoginItemManager?
    private var permissionChecker: PermissionChecker?
    private var logViewerWindow: LogViewerWindow?
    private var configFileWatcher: DispatchSourceFileSystemObject?
    private var configFileDescriptor: Int32 = -1

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

        // Set up notification dismisser
        if config.dismissNotifications {
            self.notificationDismisser = NotificationDismisser(logger: logger)
        }

        // Set up login item manager
        let loginItemManager = LoginItemManager()
        self.loginItemManager = loginItemManager

        // Set up permission checker
        let permissionChecker = PermissionChecker(cliPath: config.privilegesCLIPath)
        self.permissionChecker = permissionChecker

        // Set up log viewer window
        let logViewerWindow = LogViewerWindow(logger: logger)
        self.logViewerWindow = logViewerWindow

        // Set up menu callbacks
        let callbacks = MenuCallbacks(
            onElevate: { [weak self] reason, duration in
                self?.handleElevate(reason: reason, duration: duration)
            },
            onRevoke: { [weak self] in
                self?.handleRevoke()
            },
            onViewLogs: { [weak logViewerWindow] in
                logViewerWindow?.show()
            },
            onOpenConfiguration: { [weak self] in
                self?.openConfiguration()
            },
            onToggleLoginItem: { [weak self] in
                self?.loginItemManager?.toggle()
                self?.statusBarController?.refresh()
            },
            onCheckPermissions: { [weak permissionChecker] in
                permissionChecker?.showPermissionStatus()
            }
        )

        // Create status bar controller
        statusBarController = StatusBarController(
            config: config,
            session: session,
            callbacks: callbacks,
            isLoginItemEnabled: { [weak loginItemManager] in
                loginItemManager?.isEnabled() ?? false
            }
        )

        // Start watching config file for changes
        startConfigFileWatcher()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopReElevationTimer()
        stopConfigFileWatcher()
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
            notificationDismisser?.dismissPrivilegesNotifications()
        }

        // Refresh the menu to update remaining time display
        statusBarController?.refresh()
    }

    // MARK: - Open Configuration

    private func openConfiguration() {
        guard let configManager = configManager else { return }
        let path = configManager.path
        let url = URL(fileURLWithPath: path)

        // Ensure the config file exists before trying to open it
        if !FileManager.default.fileExists(atPath: path) {
            do {
                _ = try configManager.load()
            } catch {
                logger?.log("Failed to create default config: \(error)")
            }
        }

        NSWorkspace.shared.open(url)
    }

    // MARK: - Config File Watcher

    private func startConfigFileWatcher() {
        guard let configManager = configManager else { return }
        let path = configManager.path

        // Ensure the config file exists so we can open a file descriptor for it
        if !FileManager.default.fileExists(atPath: path) {
            do {
                _ = try configManager.load()
            } catch {
                logger?.log("Failed to create config for watcher: \(error)")
                return
            }
        }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            logger?.log("Failed to open config file for watching: \(path)")
            return
        }
        configFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.handleConfigFileChange()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.configFileDescriptor, fd >= 0 {
                close(fd)
                self?.configFileDescriptor = -1
            }
        }

        source.resume()
        configFileWatcher = source
    }

    private func stopConfigFileWatcher() {
        configFileWatcher?.cancel()
        configFileWatcher = nil
    }

    private func handleConfigFileChange() {
        guard let configManager = configManager else { return }

        do {
            let newConfig = try configManager.reload()
            logger?.log("Configuration reloaded from file change")
            statusBarController?.updateConfig(newConfig)
        } catch {
            logger?.log("Failed to reload config: \(error)")
        }

        // If the file was deleted or renamed, restart the watcher
        // (the old file descriptor may no longer be valid)
        if let flags = configFileWatcher?.data,
           flags.contains(.delete) || flags.contains(.rename) {
            stopConfigFileWatcher()
            // Delay restart slightly to allow the new file to appear (e.g., atomic save)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startConfigFileWatcher()
            }
        }
    }
}
