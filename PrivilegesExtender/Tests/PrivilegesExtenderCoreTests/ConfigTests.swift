import XCTest
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
}
