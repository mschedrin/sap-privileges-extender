import XCTest
@testable import PrivilegesExtenderCore

final class ElevationSessionTests: XCTestCase {

    // MARK: - Helpers

    private func makeSession(reElevationInterval: TimeInterval = 1500) -> ElevationSession {
        ElevationSession(reElevationIntervalSeconds: reElevationInterval)
    }

    private let fixedNow = Date(timeIntervalSince1970: 1_000_000)

    private let thirtyMin = DurationOption(label: "30 minutes", minutes: 30)
    private let oneHour = DurationOption(label: "1 hour", minutes: 60)
    private let untilLogout = DurationOption(label: "Until logout", minutes: -1)
    private let indefinite = DurationOption(label: "Indefinitely", minutes: 0)

    // MARK: - Initial State

    func testInitialStateIsIdle() {
        let session = makeSession()
        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(session.lastElevationTime)
        XCTAssertNil(session.activeReason)
        XCTAssertNil(session.activeDuration)
        XCTAssertNil(session.activeStartTime)
    }

    // MARK: - Start

    func testStartTransitionsToActive() {
        let session = makeSession()
        session.start(reason: "Update software", duration: thirtyMin, now: fixedNow)

        XCTAssertEqual(session.state, .active(reason: "Update software", startTime: fixedNow, duration: thirtyMin))
        XCTAssertEqual(session.lastElevationTime, fixedNow)
        XCTAssertEqual(session.activeReason, "Update software")
        XCTAssertEqual(session.activeDuration, thirtyMin)
        XCTAssertEqual(session.activeStartTime, fixedNow)
    }

    func testStartOverwritesPreviousSession() {
        let session = makeSession()
        session.start(reason: "First reason", duration: thirtyMin, now: fixedNow)

        let later = fixedNow.addingTimeInterval(60)
        session.start(reason: "Second reason", duration: oneHour, now: later)

        XCTAssertEqual(session.activeReason, "Second reason")
        XCTAssertEqual(session.activeDuration, oneHour)
        XCTAssertEqual(session.activeStartTime, later)
        XCTAssertEqual(session.lastElevationTime, later)
    }

    // MARK: - Stop

    func testStopTransitionsToIdle() {
        let session = makeSession()
        session.start(reason: "Testing", duration: thirtyMin, now: fixedNow)
        session.stop()

        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(session.lastElevationTime)
        XCTAssertNil(session.activeReason)
    }

    func testStopFromIdleRemainsIdle() {
        let session = makeSession()
        session.stop()
        XCTAssertEqual(session.state, .idle)
    }

    // MARK: - Expiry (Regular Durations)

    func testIsExpiredFalseWhenIdle() {
        let session = makeSession()
        XCTAssertFalse(session.isExpired(now: fixedNow))
    }

    func testIsExpiredFalseBeforeDuration() {
        let session = makeSession()
        session.start(reason: "Test", duration: thirtyMin, now: fixedNow)

        // 29 minutes later - not expired yet
        let before = fixedNow.addingTimeInterval(29 * 60)
        XCTAssertFalse(session.isExpired(now: before))
    }

    func testIsExpiredTrueAtExactDuration() {
        let session = makeSession()
        session.start(reason: "Test", duration: thirtyMin, now: fixedNow)

        // Exactly 30 minutes later
        let atExpiry = fixedNow.addingTimeInterval(30 * 60)
        XCTAssertTrue(session.isExpired(now: atExpiry))
    }

    func testIsExpiredTrueAfterDuration() {
        let session = makeSession()
        session.start(reason: "Test", duration: thirtyMin, now: fixedNow)

        // 31 minutes later
        let after = fixedNow.addingTimeInterval(31 * 60)
        XCTAssertTrue(session.isExpired(now: after))
    }

    func testCheckExpiryTransitionsToExpired() {
        let session = makeSession()
        session.start(reason: "Test", duration: thirtyMin, now: fixedNow)

        let after = fixedNow.addingTimeInterval(31 * 60)
        let didExpire = session.checkExpiry(now: after)

        XCTAssertTrue(didExpire)
        XCTAssertEqual(session.state, .expired)
        XCTAssertNil(session.lastElevationTime)
    }

