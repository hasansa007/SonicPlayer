import Foundation

/// Retry schedule for restoring a playback session on cold launch.
///
/// `AVPlayer` frequently reports a duration of zero for the first moments after `prepare`, so
/// restore retries with a backoff rather than giving up. Extracted from
/// `PlayerFeature.retryRestoreSession`, where the schedule was written out twice — once for the
/// duration-not-ready path and once for the generic error path — with no shared constant.
enum SessionRestorePolicy {

    /// Attempts after the first, matching the original `maxRetries = 3`.
    static let maxRetries = 3

    /// Whether another attempt should be made. `attemptNumber` is zero-based.
    static func shouldRetry(attemptNumber: Int) -> Bool {
        attemptNumber < maxRetries
    }

    /// Exponential backoff: 500ms, 1s, 2s.
    ///
    /// Returns `nil` once the attempts are exhausted, so callers cannot accidentally sleep and
    /// retry past the limit — the shape the original duplicated `if` statements allowed.
    static func delayMilliseconds(forAttempt attemptNumber: Int) -> Int? {
        guard shouldRetry(attemptNumber: attemptNumber) else { return nil }
        return 500 * (1 << attemptNumber)
    }
}
