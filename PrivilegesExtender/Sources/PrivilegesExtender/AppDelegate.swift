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
    private var cachedConfig: AppConfig?
    private var configFileWatcher: DispatchSourceFileSystemObject?
    private var configFileDescriptor: Int32 = -1

    /// How often the timer ticks to check session state (seconds).
    /// Short interval so the UI countdown stays responsive.
    private let timerInterval: TimeInterval = 30

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = setupSubsystems()
        cachedConfig = config
        let callbacks = buildMenuCallbacks()

        guard let session = session else {
            fatalError("ElevationSession was not initialized in setupSubsystems()")
        }

        statusBarController = StatusBarController(
            config: config,
            session: session,
            callbacks: callbacks,
            isLoginItemEnabled: { [weak self] in
                self?.loginItemManager?.isEnabled() ?? false
            }
        )

        startConfigFileWatcher()
    }

    private func setupSubsystems() -> AppConfig {
        let configManager = ConfigManager()
        self.configManager = configManager
        let config = configManager.config

        let logPath = (config.logFile as NSString).expandingTildeInPath
        let logger = Logger(filePath: logPath)
        self.logger = logger

        let cliPath = (config.privilegesCLIPath as NSString).expandingTildeInPath
        self.privilegeManager = PrivilegeManager(cliPath: cliPath, logger: logger)
        self.session = ElevationSession(
            reElevationIntervalSeconds: TimeInterval(config.reElevationIntervalSeconds)
        )

        if config.dismissNotifications {
            self.notificationDismisser = NotificationDismisser(logger: logger)
        }

        self.loginItemManager = LoginItemManager(logger: logger)
        self.permissionChecker = PermissionChecker(cliPath: config.privilegesCLIPath)
        self.logViewerWindow = LogViewerWindow(logger: logger)

        return config
    }

    private func buildMenuCallbacks() -> MenuCallbacks {
        MenuCallbacks(
            onElevate: { [weak self] reason, duration in
                self?.handleElevate(reason: reason, duration: duration)
            },
            onRevoke: { [weak self] in
                self?.handleRevoke()
            },
            onViewLogs: { [weak self] in
                self?.logViewerWindow?.show()
            },
            onOpenConfiguration: { [weak self] in
                self?.openConfiguration()
            },
            onToggleLoginItem: { [weak self] in
                self?.loginItemManager?.toggle { [weak self] in
                    self?.statusBarController?.refresh()
                }
            },
            onCheckPermissions: { [weak self] in
                self?.permissionChecker?.showPermissionStatus()
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Revoke privileges for "Until logout" sessions on app quit
        if let session = session, let duration = session.activeDuration,
           duration.isUntilLogout {
            logger?.log("App terminating, revoking 'Until logout' session")
            _ = privilegeManager?.revoke()
            session.stop()
        }

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

            // Dismiss notifications shortly after elevation to catch the banner
            if cachedConfig?.dismissNotifications ?? false {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.notificationDismisser?.dismissPrivilegesNotifications()
                }
            }
        case .failure(let error):
            logger?.log("Elevation failed: \(error)")
            showElevationFailureAlert(error)
        }
    }

    private func showElevationFailureAlert(_ error: PrivilegeError) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Elevation Failed"
        alert.informativeText = switch error {
        case .cliNotFound(let path): "PrivilegesCLI not found at: \(path)"
        case .executionFailed(let code, let out): "CLI exited with code \(code).\n\(out)"
        case .unexpectedOutput(let out): "Unexpected output: \(out)"
        case .launchFailed(let desc): "Failed to launch CLI: \(desc)"
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        // Non-scheduling initializer + .common mode so the timer fires during menu tracking too
        let timer = Timer(
            timeInterval: timerInterval,
            target: self,
            selector: #selector(timerTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.current.add(timer, forMode: .common)
        reElevationTimer = timer
    }

    private func stopReElevationTimer() {
        reElevationTimer?.invalidate()
        reElevationTimer = nil
    }

    @objc private func timerTick() {
        guard let session = session, let privilegeManager = privilegeManager else { return }
        let config = cachedConfig

        // Check if the session has expired (transitions to .expired state)
        if session.checkExpiry() {
            logger?.log("Session expired, revoking privileges")
            let revokeResult = privilegeManager.revoke()
            if case .failure(let error) = revokeResult {
                logger?.log("Failed to revoke on expiry: \(error)")
            }
            session.stop()
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

        let fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            logger?.log("Failed to open config file for watching: \(path)")
            return
        }
        configFileDescriptor = fileDescriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.handleConfigFileChange()
        }

        // Capture the descriptor by value so the cancel handler closes the correct one,
        // even if startConfigFileWatcher() has already opened a new descriptor.
        let fd = fileDescriptor
        source.setCancelHandler { [weak self] in
            close(fd)
            if self?.configFileDescriptor == fd {
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
        // Capture flags BEFORE any cancellation so they remain valid
        let flags = configFileWatcher?.data

        guard let configManager = configManager else { return }

        do {
            let oldConfig = cachedConfig
            let newConfig = try configManager.reload()
            cachedConfig = newConfig
            logger?.log("Configuration reloaded from file change")
            statusBarController?.updateConfig(newConfig)

            // Update notification dismisser if the setting changed
            if newConfig.dismissNotifications != oldConfig?.dismissNotifications {
                if newConfig.dismissNotifications {
                    notificationDismisser = NotificationDismisser(logger: logger)
                } else {
                    notificationDismisser = nil
                }
            }

            // Update privilege manager if CLI path changed
            let newCLIPath = (newConfig.privilegesCLIPath as NSString).expandingTildeInPath
            let oldCLIPath = oldConfig.map { ($0.privilegesCLIPath as NSString).expandingTildeInPath }
            if newCLIPath != oldCLIPath {
                privilegeManager = PrivilegeManager(cliPath: newCLIPath, logger: logger)
            }
        } catch {
            logger?.log("Failed to reload config: \(error)")
        }

        // If the file was deleted or renamed, restart the watcher
        // (the old file descriptor may no longer be valid)
        if let flags = flags,
           flags.contains(.delete) || flags.contains(.rename) {
            stopConfigFileWatcher()
            // Delay restart slightly to allow the new file to appear (e.g., atomic save)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startConfigFileWatcher()
            }
        }
    }
}
