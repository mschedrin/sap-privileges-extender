import Foundation
import Yams

/// Manages loading and saving the application configuration from a YAML file.
public final class ConfigManager: Sendable {
    /// The default config directory path: ~/Library/Application Support/PrivilegesExtender/
    public static let defaultConfigDirectoryPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/PrivilegesExtender"
    }()

    /// The default config file path.
    public static let defaultConfigFilePath: String = {
        "\(defaultConfigDirectoryPath)/config.yaml"
    }()

    /// The default configuration used when no config file exists.
    public static let defaultConfig = AppConfig(
        reasons: [
            "Update software",
            "Installing software",
            "Uninstalling software",
            "Run script",
            "Use software which requires elevation",
            "Troubleshooting",
        ],
        durations: [
            DurationOption(label: "30 minutes", minutes: 30),
            DurationOption(label: "1 hour", minutes: 60),
            DurationOption(label: "2 hours", minutes: 120),
            DurationOption(label: "8 hours", minutes: 480),
            DurationOption(label: "24 hours", minutes: 1440),
            DurationOption(label: "Until logout", minutes: -1),
            DurationOption(label: "Indefinitely", minutes: 0),
        ],
        privilegesCLIPath: "/Applications/Privileges.app/Contents/MacOS/PrivilegesCLI",
        reElevationIntervalSeconds: 1500,
        dismissNotifications: true,
        logFile: "~/Library/Logs/privileges-extender.log"
    )

    private let configFilePath: String
    private let fileManager: FileManager

    public init(configFilePath: String? = nil, fileManager: FileManager = .default) {
        self.configFilePath = configFilePath ?? Self.defaultConfigFilePath
        self.fileManager = fileManager
    }

    /// Loads the configuration from disk.
    /// If the config file doesn't exist, creates the directory and writes the default config.
    public func load() throws -> AppConfig {
        if !fileManager.fileExists(atPath: configFilePath) {
            try createDefaultConfig()
            return Self.defaultConfig
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: configFilePath))
        guard let yamlString = String(data: data, encoding: .utf8) else {
            throw ConfigError.invalidEncoding
        }

        let decoder = YAMLDecoder()
        return try decoder.decode(AppConfig.self, from: yamlString)
    }

    /// Reloads the configuration from disk. Alias for `load()`.
    public func reload() throws -> AppConfig {
        try load()
    }

    /// Encodes the given config to YAML and writes it to the config file path.
    public func save(_ config: AppConfig) throws {
        let encoder = YAMLEncoder()
        let yamlString = try encoder.encode(config)

        let directory = (configFilePath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: directory) {
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        try yamlString.write(toFile: configFilePath, atomically: true, encoding: .utf8)
    }

    /// Loads and returns the current config, falling back to the default on error.
    public var config: AppConfig {
        (try? load()) ?? Self.defaultConfig
    }

    /// The path to the config file being managed.
    public var path: String {
        configFilePath
    }

    // MARK: - Private

    private func createDefaultConfig() throws {
        try save(Self.defaultConfig)
    }
}

/// Errors specific to configuration loading.
public enum ConfigError: Error, Equatable {
    case invalidEncoding
}
