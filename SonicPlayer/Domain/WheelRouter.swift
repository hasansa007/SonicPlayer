import Foundation

/// What a command does, given what currently has the wheel (#6).
///
/// **This is a separate type because it is the piece that grows.** Every focus and every menu level
/// this epic adds is a case here, and `PlayerViewModel` reached 633 lines by absorbing exactly that
/// kind of growth. As a pure function it stays a table, and a table can be tested exhaustively.
enum WheelRouter {

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

    static func route(_ command: WheelCommand, focus: WheelFocus) -> [ShellEffect] {
        switch command {
        case .tick(let detents):
            guard detents != 0 else { return [] }
            switch focus {
            case .nowPlaying(.seek):
                return [.seekBy(TimeInterval(detents) * secondsPerDetent), .feedback(.detent)]
            case .nowPlaying(.volume):
                return [.volumeBy(Double(detents) * volumePerDetent), .feedback(.detent)]
            case .nowPlaying(.speed):
                return [.speedBy(detents), .feedback(.detent)]
            }

        case .select:
            return [.playPause, .feedback(.commit)]

        case .transport(.previous):
            return [.previousTrack, .feedback(.commit)]
        case .transport(.next):
            return [.nextTrack, .feedback(.commit)]
        case .transport(.playPause):
            return [.playPause, .feedback(.commit)]

        // Slice 1 has no menu and no level to pop. **Inert, not absent** — the ring already draws
        // both targets, and a target that quietly does nothing beats one that appears under the
        // thumb when slice 2 lands.
        case .back, .menu:
            return []
        }
    }
}

/// What the shell should do about it.
///
/// A value rather than a call, so `ShellViewModelTests` can assert intent instead of observing side
/// effects — and so the routing table above needs nothing injected to be tested.
enum ShellEffect: Equatable {
    case seekBy(TimeInterval)
    case volumeBy(Double)
    case speedBy(Int)
    case playPause
    case nextTrack
    case previousTrack
    case feedback(DetentFeedback.Event)
}
