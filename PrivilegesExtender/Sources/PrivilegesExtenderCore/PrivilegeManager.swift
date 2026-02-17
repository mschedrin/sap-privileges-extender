import Foundation

/// The current privilege status of the user.
public enum PrivilegeStatus: String, Equatable, Sendable {
    case elevated
    case standard
    case unknown
}

/// Errors that can occur during privilege operations.
public enum PrivilegeError: Error, Equatable {
    case cliNotFound(path: String)
    case executionFailed(exitCode: Int32, output: String)
    case unexpectedOutput(String)
    case launchFailed(description: String)
}

/// Protocol abstracting CLI execution for testability.
public protocol CLIExecutor: Sendable {
    func run(executablePath: String, arguments: [String]) throws -> CLIResult
}

/// Result of a CLI execution.
public struct CLIResult: Equatable, Sendable {
    public let exitCode: Int32
    public let output: String
    public let errorOutput: String

    public init(exitCode: Int32, output: String, errorOutput: String = "") {
        self.exitCode = exitCode
        self.output = output
        self.errorOutput = errorOutput
    }
}

/// Default CLI executor using Foundation.Process.
public struct ProcessCLIExecutor: CLIExecutor {
    public init() {}

    public func run(executablePath: String, arguments: [String]) throws -> CLIResult {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw PrivilegeError.cliNotFound(path: executablePath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Read pipes BEFORE waitUntilExit to avoid deadlock when pipe buffer fills
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        let output = String(data: stdoutData, encoding: .utf8) ?? ""
        let errorOutput = String(data: stderrData, encoding: .utf8) ?? ""

        return CLIResult(
            exitCode: process.terminationStatus,
            output: output,
            errorOutput: errorOutput
        )
    }
}

/// Manages privilege elevation via SAP PrivilegesCLI.
public final class PrivilegeManager: Sendable {
    private let cliPath: String
    private let executor: CLIExecutor
    private let logger: Logger?

    public init(cliPath: String, executor: CLIExecutor = ProcessCLIExecutor(), logger: Logger? = nil) {
        self.cliPath = cliPath
        self.executor = executor
        self.logger = logger
    }

    /// Checks the current privilege status by running PrivilegesCLI --status.
    public func checkStatus() -> PrivilegeStatus {
        do {
            let result = try executor.run(executablePath: cliPath, arguments: ["--status"])
            let status = PrivilegeManager.parseStatus(from: result.output)
            logger?.log("Status check: \(status.rawValue)")
            return status
        } catch {
            logger?.log("Status check failed: \(error)")
            return .unknown
        }
    }

    /// Elevates privileges with the given reason.
    public func elevate(reason: String) -> Result<Void, PrivilegeError> {
        logger?.log("Elevating privileges with reason: \(reason)")
        do {
            let result = try executor.run(
                executablePath: cliPath,
                arguments: ["--add", "--reason", reason]
            )
            if result.exitCode != 0 {
                let error = PrivilegeError.executionFailed(
                    exitCode: result.exitCode,
                    output: result.output + result.errorOutput
                )
                logger?.log("Elevation failed: exit code \(result.exitCode)")
                return .failure(error)
            }
            logger?.log("Elevation successful")
            return .success(())
        } catch let privilegeError as PrivilegeError {
            logger?.log("Elevation failed: \(privilegeError)")
            return .failure(privilegeError)
        } catch {
            logger?.log("Elevation failed: \(error)")
            return .failure(.launchFailed(description: error.localizedDescription))
        }
    }

    /// Revokes elevated privileges.
    public func revoke() -> Result<Void, PrivilegeError> {
        logger?.log("Revoking privileges")
        do {
            let result = try executor.run(executablePath: cliPath, arguments: ["--remove"])
            if result.exitCode != 0 {
                let error = PrivilegeError.executionFailed(
                    exitCode: result.exitCode,
                    output: result.output + result.errorOutput
                )
                logger?.log("Revoke failed: exit code \(result.exitCode)")
                return .failure(error)
            }
            logger?.log("Revoke successful")
            return .success(())
        } catch let privilegeError as PrivilegeError {
            logger?.log("Revoke failed: \(privilegeError)")
            return .failure(privilegeError)
        } catch {
            logger?.log("Revoke failed: \(error)")
            return .failure(.launchFailed(description: error.localizedDescription))
        }
    }

    // MARK: - Status Parsing

    /// Parses the output of PrivilegesCLI --status to determine privilege state.
    /// The CLI outputs text like "User has admin privileges" or "User has standard privileges".
    public static func parseStatus(from output: String) -> PrivilegeStatus {
        let lowered = output.lowercased()
        // Check for negation patterns before positive "admin" match
        if lowered.contains("user is not") || lowered.contains("standard") {
            return .standard
        } else if lowered.contains("admin") {
            return .elevated
        }
        return .unknown
    }
}
