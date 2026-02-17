import Foundation

/// Represents the current state of a privilege elevation session.
public enum ElevationState: Equatable, Sendable {
    case idle
    case active(reason: String, startTime: Date, duration: DurationOption)
    case expired
}

/// Tracks an active privilege elevation session: reason, timing, re-elevation scheduling.
public final class ElevationSession {
    public private(set) var state: ElevationState = .idle

    /// The interval between re-elevation calls (seconds). Defaults to 1500 (25 min).
    public var reElevationIntervalSeconds: TimeInterval

    /// Timestamp of the last re-elevation (or initial elevation).
    public private(set) var lastElevationTime: Date?

    public init(reElevationIntervalSeconds: TimeInterval = 1500) {
        self.reElevationIntervalSeconds = max(60, reElevationIntervalSeconds)
    }

    // MARK: - Session Lifecycle

    /// Start an elevation session with the given reason and duration.
    public func start(reason: String, duration: DurationOption, now: Date = Date()) {
        state = .active(reason: reason, startTime: now, duration: duration)
        lastElevationTime = now
    }

    /// Stop the current session and return to idle.
    public func stop() {
        state = .idle
        lastElevationTime = nil
    }

    // MARK: - Expiry

    /// Whether the session has expired based on elapsed time and chosen duration.
    public func isExpired(now: Date = Date()) -> Bool {
        guard case .active(_, let startTime, let duration) = state else {
            return false
        }
        // Special durations never expire
        if duration.isUntilLogout || duration.isIndefinite {
            return false
        }
        let elapsed = now.timeIntervalSince(startTime)
        let totalSeconds = TimeInterval(duration.minutes * 60)
        return elapsed >= totalSeconds
    }

    /// Check and transition to expired state if needed. Returns true if the session just expired.
    @discardableResult
    public func checkExpiry(now: Date = Date()) -> Bool {
        if case .active = state, isExpired(now: now) {
            state = .expired
            lastElevationTime = nil
            return true
        }
        return false
    }

    // MARK: - Remaining Time

    /// Returns the remaining time in seconds, or nil if not active or if the duration is special.
    public func remainingTime(now: Date = Date()) -> TimeInterval? {
        guard case .active(_, let startTime, let duration) = state else {
            return nil
        }
        // Special durations have no finite remaining time
        if duration.isUntilLogout || duration.isIndefinite {
            return nil
        }
        let totalSeconds = TimeInterval(duration.minutes * 60)
        let elapsed = now.timeIntervalSince(startTime)
        let remaining = totalSeconds - elapsed
        return max(0, remaining)
    }

    // MARK: - Re-elevation

    /// Returns true if enough time has passed since the last elevation and the session is still active (not expired).
    public func shouldReElevate(now: Date = Date()) -> Bool {
        guard case .active = state else {
            return false
        }
        // Check expiry first
        if isExpired(now: now) {
            return false
        }
        guard let lastTime = lastElevationTime else {
            return true
        }
        let elapsed = now.timeIntervalSince(lastTime)
        return elapsed >= reElevationIntervalSeconds
    }

    /// Record that a re-elevation just occurred.
    public func recordReElevation(at now: Date = Date()) {
        lastElevationTime = now
    }

    // MARK: - Convenience Accessors

    /// The reason for the current active session, or nil if not active.
    public var activeReason: String? {
        guard case .active(let reason, _, _) = state else {
            return nil
        }
        return reason
    }

    /// The duration option for the current active session, or nil if not active.
    public var activeDuration: DurationOption? {
        guard case .active(_, _, let duration) = state else {
            return nil
        }
        return duration
    }

    /// The start time of the current active session, or nil if not active.
    public var activeStartTime: Date? {
        guard case .active(_, let startTime, _) = state else {
            return nil
        }
        return startTime
    }

    // MARK: - Formatting

    /// Formats a remaining-time interval (in seconds) as a compact string for display.
    /// Examples: "27m", "1h 5m", "2h", "0m".
    public static func formatRemainingTime(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            if mins == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(mins)m"
        }
        return "\(totalMinutes)m"
    }
}
