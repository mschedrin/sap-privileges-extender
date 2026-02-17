import XCTest
@testable import PrivilegesExtenderCore

/// Mock CLI executor for testing PrivilegeManager without actual PrivilegesCLI.
final class MockCLIExecutor: CLIExecutor, @unchecked Sendable {
    var resultToReturn: CLIResult?
    var errorToThrow: Error?
    var lastExecutablePath: String?
    var lastArguments: [String]?
    var callCount: Int = 0

    func run(executablePath: String, arguments: [String]) throws -> CLIResult {
        callCount += 1
        lastExecutablePath = executablePath
        lastArguments = arguments

        if let error = errorToThrow {
            throw error
        }

        return resultToReturn ?? CLIResult(exitCode: 0, output: "", errorOutput: "")
    }
}

final class PrivilegeManagerTests: XCTestCase {

    // MARK: - Status Parsing

    func testParseStatusElevatedFromAdminOutput() {
        let output = "User has admin privileges."
        XCTAssertEqual(PrivilegeManager.parseStatus(from: output), .elevated)
    }

    func testParseStatusElevatedCaseInsensitive() {
        let output = "User has ADMIN privileges"
        XCTAssertEqual(PrivilegeManager.parseStatus(from: output), .elevated)
    }

    func testParseStatusStandardFromStandardOutput() {
        let output = "User has standard user privileges."
        XCTAssertEqual(PrivilegeManager.parseStatus(from: output), .standard)
    }

    func testParseStatusStandardFromNotAdmin() {
        let output = "User is not an admin."
        XCTAssertEqual(PrivilegeManager.parseStatus(from: output), .standard)
    }

    func testParseStatusUnknownFromEmptyOutput() {
        XCTAssertEqual(PrivilegeManager.parseStatus(from: ""), .unknown)
    }

    func testParseStatusUnknownFromGarbageOutput() {
        XCTAssertEqual(PrivilegeManager.parseStatus(from: "something unexpected"), .unknown)
    }

    // MARK: - checkStatus

    func testCheckStatusReturnsElevated() {
        let executor = MockCLIExecutor()
        executor.resultToReturn = CLIResult(exitCode: 0, output: "User has admin privileges.\n")
        let manager = PrivilegeManager(cliPath: "/usr/bin/cli", executor: executor)

        let status = manager.checkStatus()

        XCTAssertEqual(status, .elevated)
        XCTAssertEqual(executor.lastArguments, ["--status"])
    }

    func testCheckStatusReturnsStandard() {
        let executor = MockCLIExecutor()
        executor.resultToReturn = CLIResult(exitCode: 0, output: "User has standard user privileges.\n")
        let manager = PrivilegeManager(cliPath: "/usr/bin/cli", executor: executor)

        let status = manager.checkStatus()

        XCTAssertEqual(status, .standard)
    }

    func testCheckStatusReturnsUnknownOnExecutionError() {
        let executor = MockCLIExecutor()
        executor.errorToThrow = NSError(domain: "test", code: 1)
        let manager = PrivilegeManager(cliPath: "/nonexistent/path", executor: executor)

        let status = manager.checkStatus()

        XCTAssertEqual(status, .unknown)
    }

    // MARK: - elevate

    func testElevateSuccess() {
        let executor = MockCLIExecutor()
        executor.resultToReturn = CLIResult(exitCode: 0, output: "")
        let manager = PrivilegeManager(cliPath: "/usr/bin/cli", executor: executor)

        let result = manager.elevate(reason: "Update software")

        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
        XCTAssertEqual(executor.lastArguments, ["--add", "--reason", "Update software"])
    }

