import Foundation

/// **How far one turn of the wheel goes.** Three numbers, and nothing that decides anything.
///
/// This was `WheelRouter`, a routing table mapping a command plus a focus to a `[ShellEffect]`, and
/// its own doc said it was "the piece that grows". It did not grow — `DialNavigator` was written
/// instead, and routing moved there as a state machine over `DialScreen`. What survived the move is
/// exactly the physics: the router's `route(_:focus:)` had one caller left, `ShellViewModel`, which
/// nothing constructed.
///
/// Renamed rather than emptied in place, because a type called `Router` holding no routes is the
/// kind of thing the next reader restores a caller to (#76).
enum WheelMetrics {

    /// One detent of seeking. The *fine* step — coarse travel is dragging `SonicScrubber`, and that
    /// pairing is what the whole design rests on: a finger is fast and rough, a detent is slow and
    /// exact.
    static let secondsPerDetent: TimeInterval = 0.1

    /// One detent of volume, as a fraction of the full range. Fifty detents end to end.
    ///
    /// Right for a wheel, which is turned continuously — fifty steps across the range is what makes
    /// it feel like a dial rather than a set of buttons.
    static let volumePerDetent: Double = 0.02

    /// One *nudge* of volume, from the stick's vertical axis.
    ///
    /// **Five times the detent, because a nudge is a press and not a turn.** The stick reused
    /// `volumePerDetent`, so one push moved the level by two percent — which is doing exactly what
    /// it was told and completely inaudible, and reads as a control that does nothing. Ten steps end
    /// to end is roughly what iOS gives its own hardware buttons.
    static let volumePerNudge: Double = 0.1
}