    func testCheckExpiryReturnsFalseWhenNotExpired() {
        let session = makeSession()
        session.start(reason: "Test", duration: thirtyMin, now: fixedNow)

        let before = fixedNow.addingTimeInterval(10 * 60)
        let didExpire = session.checkExpiry(now: before)

        XCTAssertFalse(didExpire)
        XCTAssertEqual(session.activeReason, "Test")
    }

    // MARK: - Expiry (Special Durations)

    func testUntilLogoutNeverExpires() {
        let session = makeSession()
        session.start(reason: "Test", duration: untilLogout, now: fixedNow)

        // Even after 24 hours, should not expire
        let farFuture = fixedNow.addingTimeInterval(24 * 60 * 60)
        XCTAssertFalse(session.isExpired(now: farFuture))
        XCTAssertFalse(session.checkExpiry(now: farFuture))
        XCTAssertEqual(session.activeReason, "Test")
    }

    func testIndefiniteNeverExpires() {
        let session = makeSession()
        session.start(reason: "Test", duration: indefinite, now: fixedNow)

        // Even after 7 days
        let farFuture = fixedNow.addingTimeInterval(7 * 24 * 60 * 60)
        XCTAssertFalse(session.isExpired(now: farFuture))
        XCTAssertFalse(session.checkExpiry(now: farFuture))
        XCTAssertEqual(session.activeReason, "Test")
    }

    // MARK: - Remaining Time

    func testRemainingTimeWhenIdle() {
        let session = makeSession()
        XCTAssertNil(session.remainingTime(now: fixedNow))
    }

    func testRemainingTimeAtStart() throws {
        let session = makeSession()
        session.start(reason: "Test", duration: thirtyMin, now: fixedNow)

        let remaining = try XCTUnwrap(session.remainingTime(now: fixedNow))
        XCTAssertEqual(remaining, 30 * 60, accuracy: 0.001)
    }

    func testRemainingTimePartway() throws {
        let session = makeSession()
        session.start(reason: "Test", duration: oneHour, now: fixedNow)

        let later = fixedNow.addingTimeInterval(20 * 60)
        let remaining = try XCTUnwrap(session.remainingTime(now: later))
        XCTAssertEqual(remaining, 40 * 60, accuracy: 0.001)
    }

    func testRemainingTimeAtExpiry() throws {
        let session = makeSession()
        session.start(reason: "Test", duration: thirtyMin, now: fixedNow)

        let atExpiry = fixedNow.addingTimeInterval(30 * 60)
        let remaining = try XCTUnwrap(session.remainingTime(now: atExpiry))
        XCTAssertEqual(remaining, 0, accuracy: 0.001)
    }

    func testRemainingTimeAfterExpiryClampedToZero() throws {
        let session = makeSession()
        session.start(reason: "Test", duration: thirtyMin, now: fixedNow)

        let after = fixedNow.addingTimeInterval(35 * 60)
        let remaining = try XCTUnwrap(session.remainingTime(now: after))
        XCTAssertEqual(remaining, 0, accuracy: 0.001)
    }

    func testRemainingTimeNilForUntilLogout() {
        let session = makeSession()
        session.start(reason: "Test", duration: untilLogout, now: fixedNow)
        XCTAssertNil(session.remainingTime(now: fixedNow))
    }

    func testRemainingTimeNilForIndefinite() {
        let session = makeSession()
        session.start(reason: "Test", duration: indefinite, now: fixedNow)
        XCTAssertNil(session.remainingTime(now: fixedNow))
    }

    // MARK: - Re-elevation Timing

    func testShouldReElevateFalseWhenIdle() {
        let session = makeSession()
        XCTAssertFalse(session.shouldReElevate(now: fixedNow))
    }

