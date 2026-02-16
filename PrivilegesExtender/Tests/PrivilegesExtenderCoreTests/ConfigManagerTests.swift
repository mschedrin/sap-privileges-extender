import XCTest
import Yams
@testable import PrivilegesExtenderCore

final class ConfigManagerTests: XCTestCase {
    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "ConfigManagerTests-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
        super.tearDown()
    }

    func testLoadCreatesDefaultConfigWhenFileMissing() throws {
        let configPath = "\(tempDir!)/subdir/config.yaml"
        let manager = ConfigManager(configFilePath: configPath)

        let config = try manager.load()

        // Should return default config
        XCTAssertEqual(config, ConfigManager.defaultConfig)

        // Should have created the file on disk
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath))

        // The written file should be valid YAML that decodes back to the same config
        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let yamlString = String(data: data, encoding: .utf8)!
        let decoded = try YAMLDecoder().decode(AppConfig.self, from: yamlString)
        XCTAssertEqual(decoded, ConfigManager.defaultConfig)
    }

    func testLoadReadsExistingConfig() throws {
        let configPath = "\(tempDir!)/config.yaml"
        let customConfig = AppConfig(
            reasons: ["Custom reason"],
            durations: [DurationOption(label: "5 minutes", minutes: 5)],
            privilegesCLIPath: "/custom/path",
            reElevationIntervalSeconds: 300,
            dismissNotifications: false,
            logFile: "/custom/log.txt"
        )

        // Write custom config to disk
        let yamlString = try YAMLEncoder().encode(customConfig)
        try yamlString.write(toFile: configPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configFilePath: configPath)
        let loaded = try manager.load()

        XCTAssertEqual(loaded, customConfig)
    }

    func testReloadReturnsUpdatedConfig() throws {
        let configPath = "\(tempDir!)/config.yaml"
        let manager = ConfigManager(configFilePath: configPath)

        // First load creates default
        let initial = try manager.load()
        XCTAssertEqual(initial, ConfigManager.defaultConfig)

        // Modify the file
        let modified = AppConfig(
            reasons: ["Modified"],
            durations: [DurationOption(label: "10 min", minutes: 10)]
        )
        let yamlString = try YAMLEncoder().encode(modified)
        try yamlString.write(toFile: configPath, atomically: true, encoding: .utf8)

        // Reload should pick up changes
        let reloaded = try manager.reload()
        XCTAssertEqual(reloaded.reasons, ["Modified"])
        XCTAssertEqual(reloaded.durations.count, 1)
        XCTAssertEqual(reloaded.durations[0].label, "10 min")
    }

    func testSaveWritesConfigToDisk() throws {
        let configPath = "\(tempDir!)/config.yaml"
        let manager = ConfigManager(configFilePath: configPath)

        let config = AppConfig(
            reasons: ["Save test"],
            durations: [DurationOption(label: "1 hour", minutes: 60)],
            privilegesCLIPath: "/test/path",
            reElevationIntervalSeconds: 500,
            dismissNotifications: true,
            logFile: "/test/log"
        )

        try manager.save(config)

        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath))

        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let yamlString = String(data: data, encoding: .utf8)!
        let decoded = try YAMLDecoder().decode(AppConfig.self, from: yamlString)
        XCTAssertEqual(decoded, config)
    }

    func testSaveCreatesDirectoryIfMissing() throws {
        let configPath = "\(tempDir!)/deeply/nested/dir/config.yaml"
        let manager = ConfigManager(configFilePath: configPath)

        let config = AppConfig(reasons: ["Nested"])
        try manager.save(config)

        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath))
    }

    func testLoadMalformedYAMLThrows() throws {
        let configPath = "\(tempDir!)/config.yaml"

        // Write invalid YAML content (valid YAML but not decodable as AppConfig)
        let malformed = "this is not: [a valid config structure"
        try malformed.write(toFile: configPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configFilePath: configPath)

        XCTAssertThrowsError(try manager.load())
    }

    func testDefaultConfigHasExpectedValues() {
        let config = ConfigManager.defaultConfig

        XCTAssertEqual(config.reasons.count, 6)
        XCTAssertEqual(config.reasons[0], "Update software")
        XCTAssertEqual(config.reasons[5], "Troubleshooting")

        XCTAssertEqual(config.durations.count, 7)
        XCTAssertEqual(config.durations[0].label, "30 minutes")
        XCTAssertEqual(config.durations[0].minutes, 30)
        XCTAssertEqual(config.durations[5].label, "Until logout")
        XCTAssertEqual(config.durations[5].minutes, -1)
        XCTAssertEqual(config.durations[6].label, "Indefinitely")
        XCTAssertEqual(config.durations[6].minutes, 0)

        XCTAssertEqual(config.privilegesCLIPath, "/Applications/Privileges.app/Contents/MacOS/PrivilegesCLI")
        XCTAssertEqual(config.reElevationIntervalSeconds, 1500)
        XCTAssertTrue(config.dismissNotifications)
        XCTAssertEqual(config.logFile, "~/Library/Logs/privileges-extender.log")
    }

    func testPathReturnsConfigFilePath() {
        let customPath = "/some/custom/path.yaml"
        let manager = ConfigManager(configFilePath: customPath)
        XCTAssertEqual(manager.path, customPath)
    }

    func testConfigPropertyReturnsLoadedConfig() throws {
        let configPath = "\(tempDir!)/config.yaml"
        let customConfig = AppConfig(
            reasons: ["Property test"],
            durations: [DurationOption(label: "15 minutes", minutes: 15)]
        )
        let yamlString = try YAMLEncoder().encode(customConfig)
        try yamlString.write(toFile: configPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configFilePath: configPath)
        let config = manager.config

        XCTAssertEqual(config.reasons, ["Property test"])
        XCTAssertEqual(config.durations.count, 1)
    }

    func testConfigPropertyReturnsDefaultWhenFileIsMissing() {
        let configPath = "\(tempDir!)/nonexistent/config.yaml"
        let manager = ConfigManager(configFilePath: configPath)

        // The config property should return default config (file creation may fail
        // if parent directory doesn't exist in the convenience getter, but it falls back)
        let config = manager.config
        XCTAssertEqual(config.reasons.count, 6)
    }

    func testConfigPropertyReturnsDefaultWhenFileIsMalformed() throws {
        let configPath = "\(tempDir!)/config.yaml"
        try "not: [valid yaml config".write(toFile: configPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configFilePath: configPath)
        let config = manager.config

        // Should fall back to default on parse error
        XCTAssertEqual(config, ConfigManager.defaultConfig)
    }
}
