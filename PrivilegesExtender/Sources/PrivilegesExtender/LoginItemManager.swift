import ServiceManagement

/// Manages the "Start at Login" login item using SMAppService (macOS 13+).
final class LoginItemManager {
    private let service = SMAppService.mainApp

    /// Returns whether the app is currently registered as a login item.
    func isEnabled() -> Bool {
        service.status == .enabled
    }

    /// Toggles the login item registration on or off.
    /// If currently enabled, unregisters; if disabled, registers.
    func toggle() {
        if isEnabled() {
            service.unregister { _ in }
        } else {
            do {
                try service.register()
            } catch {
                // Registration failed — logged by caller if needed
            }
        }
    }
}