    func testShouldReElevateFalseRightAfterStart() {
        let session = makeSession(reElevationInterval: 1500)
        session.start(reason: "Test", duration: oneHour, now: fixedNow)

        // 1 second later - too soon
        let soon = fixedNow.addingTimeInterval(1)
        XCTAssertFalse(session.shouldReElevate(now: soon))
    }

    func testShouldReElevateTrueAfterInterval() {
        let session = makeSession(reElevationInterval: 1500) // 25 min
        session.start(reason: "Test", duration: oneHour, now: fixedNow)

        // Exactly 25 minutes later
        let after = fixedNow.addingTimeInterval(1500)
        XCTAssertTrue(session.shouldReElevate(now: after))
    }

    func testShouldReElevateFalseAfterExpiry() {
        let session = makeSession(reElevationInterval: 1500)
        session.start(reason: "Test", duration: thirtyMin, now: fixedNow)

        // 31 minutes later - session expired
        let after = fixedNow.addingTimeInterval(31 * 60)
        XCTAssertFalse(session.shouldReElevate(now: after))
    }

    func testShouldReElevateWithUntilLogout() {
        let session = makeSession(reElevationInterval: 1500)
        session.start(reason: "Test", duration: untilLogout, now: fixedNow)

        // 25 minutes later - should re-elevate (never expires)
        let after = fixedNow.addingTimeInterval(1500)
        XCTAssertTrue(session.shouldReElevate(now: after))
    }

    func testShouldReElevateWithIndefinite() {
        let session = makeSession(reElevationInterval: 1500)
        session.start(reason: "Test", duration: indefinite, now: fixedNow)

        // 25 minutes later
        let after = fixedNow.addingTimeInterval(1500)
        XCTAssertTrue(session.shouldReElevate(now: after))
    }

    func testRecordReElevationResetsTimer() {
        let session = makeSession(reElevationInterval: 1500)
        session.start(reason: "Test", duration: oneHour, now: fixedNow)

        // After 25 min, should re-elevate
        let first = fixedNow.addingTimeInterval(1500)
        XCTAssertTrue(session.shouldReElevate(now: first))

        // Record re-elevation
        session.recordReElevation(at: first)

        // 1 minute later - too soon since last re-elevation
        let afterRecord = first.addingTimeInterval(60)
        XCTAssertFalse(session.shouldReElevate(now: afterRecord))

        // 25 min after the re-elevation - should re-elevate again
        let secondInterval = first.addingTimeInterval(1500)
        XCTAssertTrue(session.shouldReElevate(now: secondInterval))
    }

    // MARK: - ElevationState Equatable

    func testElevationStateEquality() {
        let state1 = ElevationState.active(reason: "Test", startTime: fixedNow, duration: thirtyMin)
        let state2 = ElevationState.active(reason: "Test", startTime: fixedNow, duration: thirtyMin)
        XCTAssertEqual(state1, state2)

        let state3 = ElevationState.active(reason: "Other", startTime: fixedNow, duration: thirtyMin)
        XCTAssertNotEqual(state1, state3)

        XCTAssertEqual(ElevationState.idle, ElevationState.idle)
        XCTAssertEqual(ElevationState.expired, ElevationState.expired)
        XCTAssertNotEqual(ElevationState.idle, ElevationState.expired)
    }

    // MARK: - Convenience Accessors

    func testAccessorsReturnNilWhenExpired() {
        let session = makeSession()
        session.start(reason: "Test", duration: thirtyMin, now: fixedNow)
        session.checkExpiry(now: fixedNow.addingTimeInterval(31 * 60))

        XCTAssertEqual(session.state, .expired)
        XCTAssertNil(session.activeReason)
        XCTAssertNil(session.activeDuration)
        XCTAssertNil(session.activeStartTime)
    }

    func testShouldReElevateFalseWhenExpired() {
        let session = makeSession(reElevationInterval: 1500)
        session.start(reason: "Test", duration: thirtyMin, now: fixedNow)
        session.checkExpiry(now: fixedNow.addingTimeInterval(31 * 60))

        XCTAssertFalse(session.shouldReElevate(now: fixedNow.addingTimeInterval(31 * 60)))
    }
}