    func testElevateFailsWithNonZeroExitCode() {
        let executor = MockCLIExecutor()
        executor.resultToReturn = CLIResult(exitCode: 1, output: "Permission denied")
        let manager = PrivilegeManager(cliPath: "/usr/bin/cli", executor: executor)

        let result = manager.elevate(reason: "Test")

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error, .executionFailed(exitCode: 1, output: "Permission denied"))
        }
    }

    func testElevateFailsWhenCLILaunchFails() {
        let executor = MockCLIExecutor()
        executor.errorToThrow = NSError(domain: "NSPOSIXErrorDomain", code: 2, userInfo: nil)
        let manager = PrivilegeManager(cliPath: "/nonexistent/cli", executor: executor)

        let result = manager.elevate(reason: "Test")

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            if case .launchFailed = error {
                // Expected
            } else {
                XCTFail("Expected .launchFailed, got \(error)")
            }
        }
    }

    // MARK: - revoke

    func testRevokeSuccess() {
        let executor = MockCLIExecutor()
        executor.resultToReturn = CLIResult(exitCode: 0, output: "")
        let manager = PrivilegeManager(cliPath: "/usr/bin/cli", executor: executor)

        let result = manager.revoke()

        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
        XCTAssertEqual(executor.lastArguments, ["--remove"])
    }

    func testRevokeFailsWithNonZeroExitCode() {
        let executor = MockCLIExecutor()
        executor.resultToReturn = CLIResult(exitCode: 2, output: "Error occurred")
        let manager = PrivilegeManager(cliPath: "/usr/bin/cli", executor: executor)

        let result = manager.revoke()

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error, .executionFailed(exitCode: 2, output: "Error occurred"))
        }
    }

    func testRevokeFailsWhenCLILaunchFails() {
        let executor = MockCLIExecutor()
        executor.errorToThrow = NSError(domain: "NSPOSIXErrorDomain", code: 2, userInfo: nil)
        let manager = PrivilegeManager(cliPath: "/nonexistent/cli", executor: executor)

        let result = manager.revoke()

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            if case .launchFailed = error {
                // Expected
            } else {
                XCTFail("Expected .launchFailed, got \(error)")
            }
        }
    }

    // MARK: - Logging integration

    func testCheckStatusLogsResult() throws {
        let tmpDir = NSTemporaryDirectory()
        let logPath = tmpDir + "test-privilege-\(UUID().uuidString).log"
        let logger = Logger(filePath: logPath)

        let executor = MockCLIExecutor()
        executor.resultToReturn = CLIResult(exitCode: 0, output: "User has admin privileges.\n")
        let manager = PrivilegeManager(cliPath: "/usr/bin/cli", executor: executor, logger: logger)

        _ = manager.checkStatus()

        let logContent = logger.readAll()
        XCTAssertNotNil(logContent)
        XCTAssertTrue(logContent!.contains("Status changed: elevated"))

        try? FileManager.default.removeItem(atPath: logPath)
    }

    func testElevateLogsReason() throws {
        let tmpDir = NSTemporaryDirectory()
        let logPath = tmpDir + "test-privilege-\(UUID().uuidString).log"
        let logger = Logger(filePath: logPath)

        let executor = MockCLIExecutor()
        executor.resultToReturn = CLIResult(exitCode: 0, output: "")
        let manager = PrivilegeManager(cliPath: "/usr/bin/cli", executor: executor, logger: logger)

        _ = manager.elevate(reason: "Installing software")

        let logContent = logger.readAll()
        XCTAssertNotNil(logContent)
        XCTAssertTrue(logContent!.contains("Elevating privileges with reason: Installing software"))
        XCTAssertTrue(logContent!.contains("Elevation successful"))

        try? FileManager.default.removeItem(atPath: logPath)
    }

    // MARK: - CLI path usage

    func testManagerUsesConfiguredCLIPath() {
        let executor = MockCLIExecutor()
        executor.resultToReturn = CLIResult(exitCode: 0, output: "")
        let customPath = "/custom/path/to/PrivilegesCLI"
        let manager = PrivilegeManager(cliPath: customPath, executor: executor)

        _ = manager.checkStatus()

        XCTAssertEqual(executor.lastExecutablePath, customPath)
    }

    // MARK: - PrivilegeStatus enum

    func testPrivilegeStatusRawValues() {
        XCTAssertEqual(PrivilegeStatus.elevated.rawValue, "elevated")
        XCTAssertEqual(PrivilegeStatus.standard.rawValue, "standard")
        XCTAssertEqual(PrivilegeStatus.unknown.rawValue, "unknown")
    }

    // MARK: - PrivilegeError equatable

    func testPrivilegeErrorEquality() {
        let err1 = PrivilegeError.cliNotFound(path: "/a")
        let err2 = PrivilegeError.cliNotFound(path: "/a")
        let err3 = PrivilegeError.cliNotFound(path: "/b")
        XCTAssertEqual(err1, err2)
        XCTAssertNotEqual(err1, err3)

        let err4 = PrivilegeError.executionFailed(exitCode: 1, output: "fail")
        let err5 = PrivilegeError.executionFailed(exitCode: 1, output: "fail")
        XCTAssertEqual(err4, err5)
    }
}

