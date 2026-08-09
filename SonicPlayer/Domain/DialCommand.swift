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

    /// A chip in the action row was tapped. The `id` matches `DialScreen.Action.id`.
    ///
    /// Touch and wheel are equals here — the wheel highlights and presses, the finger taps
    /// directly, and both arrive as commands the navigator handles identically.
    case action(String)

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
