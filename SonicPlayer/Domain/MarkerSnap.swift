import Foundation

/// Where a trim handle should land when a marker is nearby (#74).
///
/// **Snapping is decided on *entering* a marker's zone, never on being inside it**, and that single
/// rule is what keeps a handle from sticking. The obvious implementation — "if the new value is
/// within tolerance of a marker, use the marker" — parks the handle on the first marker it touches
/// and never lets go: the next detent moves it 0.1s, which is still within one detent of the
/// marker, so it snaps straight back. The wheel then feels broken in the one place it was supposed
/// to feel best.
///
/// Comparing where the handle *was* against where it *is* fixes that, and buys a second property
/// worth having: a fast spin that vaults clean over a marker does not snap to it. Acceleration goes
/// up to ×40, so a single tick can cover four seconds — grabbing a marker in the middle of that
/// would be a hand brake, not an aid.
///
/// **The tolerance is a parameter because it is a property of the input, not of the markers.**
/// §5 of the design: a few points for a finger, one detent for the wheel. Only the wheel's half is
/// supplied today — the finger's needs the waveform's rendered width, which arrives with the view.
enum MarkerSnap {

    /// The marker `value` should snap to, or `nil` to leave it where it is.
    ///
    /// `markers` is expected sorted; ties break toward the earlier one either way, so an unsorted
    /// array gives the same answer rather than an arbitrary one.
    static func target(
        for value: TimeInterval,
        from previous: TimeInterval,
        markers: [TimeInterval],
        tolerance: TimeInterval
    ) -> TimeInterval? {
        guard tolerance > 0 else { return nil }

        return markers
            .filter { abs(value - $0) <= tolerance && abs(previous - $0) > tolerance }
            .min { lhs, rhs in
                let left = abs(value - lhs), right = abs(value - rhs)
                return left == right ? lhs < rhs : left < right
            }
    }
}