// MARK: - Logger Tests

final class LoggerTests: XCTestCase {

    func testLogWritesTimestampedEntry() throws {
        let tmpDir = NSTemporaryDirectory()
        let logPath = tmpDir + "test-logger-\(UUID().uuidString).log"
        let logger = Logger(filePath: logPath)

        logger.log("Test message")

        let content = logger.readAll()
        XCTAssertNotNil(content)
        // Should contain timestamp in format [YYYY-MM-DD HH:MM:SS] and the message
        XCTAssertTrue(content!.contains("Test message"))
        XCTAssertTrue(content!.contains("["))
        XCTAssertTrue(content!.contains("]"))

        try FileManager.default.removeItem(atPath: logPath)
    }

    func testLogAppendsMultipleEntries() throws {
        let tmpDir = NSTemporaryDirectory()
        let logPath = tmpDir + "test-logger-\(UUID().uuidString).log"
        let logger = Logger(filePath: logPath)

        logger.log("First")
        logger.log("Second")
        logger.log("Third")

        let content = logger.readAll()
        XCTAssertNotNil(content)
        XCTAssertTrue(content!.contains("First"))
        XCTAssertTrue(content!.contains("Second"))
        XCTAssertTrue(content!.contains("Third"))

        // Verify ordering - First should appear before Second
        let firstRange = content!.range(of: "First")!
        let secondRange = content!.range(of: "Second")!
        XCTAssertTrue(firstRange.lowerBound < secondRange.lowerBound)

        try FileManager.default.removeItem(atPath: logPath)
    }

    func testReadAllReturnsNilForMissingFile() {
        let logger = Logger(filePath: "/nonexistent/path/log.txt")
        XCTAssertNil(logger.readAll())
    }

    func testClearEmptiesLogFile() throws {
        let tmpDir = NSTemporaryDirectory()
        let logPath = tmpDir + "test-logger-\(UUID().uuidString).log"
        let logger = Logger(filePath: logPath)

        logger.log("Some content")
        XCTAssertNotNil(logger.readAll())

        logger.clear()

        let content = logger.readAll()
        XCTAssertNotNil(content)
        XCTAssertEqual(content, "")

        try FileManager.default.removeItem(atPath: logPath)
    }

    func testLogCreatesDirectoryIfMissing() throws {
        let tmpDir = NSTemporaryDirectory()
        let nestedPath = tmpDir + "test-logger-nested-\(UUID().uuidString)/subdir/log.txt"
        let logger = Logger(filePath: nestedPath)

        logger.log("Creating nested")

        let content = logger.readAll()
        XCTAssertNotNil(content)
        XCTAssertTrue(content!.contains("Creating nested"))

        // Clean up
        let parentDir = (nestedPath as NSString).deletingLastPathComponent
        let topDir = (parentDir as NSString).deletingLastPathComponent
        try FileManager.default.removeItem(atPath: topDir)
    }
}
