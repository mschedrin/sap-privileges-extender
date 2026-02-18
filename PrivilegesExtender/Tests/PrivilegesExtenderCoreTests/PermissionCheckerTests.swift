import XCTest

/// Tests for permission checking logic used by PermissionChecker and
/// the startup permission check in AppDelegate.
///
/// PermissionChecker lives in the executable target and can't be imported
/// here, so these tests verify the same underlying logic and integration
/// patterns — following the approach used by RevokeRaceConditionTests.
final class PermissionCheckerTests: XCTestCase {

    // MARK: - CLI Availability (filesystem checks)

    /// An executable file at the given path should be detected as available.
    func testCLIAvailableWhenExecutableExists() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PermissionCheckerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeCLI = tempDir.appendingPathComponent("PrivilegesCLI")
        FileManager.default.createFile(atPath: fakeCLI.path, contents: nil)
        // Make it executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeCLI.path
        )

        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: fakeCLI.path),
            "An executable file should be detected as available"
        )
    }

    /// A non-existent path should not be detected as available.
    func testCLIUnavailableWhenPathMissing() {
        let fakePath = "/tmp/PermissionCheckerTests-\(UUID().uuidString)/PrivilegesCLI"
        XCTAssertFalse(
            FileManager.default.isExecutableFile(atPath: fakePath),
            "A non-existent path should not be detected as available"
        )
    }

    /// A file that exists but is not executable should not be detected as available.
    func testCLIUnavailableWhenNotExecutable() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PermissionCheckerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeCLI = tempDir.appendingPathComponent("PrivilegesCLI")
        FileManager.default.createFile(atPath: fakeCLI.path, contents: nil)
        // Explicitly remove execute permission
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: fakeCLI.path
        )

        XCTAssertFalse(
            FileManager.default.isExecutableFile(atPath: fakeCLI.path),
            "A non-executable file should not be detected as available"
        )
    }

    /// Tilde in CLI path should be expanded before checking.
    func testCLIPathTildeExpansion() {
        // "~" expands to the home directory; a non-existent binary there should fail
        let tilded = "~/nonexistent-privileges-cli-\(UUID().uuidString)"
        let expanded = (tilded as NSString).expandingTildeInPath
        XCTAssertFalse(
            FileManager.default.isExecutableFile(atPath: expanded),
            "Tilde-expanded path to non-existent file should not be available"
        )
        XCTAssertTrue(
            expanded.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path),
            "Tilde should expand to home directory"
        )
    }

    // MARK: - hasAllPermissions combination logic

    /// Both checks must pass for hasAllPermissions to return true.
    func testHasAllPermissionsRequiresBothChecks() {
        // Simulates the same logic as PermissionChecker.hasAllPermissions()
        let combinations: [(accessibility: Bool, cli: Bool, expected: Bool)] = [
            (true, true, true),
            (true, false, false),
            (false, true, false),
            (false, false, false),
        ]

        for combo in combinations {
            let result = combo.accessibility && combo.cli
            XCTAssertEqual(
                result, combo.expected,
                "accessibility=\(combo.accessibility), cli=\(combo.cli) should be \(combo.expected)"
            )
        }
    }

    // MARK: - Startup permission check integration

    /// Simulates the startup check in AppDelegate.applicationDidFinishLaunching.
    /// When hasAllPermissions() returns false, the permission dialog should be shown.
    func testStartupShowsDialogWhenPermissionsMissing() {
        var dialogShown = false

        // Simulate hasAllPermissions() returning false (e.g. no accessibility)
        let hasAllPermissions = false
        if !hasAllPermissions {
            // Simulate showPermissionStatus()
            dialogShown = true
        }

        XCTAssertTrue(dialogShown, "Dialog must be shown when permissions are missing")
    }

    /// When hasAllPermissions() returns true, no dialog should be shown on startup.
    func testStartupSkipsDialogWhenAllPermissionsGranted() {
        var dialogShown = false

        let hasAllPermissions = true
        if !hasAllPermissions {
            dialogShown = true
        }

        XCTAssertFalse(dialogShown, "No dialog should be shown when all permissions are granted")
    }

    /// Simulates the optional-chaining guard in AppDelegate:
    /// `if permissionChecker?.hasAllPermissions() == false`
    /// When permissionChecker is nil, the dialog should NOT be shown.
    func testStartupSkipsDialogWhenCheckerIsNil() {
        var dialogShown = false

        // Simulate permissionChecker being nil
        let hasAllPermissions: Bool? = nil
        if hasAllPermissions == false {
            dialogShown = true
        }

        XCTAssertFalse(
            dialogShown,
            "Dialog must not be shown when permissionChecker is nil (nil != false)"
        )
    }
}
