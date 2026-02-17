import Foundation
import ServiceManagement
import PrivilegesExtenderCore

/// Manages the "Start at Login" login item using SMAppService (macOS 13+).
final class LoginItemManager {
    private let service = SMAppService.mainApp
    private let logger: Logger?

    init(logger: Logger? = nil) {
        self.logger = logger
    }

    /// Returns whether the app is currently registered as a login item.
    func isEnabled() -> Bool {
        service.status == .enabled
    }

    /// Toggles the login item registration on or off.
    /// If currently enabled, unregisters; if disabled, registers.
    /// Calls the completion handler on the main queue when done.
    func toggle(completion: (() -> Void)? = nil) {
        if isEnabled() {
            service.unregister { [weak self] error in
                if let error = error {
                    self?.logger?.log("Login item unregister failed: \(error)")
                }
                DispatchQueue.main.async { completion?() }
            }
        } else {
            do {
                try service.register()
            } catch {
                logger?.log("Login item register failed: \(error)")
            }
            DispatchQueue.main.async { completion?() }
        }
    }
}
