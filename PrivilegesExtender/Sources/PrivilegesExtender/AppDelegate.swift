import AppKit
import PrivilegesExtenderCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var session: ElevationSession?
    private var configManager: ConfigManager?
    private var privilegeManager: PrivilegeManager?
    private var logger: Logger?
    private var reElevationTimer: Timer?
    private var notificationSuppressor: NotificationSuppressor?
    private var notificationDismisser: NotificationDismisser?
    private var loginItemManager: LoginItemManager?
    private var permissionChecker: PermissionChecker?
    private var logViewerWindow: LogViewerWindow?
    private var cachedConfig: AppConfig?
    private var configFileWatcher: DispatchSourceFileSystemObject?
    private var configFileDescriptor: Int32 = -1
    private var configFileWatcherRetries: Int = 0
    private let maxConfigFileWatcherRetries: Int = 30

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

        // Check if already elevated (e.g. elevated outside the app or app relaunched).
        // Use indefinite duration since we can't know the original intent. The user can
        // always revoke manually or start a new session with their desired duration.
        if let privilegeManager = privilegeManager {
            let status = privilegeManager.checkStatus()
            if status == .elevated {
                logger?.log("Already elevated on launch, tracking existing session as indefinite")
                let defaultDuration = DurationOption(label: "Indefinitely", minutes: 0)
                session.start(reason: "Pre-existing elevation", duration: defaultDuration)
                startReElevationTimer()
                statusBarController?.refresh()
            }
        }

        // Check permissions on startup and show dialog if something is missing
        if permissionChecker?.hasAllPermissions() == false {
            permissionChecker?.showPermissionStatus()
        }

        startConfigFileWatcher()
    }

    private func setupSubsystems() -> AppConfig {
        let configManager = ConfigManager()
        self.configManager = configManager
        let config: AppConfig
        do {
            config = try configManager.load()
        } catch {
            NSLog("PrivilegesExtender: failed to load config, using defaults: %@", "\(error)")
            config = ConfigManager.defaultConfig
        }

        let logPath = (config.logFile as NSString).expandingTildeInPath
        let logger = Logger(filePath: logPath)
        self.logger = logger

        let cliPath = (config.privilegesCLIPath as NSString).expandingTildeInPath
        self.privilegeManager = PrivilegeManager(cliPath: cliPath, logger: logger)
        self.session = ElevationSession(
            reElevationIntervalSeconds: TimeInterval(config.reElevationIntervalSeconds)
        )

        if config.suppressNotifications {
            self.notificationSuppressor = NotificationSuppressor(logger: logger)
        }

        if config.dismissNotifications {
            self.notificationDismisser = NotificationDismisser(logger: logger)
        }

        self.loginItemManager = LoginItemManager(logger: logger)
        self.permissionChecker = PermissionChecker(
            cliPath: config.privilegesCLIPath,
            checkAccessibility: config.dismissNotifications
        )
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
            onToggleAutoExtend: { [weak self] in
                self?.handleToggleAutoExtend()
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

    /// Wraps a privilege elevation call with notification suppression when configured.
    /// Freezes usernoted before the CLI call and kills it after so the banner never renders.
    private func elevateWithSuppression(reason: String) -> Result<Void, PrivilegeError> {
        guard let privilegeManager = privilegeManager else {
            return .failure(.launchFailed(description: "PrivilegeManager not initialized"))
        }

        if let suppressor = notificationSuppressor {
            var result: Result<Void, PrivilegeError> = .failure(.launchFailed(description: "Not executed"))
            suppressor.withSuppressedNotifications {
                result = privilegeManager.elevate(reason: reason)
            }
            return result
        } else {
            return privilegeManager.elevate(reason: reason)
        }
    }

    private func handleElevate(reason: String, duration: DurationOption) {
        guard let session = session else { return }

        let result = elevateWithSuppression(reason: reason)
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
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func handleToggleAutoExtend() {
        guard let session = session else { return }
        if session.isAutoExtendEnabled {
            session.stopAutoExtend()
            logger?.log("Auto-extend paused by user")
        } else {
            session.resumeAutoExtend()
            logger?.log("Auto-extend resumed by user")

            // Re-elevate immediately if overdue so MDM doesn't revoke before
            // the next timer tick (up to 30s away).
            if session.shouldReElevate(), let reason = session.activeReason {
                logger?.log("Re-elevating immediately on resume (overdue)")
                if case .success = elevateWithSuppression(reason: reason) {
                    session.recordReElevation()
                    logger?.log("Immediate re-elevation successful")
                }
            }
        }
        statusBarController?.refresh()
    }

    private func handleRevoke() {
        guard let session = session, let privilegeManager = privilegeManager else { return }

        // Stop the timer BEFORE the CLI call. Process.waitUntilExit() spins the
        // RunLoop in default mode, and the timer (registered in .common mode) can
        // fire during that spin. Without this, timerTick() would see the session
        // still active but privileges already revoked (standard), misinterpret it
        // as an MDM timeout, and immediately re-elevate.
        stopReElevationTimer()

        let result = privilegeManager.revoke()
        switch result {
        case .success:
            session.stop()
            logger?.log("Privileges revoked")
            statusBarController?.refresh()
        case .failure(let error):
            logger?.log("Revoke failed: \(error)")
            // Restart the timer since the session is still active
            startReElevationTimer()
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

        // Validate actual privilege status against session state.
        // If privileges were lost (e.g. MDM timeout during sleep), try to re-elevate
        // rather than assuming the user revoked externally.
        let actualStatus = privilegeManager.checkStatus()
        if case .active = session.state, actualStatus == .standard {
            if session.isExpired() {
                logger?.log("Session expired and privileges lost, stopping session")
                session.stop()
                stopReElevationTimer()
                statusBarController?.refresh()
                return
            }
            if !session.isAutoExtendEnabled {
                logger?.log("Privileges lost but auto-extend is paused, skipping re-elevation")
            } else if let reason = session.activeReason {
                logger?.log("Privileges lost (MDM timeout?), re-elevating")
                let result = elevateWithSuppression(reason: reason)
                switch result {
                case .success:
                    session.recordReElevation()
                    logger?.log("Re-elevation after privilege loss successful")
                case .failure(let error):
                    logger?.log("Re-elevation after privilege loss failed: \(error), stopping session")
                    session.stop()
                    stopReElevationTimer()
                    statusBarController?.refresh()
                    return
                }
            } else {
                logger?.log("Privileges lost with no active reason, stopping session")
                session.stop()
                stopReElevationTimer()
                statusBarController?.refresh()
                return
            }
        }

        // Check if the session has expired
        if session.isExpired() {
            logger?.log("Session expired, revoking privileges")
            let revokeResult = privilegeManager.revoke()
            switch revokeResult {
            case .success:
                session.stop()
                stopReElevationTimer()
                statusBarController?.refresh()
            case .failure(let error):
                // Revoke failed — keep the session active so the timer retries
                // on the next tick instead of leaving user elevated while the
                // UI shows standard.
                logger?.log("Failed to revoke on expiry: \(error), will retry")
                statusBarController?.refresh()
            }
            return
        }

        // Check if it's time to re-elevate
        if session.shouldReElevate() {
            if let reason = session.activeReason {
                logger?.log("Re-elevating privileges (reason: \(reason))")
                let result = elevateWithSuppression(reason: reason)
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

}

// MARK: - Config File Watcher

extension AppDelegate {
    private func startConfigFileWatcher(reloadAfterSetup: Bool = false) {
        // Cancel any existing watcher before setting up a new one to avoid
        // leaking file descriptors or crashing from a deallocated resumed DispatchSource.
        stopConfigFileWatcher()

        guard let configManager = configManager else { return }
        let path = configManager.path

        // If the config file doesn't exist yet (e.g. mid-atomic-save), retry after a delay
        // instead of calling load() which would create a default config and overwrite an
        // in-flight save. Pass reloadAfterSetup through so the config is reloaded once the
        // file appears and the watcher is successfully created.
        if !FileManager.default.fileExists(atPath: path) {
            configFileWatcherRetries += 1
            if configFileWatcherRetries > maxConfigFileWatcherRetries {
                logger?.log("Config file not found after \(maxConfigFileWatcherRetries) retries, giving up watcher setup")
                configFileWatcherRetries = 0
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startConfigFileWatcher(reloadAfterSetup: reloadAfterSetup)
            }
            return
        }
        configFileWatcherRetries = 0

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
        let capturedDescriptor = fileDescriptor
        source.setCancelHandler { [weak self] in
            close(capturedDescriptor)
            if self?.configFileDescriptor == capturedDescriptor {
                self?.configFileDescriptor = -1
            }
        }

        source.resume()
        configFileWatcher = source

        // When the watcher was restarted after a rename/delete (atomic save), the file
        // may have been replaced while no watcher was active. Reload now so we don't
        // miss the update.
        if reloadAfterSetup {
            reloadConfig()
        }
    }

    private func stopConfigFileWatcher() {
        configFileWatcher?.cancel()
        configFileWatcher = nil
    }

    private func handleConfigFileChange() {
        // Capture flags BEFORE any cancellation so they remain valid
        let flags = configFileWatcher?.data

        guard configManager != nil else { return }

        // If the file was deleted or renamed (common with atomic saves by text editors),
        // skip the reload to avoid overwriting the user's config with defaults.
        // Restart the watcher after a delay so the new file can appear.
        if let flags = flags,
           flags.contains(.delete) || flags.contains(.rename) {
            stopConfigFileWatcher()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startConfigFileWatcher(reloadAfterSetup: true)
            }
            return
        }

        reloadConfig()
    }

    private func reloadConfig() {
        guard let configManager = configManager else { return }

        // If the file doesn't exist (e.g. mid-atomic-save), skip the reload.
        // load() would create a default config and overwrite an in-flight save.
        // The config watcher will retry once the new file appears.
        guard FileManager.default.fileExists(atPath: configManager.path) else {
            return
        }

        do {
            let oldConfig = cachedConfig
            let newConfig = try configManager.reload()
            cachedConfig = newConfig
            logger?.log("Configuration reloaded from file change")
            statusBarController?.updateConfig(newConfig)

            // Update notification suppressor if the setting changed
            if newConfig.suppressNotifications != oldConfig?.suppressNotifications {
                if newConfig.suppressNotifications {
                    notificationSuppressor = NotificationSuppressor(logger: logger)
                } else {
                    notificationSuppressor = nil
                }
            }

            // Update notification dismisser if the setting changed
            if newConfig.dismissNotifications != oldConfig?.dismissNotifications {
                if newConfig.dismissNotifications {
                    notificationDismisser = NotificationDismisser(logger: logger)
                } else {
                    notificationDismisser = nil
                }
            }

            // Update privilege manager and permission checker if CLI path or dismiss setting changed
            let newCLIPath = (newConfig.privilegesCLIPath as NSString).expandingTildeInPath
            let oldCLIPath = oldConfig.map { ($0.privilegesCLIPath as NSString).expandingTildeInPath }
            if newCLIPath != oldCLIPath || newConfig.dismissNotifications != oldConfig?.dismissNotifications {
                if newCLIPath != oldCLIPath {
                    privilegeManager = PrivilegeManager(cliPath: newCLIPath, logger: logger)
                }
                permissionChecker = PermissionChecker(
                    cliPath: newConfig.privilegesCLIPath,
                    checkAccessibility: newConfig.dismissNotifications
                )
            }

            // Update re-elevation interval if changed
            let newInterval = TimeInterval(newConfig.reElevationIntervalSeconds)
            if newInterval != TimeInterval(oldConfig?.reElevationIntervalSeconds ?? 0) {
                session?.reElevationIntervalSeconds = max(60, newInterval)
            }
        } catch {
            logger?.log("Failed to reload config: \(error)")
        }
    }
}
