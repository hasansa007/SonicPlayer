import Foundation

/// **Everything the user can say to the dial.**
///
/// The other half of the contract in `DialScreen`: the UI emits these and the navigator consumes
/// them. Four of them come from the wheel; the fifth comes from the action row above it.
///
/// **Why so few.** The earlier prototype gave the ring four labelled cardinal targets *and* a hub,
/// so the vocabulary carried `.back`, `.menu` and a transport enum. Moving the actions into a touch
/// row above the wheel collapsed all of that into `.action(id:)`, which means a new screen adds
/// chips rather than cases — and the wheel's own vocabulary stops growing.
enum DialCommand: Equatable {

    /// Signed detents, already multiplied by `RotaryTracker`'s acceleration.
    case tick(Int)

    /// A single press of the hub.
    case press

    /// Two presses inside `doublePressWindow`. Used for "open the editor" on a recording row.
    ///
    /// **This is an invisible affordance and needs a visible partner.** Nothing on screen announces
    /// it, and VoiceOver cannot perform it. Every double-press must also be reachable as an
    /// `.action` chip — the design does this on 1b, where `Edit` sits in the action row beside the
    /// gesture.
    case doublePress

    /// The hub held for `holdDuration`. Used for "jump to now playing" from anywhere.
    ///
    /// Same rule as `doublePress`: it is a shortcut, never the only route.
    case hold

    /// Signed detents from the *small* wheel, which only ever means volume.
    ///
    /// Separate from `.tick` rather than a mode of it: there are two wheels on Now Playing and they
    /// are turned independently, so a single tick case would need a sender and that is a mode by
    /// another name.
    case volumeTick(Int)

    /// A chip in the action row was tapped. The `id` matches `DialScreen.Action.id`.
    ///
    /// Touch and wheel are equals here — the wheel highlights and presses, the finger taps
    /// directly, and both arrive as commands the navigator handles identically.
    case action(String)

    /// The stick has just travelled far enough to count as a nudge.
    ///
    /// **Sent while the thumb is still down, and it is the whole point.** The nudge's action fires
    /// on release, so until now nothing was felt at the moment the stick engaged — you pushed, felt
    /// nothing, and learned whether it had taken only after letting go, by which time the choice was
    /// already made. Every physical detented control answers at the moment you cross into the
    /// detent, not when you stop pressing.
    ///
    /// A command rather than a haptic call inside `DialRing`, because the ring emits commands and
    /// knows nothing else — the navigator answers this the way it answers every other feedback.
    case nudgeEngaged

    /// A trim handle dragged straight to a position, `0...1` of the recording.
    ///
    /// **It names the handle, because dragging one selects it.** The finger is coarse and the wheel
    /// is fine, so the pairing this screen wants is drag-then-nudge — and that only works if the
    /// wheel picks up the handle the finger just let go of.
    ///
    /// Absolute rather than a delta, for the reason `DialEffect` gives at the top of its own file:
    /// the sender already knows where in the waveform the finger is, so a value that arrives
    /// complete cannot be applied against a stale position.
    case dragTrim(handle: DialScreen.Handle, fraction: Double)

    /// How long two presses may be apart and still count as one double-press.
    ///
    /// Tuned to Apple's own double-tap window rather than guessed. Longer than this and a
    /// deliberate second press feels ignored; shorter and an ordinary pair of presses fires the
    /// editor by accident.
    static let doublePressWindow: TimeInterval = 0.3

    /// How long the hub must be held. Deliberately longer than the double-press window so a slow
    /// press cannot resolve as both.
    static let holdDuration: TimeInterval = 0.5
}
