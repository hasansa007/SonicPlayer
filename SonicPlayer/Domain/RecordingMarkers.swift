import Foundation

/// The timestamps dropped during a capture (#75).
///
/// **The whole screen is the target, which is why refusal is a feature.** #75 makes marking a
/// tap anywhere rather than a small button, precisely so it can be done without looking — and the
/// cost of a target that large is that a fumble, a bag, or a thumb resting on the glass produces
/// two markers where the user meant one. `add(at:)` refuses anything landing within
/// `minimumSeparation` of a marker already there, so the failure mode of the large target is
/// absorbed here instead of showing up as noise in the editor.
///
/// The times are kept sorted, so `MarkerSnap` and the editor can rely on the order without each
/// sorting a copy. Insertion is ordered rather than append-then-sort because a capture only ever
/// appends at the end anyway — the sort exists for a set handed in from outside.
struct RecordingMarkers: Equatable {

    /// The closest two markers may sit. Deliberately its own constant rather than a reference to
    /// `DialTrimRange.minimumLength`, which happens to hold the same number today: one is "the
    /// shortest audio worth keeping" and the other is "closer than this was one tap, not two".
    /// Tuning either on a device must not silently move the other — the same reasoning that keeps
    /// `DialNavigator.gainPerDetent` separate from `WheelRouter.volumePerDetent`.
    static let minimumSeparation: TimeInterval = 0.5

    private(set) var times: [TimeInterval]

    init(times: [TimeInterval] = []) {
        self.times = []
        for time in times.sorted() { add(at: time) }
    }

    var isEmpty: Bool { times.isEmpty }
    var count: Int { times.count }

    /// Whether the marker landed — which is the signal the caller needs to choose between a commit
    /// pulse and nothing at all. Same shape, and the same reason, as `DialTrimRange.moveStart`.
    ///
    /// A negative time is clamped rather than refused: it can only arrive from a clock that has not
    /// started, and marking the very beginning of a capture is a real thing to want.
    @discardableResult
    mutating func add(at time: TimeInterval) -> Bool {
        let time = max(0, time)
        guard !times.contains(where: { abs($0 - time) < Self.minimumSeparation }) else { return false }

        let index = times.firstIndex { $0 > time } ?? times.endIndex
        times.insert(time, at: index)
        return true
    }
}
