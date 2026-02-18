import XCTest
@testable import PrivilegesExtenderCore

/// Mock CLI executor that invokes a callback during `run()` to simulate
/// the re-elevation timer firing during `Process.waitUntilExit()`'s RunLoop spin.
private final class ReentrantMockExecutor: CLIExecutor, @unchecked Sendable {
    var results: [String: CLIResult] = [:]
    var onRun: ((_ arguments: [String]) -> Void)?
    var callLog: [[String]] = []

    func run(executablePath: String, arguments: [String]) throws -> CLIResult {
        callLog.append(arguments)
        // Callback fires DURING the CLI call, simulating a timer tick
        // that runs while waitUntilExit() spins the RunLoop.
        onRun?(arguments)
        let key = arguments.first ?? ""
        return results[key] ?? CLIResult(exitCode: 0, output: "")
    }
}

// MARK: - Revoke Race Condition Tests

/// Tests that verify the revoke-before-stop ordering prevents the re-elevation race.
///
/// **The bug:** `Process.waitUntilExit()` polls the RunLoop in default mode, and the
/// re-elevation timer (registered in `.common` mode) can fire mid-call. When it does,
/// `timerTick()` sees the session is still `.active` but actual status is `.standard`,
/// interprets it as an MDM timeout, and immediately re-elevates — undoing the revoke.
///
/// **The fix:** Stop the timer (and, if the timer simulates its tick, the session must
/// already be idle) BEFORE calling the revoke CLI.
///
/// These tests exercise the coordination contract between `ElevationSession` and
/// `PrivilegeManager` that `AppDelegate.handleRevoke()` relies on.
final class RevokeRaceConditionTests: XCTestCase {

    // MARK: - Fixed ordering: session stopped before CLI call

    /// With the fix, the session is stopped before the CLI call. A simulated
    /// timer tick during the CLI call sees an idle session and does not re-elevate.
    func testSessionStoppedBeforeCLICallPreventsReElevation() {
        let executor = ReentrantMockExecutor()
        executor.results["--remove"] = CLIResult(exitCode: 0, output: "")
        executor.results["--status"] = CLIResult(exitCode: 0, output: "User has standard user privileges.\n")
        executor.results["--add"] = CLIResult(exitCode: 0, output: "")

        let session = ElevationSession(reElevationIntervalSeconds: 60)
        let manager = PrivilegeManager(cliPath: "/cli", executor: executor)

        // Start an active session
        let duration = DurationOption(label: "30 min", minutes: 30)
        session.start(reason: "Testing", duration: duration)

        var reElevationAttempted = false

        // Simulate what timerTick() does when it fires during the revoke CLI call
        executor.onRun = { arguments in
            guard arguments == ["--remove"] else { return }
            // Timer fires here (inside waitUntilExit's RunLoop spin)
            let status = manager.checkStatus()
            if case .active = session.state, status == .standard {
                // Old code would re-elevate here
                _ = manager.elevate(reason: session.activeReason ?? "")
                reElevationAttempted = true
            }
        }

        // --- Fixed ordering: stop session, then call CLI ---
        session.stop()
        let result = manager.revoke()

        switch result {
        case .success: break
        case .failure(let error): XCTFail("Revoke should succeed, got \(error)")
        }
        XCTAssertFalse(reElevationAttempted,
                        "Timer must not re-elevate when session is stopped before CLI call")
        XCTAssertEqual(session.state, .idle)
        // Only --remove and --status (from the simulated timer) should appear;
        // --add should never be called.
        XCTAssertFalse(executor.callLog.contains(["--add", "--reason", "Testing"]),
                        "elevate() must not be called when session is idle")
    }

    // MARK: - Old ordering: demonstrates the race

    /// With the old ordering (CLI call before session.stop()), a simulated timer
    /// tick during the CLI call sees an active session and re-elevates.
    func testOldOrderingAllowsReElevationRace() {
        let executor = ReentrantMockExecutor()
        executor.results["--remove"] = CLIResult(exitCode: 0, output: "")
        executor.results["--status"] = CLIResult(exitCode: 0, output: "User has standard user privileges.\n")
        executor.results["--add"] = CLIResult(exitCode: 0, output: "")

        let session = ElevationSession(reElevationIntervalSeconds: 60)
        let manager = PrivilegeManager(cliPath: "/cli", executor: executor)

        let duration = DurationOption(label: "30 min", minutes: 30)
        session.start(reason: "Testing", duration: duration)

        var reElevationAttempted = false

        executor.onRun = { arguments in
            guard arguments == ["--remove"] else { return }
            let status = manager.checkStatus()
            if case .active = session.state, status == .standard {
                _ = manager.elevate(reason: session.activeReason ?? "")
                reElevationAttempted = true
            }
        }

        // --- Old buggy ordering: CLI call first, then session.stop() ---
        _ = manager.revoke()
        session.stop()

        XCTAssertTrue(reElevationAttempted,
                       "Without the fix, the timer sees an active session during revoke and re-elevates")
        XCTAssertTrue(executor.callLog.contains(["--add", "--reason", "Testing"]),
                       "elevate() was called due to the race")
    }

