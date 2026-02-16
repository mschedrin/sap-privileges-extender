import XCTest
import Yams
@testable import PrivilegesExtenderCore

final class ConfigTests: XCTestCase {

    func testAppConfigDefaultInit() {
        let config = AppConfig()
        XCTAssertEqual(config.reasons, [])
        XCTAssertEqual(config.durations, [])
        XCTAssertEqual(config.privilegesCLIPath, "/Applications/Privileges.app/Contents/MacOS/PrivilegesCLI")
        XCTAssertEqual(config.reElevationIntervalSeconds, 1500)
        XCTAssertTrue(config.dismissNotifications)
        XCTAssertEqual(config.logFile, "~/Library/Logs/privileges-extender.log")
    }

    func testDurationOptionSpecialValues() {
        let untilLogout = DurationOption(label: "Until logout", minutes: -1)
        XCTAssertTrue(untilLogout.isUntilLogout)
        XCTAssertFalse(untilLogout.isIndefinite)

        let indefinite = DurationOption(label: "Indefinitely", minutes: 0)
        XCTAssertFalse(indefinite.isUntilLogout)
        XCTAssertTrue(indefinite.isIndefinite)

        let thirtyMin = DurationOption(label: "30 minutes", minutes: 30)
        XCTAssertFalse(thirtyMin.isUntilLogout)
        XCTAssertFalse(thirtyMin.isIndefinite)
    }

    func testAppConfigEquality() {
        let config1 = AppConfig(reasons: ["Test"], durations: [DurationOption(label: "30 min", minutes: 30)])
        let config2 = AppConfig(reasons: ["Test"], durations: [DurationOption(label: "30 min", minutes: 30)])
        XCTAssertEqual(config1, config2)
    }

    func testAppConfigYAMLRoundTrip() throws {
        let config = AppConfig(
            reasons: ["Update software", "Troubleshooting"],
            durations: [
                DurationOption(label: "30 minutes", minutes: 30),
                DurationOption(label: "Until logout", minutes: -1),
                DurationOption(label: "Indefinitely", minutes: 0),
            ],
            privilegesCLIPath: "/usr/local/bin/PrivilegesCLI",
            reElevationIntervalSeconds: 900,
            dismissNotifications: false,
            logFile: "/tmp/test.log"
        )

        let encoder = YAMLEncoder()
        let yamlString = try encoder.encode(config)

        let decoder = YAMLDecoder()
        let decoded = try decoder.decode(AppConfig.self, from: yamlString)

        XCTAssertEqual(config, decoded)
    }

    func testAppConfigDecodesFromSnakeCaseYAML() throws {
        let yaml = """
        reasons:
          - Update software
          - Run script
        durations:
          - label: "1 hour"
            minutes: 60
        privileges_cli_path: "/usr/bin/cli"
        re_elevation_interval_seconds: 600
        dismiss_notifications: false
        log_file: "/tmp/log.txt"
        """

        let decoder = YAMLDecoder()
        let config = try decoder.decode(AppConfig.self, from: yaml)

        XCTAssertEqual(config.reasons, ["Update software", "Run script"])
        XCTAssertEqual(config.durations.count, 1)
        XCTAssertEqual(config.durations[0].label, "1 hour")
        XCTAssertEqual(config.durations[0].minutes, 60)
        XCTAssertEqual(config.privilegesCLIPath, "/usr/bin/cli")
        XCTAssertEqual(config.reElevationIntervalSeconds, 600)
        XCTAssertFalse(config.dismissNotifications)
        XCTAssertEqual(config.logFile, "/tmp/log.txt")
    }

    func testDurationOptionYAMLRoundTrip() throws {
        let duration = DurationOption(label: "2 hours", minutes: 120)

        let encoder = YAMLEncoder()
        let yamlString = try encoder.encode(duration)

        let decoder = YAMLDecoder()
        let decoded = try decoder.decode(DurationOption.self, from: yamlString)

        XCTAssertEqual(duration, decoded)
    }

    func testAppConfigWithAllDurationTypes() throws {
        let config = AppConfig(
            reasons: ["Test"],
            durations: [
                DurationOption(label: "30 minutes", minutes: 30),
                DurationOption(label: "1 hour", minutes: 60),
                DurationOption(label: "2 hours", minutes: 120),
                DurationOption(label: "8 hours", minutes: 480),
                DurationOption(label: "24 hours", minutes: 1440),
                DurationOption(label: "Until logout", minutes: -1),
                DurationOption(label: "Indefinitely", minutes: 0),
            ]
        )

        // Verify special durations
        XCTAssertTrue(config.durations[5].isUntilLogout)
        XCTAssertTrue(config.durations[6].isIndefinite)

        // Regular durations are neither special
        for i in 0..<5 {
            XCTAssertFalse(config.durations[i].isUntilLogout)
            XCTAssertFalse(config.durations[i].isIndefinite)
        }

        // Round-trip
        let encoder = YAMLEncoder()
        let yamlString = try encoder.encode(config)
        let decoder = YAMLDecoder()
        let decoded = try decoder.decode(AppConfig.self, from: yamlString)
        XCTAssertEqual(config, decoded)
    }
}
