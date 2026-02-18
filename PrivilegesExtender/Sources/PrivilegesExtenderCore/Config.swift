import Foundation

/// Configuration model for the Privileges Extender application.
public struct AppConfig: Codable, Equatable, Sendable {
    public var reasons: [String]
    public var durations: [DurationOption]
    public var privilegesCLIPath: String
    public var reElevationIntervalSeconds: Int
    public var suppressNotifications: Bool
    public var dismissNotifications: Bool
    public var logFile: String

    public static let defaultReasons: [String] = [
        "Update software",
        "Installing software",
        "Uninstalling software",
        "Run script",
        "Use software which requires elevation",
        "Troubleshooting"
    ]

    public static let defaultDurations: [DurationOption] = [
        DurationOption(label: "30 minutes", minutes: 30),
        DurationOption(label: "1 hour", minutes: 60),
        DurationOption(label: "2 hours", minutes: 120),
        DurationOption(label: "8 hours", minutes: 480),
        DurationOption(label: "24 hours", minutes: 1440),
        DurationOption(label: "Until logout", minutes: -1),
        DurationOption(label: "Indefinitely", minutes: 0)
    ]

    public init(
        reasons: [String] = AppConfig.defaultReasons,
        durations: [DurationOption] = AppConfig.defaultDurations,
        privilegesCLIPath: String = "/Applications/Privileges.app/Contents/MacOS/PrivilegesCLI",
        reElevationIntervalSeconds: Int = 1500,
        suppressNotifications: Bool = true,
        dismissNotifications: Bool = false,
        logFile: String = "~/Library/Logs/privileges-extender.log"
    ) {
        self.reasons = reasons
        self.durations = durations
        self.privilegesCLIPath = privilegesCLIPath
        self.reElevationIntervalSeconds = reElevationIntervalSeconds
        self.suppressNotifications = suppressNotifications
        self.dismissNotifications = dismissNotifications
        self.logFile = logFile
    }

    enum CodingKeys: String, CodingKey {
        case reasons
        case durations
        case privilegesCLIPath = "privileges_cli_path"
        case reElevationIntervalSeconds = "re_elevation_interval_seconds"
        case suppressNotifications = "suppress_notifications"
        case dismissNotifications = "dismiss_notifications"
        case logFile = "log_file"
    }

    /// Custom decoder that allows partial YAML configs by falling back to defaults for missing keys.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfig()
        reasons = try container.decodeIfPresent([String].self, forKey: .reasons) ?? defaults.reasons
        durations = try container.decodeIfPresent([DurationOption].self, forKey: .durations) ?? defaults.durations
        privilegesCLIPath = try container.decodeIfPresent(String.self, forKey: .privilegesCLIPath)
            ?? defaults.privilegesCLIPath
        reElevationIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .reElevationIntervalSeconds)
            ?? defaults.reElevationIntervalSeconds
        suppressNotifications = try container.decodeIfPresent(Bool.self, forKey: .suppressNotifications)
            ?? defaults.suppressNotifications
        dismissNotifications = try container.decodeIfPresent(Bool.self, forKey: .dismissNotifications)
            ?? defaults.dismissNotifications
        logFile = try container.decodeIfPresent(String.self, forKey: .logFile) ?? defaults.logFile
    }
}

/// A duration option for privilege elevation.
public struct DurationOption: Codable, Equatable, Sendable {
    public var label: String
    public var minutes: Int

    public init(label: String, minutes: Int) {
        self.label = label
        self.minutes = minutes
    }

    /// Whether this duration means "until logout" (re-elevate until app quits).
    public var isUntilLogout: Bool {
        minutes == -1
    }

    /// Whether this duration means "indefinitely" (re-elevate forever).
    public var isIndefinite: Bool {
        minutes == 0
    }
}
