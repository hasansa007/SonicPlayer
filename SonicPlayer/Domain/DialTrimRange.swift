import Foundation

/// The trim editor's selection, which cannot be crossed (#6).
///
/// **This is a type rather than two `TimeInterval`s because of what `ScrubClamp`'s header admits:**
/// `trimStart` and `trimEnd` in the old editor are "assigned straight from the slider with no
/// validation at all". Two independent numbers can always be crossed by whichever one is written
/// second, and the check then has to be repeated at every write site. Here the handles are private
/// and the only ways to move them are the two methods below, so `in ≤ out − minimumLength` holds by
/// construction — including for a range handed in already crossed.
///
/// The bounds against the recording itself come from `ScrubClamp.position`, so "inside the
/// recording" keeps the one answer this codebase already has.
struct DialTrimRange: Equatable {

    /// The shortest thing worth keeping. Below about this a trim is a mis-tap rather than an edit,
    /// and the two handles land on the same pixel with no way to tell them apart.
    static let minimumLength: TimeInterval = 0.5

    let duration: TimeInterval
    private(set) var start: TimeInterval
    private(set) var end: TimeInterval

    init(start: TimeInterval, end: TimeInterval, duration: TimeInterval) {
        self.duration = max(0, duration)
        self.start = ScrubClamp.position(min(start, end), duration: self.duration)
        self.end = ScrubClamp.position(max(start, end), duration: self.duration)
        separate()
    }

    /// Whether it moved — which is the whole signal the navigator needs to choose between `.detent`
    /// and `.limit`. Travel that is merely truncated by a bound still moved, and still clicks; only
    /// a handle already against the wall is silent.
    @discardableResult
    mutating func moveStart(by delta: TimeInterval) -> Bool {
        setStart(to: start + delta)
    }

    @discardableResult
    mutating func moveEnd(by delta: TimeInterval) -> Bool {
        setEnd(to: end + delta)
    }

    /// Places a handle at an exact time, subject to the same bounds a nudge obeys.
    ///
    /// **Snapping needs this rather than `moveStart(by: target - start)` (#74.)** A detent is 0.1s,
    /// which is not representable, so a handle walked there in tenths sits a few ulps off — and
    /// arriving *near* a marker is the failure snapping exists to prevent. Assigning the target
    /// makes the equality that decides whether the snap took a real one instead of a coin flip.
    ///
    /// The relative moves above are written in terms of these, so there is one clamp rather than
    /// two that agree today.
    @discardableResult
    mutating func setStart(to time: TimeInterval) -> Bool {
        let ceiling = max(0, end - Self.minimumLength)
        return assign(&start, to: min(ScrubClamp.position(time, duration: duration), ceiling))
    }

    @discardableResult
    mutating func setEnd(to time: TimeInterval) -> Bool {
        let floor = min(duration, start + Self.minimumLength)
        return assign(&end, to: max(ScrubClamp.position(time, duration: duration), floor))
    }

    /// What survives the trim.
    var length: TimeInterval { end - start }

    var inFraction: Double { fraction(start) }
    var outFraction: Double { fraction(end) }

    // MARK: - Private

    /// Pushes the handles apart until the minimum fits, preferring to move the end — the start is
    /// where the user's attention is. A recording too short to hold the minimum keeps its whole
    /// self rather than inventing time it does not have.
    private mutating func separate() {
        guard duration > 0 else {
            start = 0
            end = 0
            return
        }
        guard end - start < Self.minimumLength else { return }

        end = min(start + Self.minimumLength, duration)
        start = max(0, end - Self.minimumLength)
    }

    private func fraction(_ time: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return time / duration
    }

    private func assign(_ handle: inout TimeInterval, to value: TimeInterval) -> Bool {
        guard value != handle else { return false }
        handle = value
        return true
    }
}