    // MARK: - Revoke failure should keep session active

    /// If the revoke CLI call fails, the session should remain active so the
    /// caller can restart the timer and retry later.
    func testSessionRemainsActiveWhenRevokeFails() {
        let executor = ReentrantMockExecutor()
        executor.results["--remove"] = CLIResult(exitCode: 1, output: "Permission denied")

        let session = ElevationSession(reElevationIntervalSeconds: 60)
        let manager = PrivilegeManager(cliPath: "/cli", executor: executor)

        let duration = DurationOption(label: "30 min", minutes: 30)
        session.start(reason: "Testing", duration: duration)

        // With the fix, the timer is stopped before CLI call but restarted on failure.
        // The session is NOT stopped before the CLI call — only the timer is.
        // So on failure, the session should still be active.
        let result = manager.revoke()

        switch result {
        case .success: XCTFail("Revoke should fail with exit code 1")
        case .failure: break
        }
        // Session was never stopped because revoke failed
        XCTAssertEqual(session.state,
                       .active(reason: "Testing", startTime: session.activeStartTime!, duration: duration),
                       "Session must remain active when revoke fails")
    }

    // MARK: - Full handleRevoke simulation

    /// Simulates the complete fixed `handleRevoke()` flow including timer
    /// stop/restart logic, verifying end state for a successful revoke.
    func testHandleRevokeSimulationSuccess() {
        let executor = ReentrantMockExecutor()
        executor.results["--remove"] = CLIResult(exitCode: 0, output: "")
        executor.results["--status"] = CLIResult(exitCode: 0, output: "User has standard user privileges.\n")
        executor.results["--add"] = CLIResult(exitCode: 0, output: "")

        let session = ElevationSession(reElevationIntervalSeconds: 60)
        let manager = PrivilegeManager(cliPath: "/cli", executor: executor)

        let duration = DurationOption(label: "Indefinitely", minutes: 0)
        session.start(reason: "Dev work", duration: duration)

        var timerRunning = true
        var reElevationCount = 0

        executor.onRun = { arguments in
            guard arguments == ["--remove"] else { return }
            // Simulate timer tick during CLI call
            if timerRunning {
                let status = manager.checkStatus()
                if case .active = session.state, status == .standard {
                    _ = manager.elevate(reason: session.activeReason ?? "")
                    reElevationCount += 1
                }
            }
        }

        // --- Simulate fixed handleRevoke() ---
        // 1. Stop timer
        timerRunning = false
        // 2. Call CLI
        let result = manager.revoke()
        // 3. On success: stop session
        switch result {
        case .success:
            session.stop()
        case .failure:
            // On failure: restart timer
            timerRunning = true
        }

        XCTAssertEqual(reElevationCount, 0, "No re-elevation should occur")
        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(timerRunning)
    }

    /// Simulates the complete fixed `handleRevoke()` flow when the CLI fails,
    /// verifying the timer is restarted.
    func testHandleRevokeSimulationFailureRestartsTimer() {
        let executor = ReentrantMockExecutor()
        executor.results["--remove"] = CLIResult(exitCode: 1, output: "Error")

        let session = ElevationSession(reElevationIntervalSeconds: 60)
        let manager = PrivilegeManager(cliPath: "/cli", executor: executor)

        let duration = DurationOption(label: "30 min", minutes: 30)
        session.start(reason: "Dev work", duration: duration)

        var timerRunning = true

        // --- Simulate fixed handleRevoke() ---
        timerRunning = false
        let result = manager.revoke()
        switch result {
        case .success:
            session.stop()
        case .failure:
            timerRunning = true
        }

        XCTAssertTrue(timerRunning, "Timer must be restarted when revoke fails")
        if case .active(let reason, _, _) = session.state {
            XCTAssertEqual(reason, "Dev work")
        } else {
            XCTFail("Session must remain active when revoke fails")
        }
    }
}
