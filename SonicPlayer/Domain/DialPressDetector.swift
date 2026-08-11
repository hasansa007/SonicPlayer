import Foundation

/// Turns hub touches into `.press`, `.doublePress` and `.hold` (#6).
///
/// `DialCommand` documents `doublePressWindow` and `holdDuration` but nothing consumes them, and a
/// tuning constant with no consumer is a constant nobody can be wrong about. This is the consumer.
/// The navigator does not need it — the contract says the three arrive as distinct commands — so
/// this sits between the gesture and the navigator, on the view's side of the line but in
/// `Domain/`, because it is a decision statable without a view.
///
/// **Time arrives as a parameter, and the detector never reads a clock.** Same as `RotaryTracker`:
/// a half-second hold is tested in microseconds, and the two waits are scheduled by whoever owns a
/// run loop. `holdDeadline` and `settleDeadline` say when to come back, so the caller schedules
/// rather than polls and neither constant is re-derived at the call site.
///
/// **A single press is deferred, and that is the real cost of having a double-press at all.** It
/// cannot be emitted on release, because a second press inside the window would then arrive after
/// the first has already opened something. So `up` stays silent and `settle` pays out — one window
/// of latency on every press, in exchange for a gesture the contract calls invisible and requires a
/// visible partner for anyway.
struct DialPressDetector {

    private enum State: Equatable {
        case idle
        /// The hub is down. `since` is when, `isSecond` whether a press inside the window preceded
        /// it, and `didHold` whether the hold has already been paid out.so
        case down(since: TimeInterval, isSecond: Bool, didHold: Bool)
        /// Released, waiting to find out whether a second press is coming.
        case waiting(since: TimeInterval)
    }

    private var state: State = .idle

    init() {}

    mutating func down(at timestamp: TimeInterval) {
        let isSecond: Bool
        if case .waiting(let released) = state, timestamp - released <= DialCommand.doublePressWindow {
            isSecond = true
        } else {
            isSecond = false
        }
        state = .down(since: timestamp, isSecond: isSecond, didHold: false)
    }

    /// The hold, once the hub has been down long enough. Call from a timer scheduled at
    /// `holdDeadline`, or on any frame while down — asking twice cannot pay twice.
    mutating func elapsed(at timestamp: TimeInterval) -> DialCommand? {
        guard case .down(let since, let isSecond, let didHold) = state,
              !didHold,
              timestamp - since >= DialCommand.holdDuration
        else { return nil }

        state = .down(since: since, isSecond: isSecond, didHold: true)
        return .hold
    }

    /// The double-press, on the release that completes it. A first press resolves later, in
    /// `settle`; a release that already paid out a hold resolves as nothing at all.
    mutating func up(at timestamp: TimeInterval) -> DialCommand? {
        guard case .down(_, let isSecond, let didHold) = state else {
            state = .idle
            return nil
        }

        guard !didHold else {
            // A hold has been delivered, so this release is the end of it and nothing more. Idle
            // rather than waiting, or the next press would resolve as the second of a pair.
            state = .idle
            return nil
        }

        guard !isSecond else {
            state = .idle
            return .doublePress
        }

        state = .waiting(since: timestamp)
        return nil
    }

    /// The deferred single press, once a second one has been ruled out. Call from a timer
    /// scheduled at `settleDeadline`.
    mutating func settle(at timestamp: TimeInterval) -> DialCommand? {
        guard case .waiting(let released) = state,
              timestamp - released > DialCommand.doublePressWindow
        else { return nil }

        state = .idle
        return .press
    }

    /// When `elapsed` will have something to say, or nil when the hub is not down.
    var holdDeadline: TimeInterval? {
        guard case .down(let since, _, let didHold) = state, !didHold else { return nil }
        return since + DialCommand.holdDuration
    }

    /// When `settle` will have something to say, or nil when nothing is pending.
    var settleDeadline: TimeInterval? {
        guard case .waiting(let released) = state else { return nil }
        return released + DialCommand.doublePressWindow
    }
}
