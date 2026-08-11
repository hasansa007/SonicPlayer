import Foundation

/// The haptic design, expressed as data so it can be reviewed and tested rather than only felt (#6).
///
/// Pure Foundation on purpose: `HapticsClient` turns these into `CHHapticEvent`s, and nothing about
/// *which* pulse fires needs CoreHaptics — or a device that can vibrate — to decide.
enum DetentFeedback {

    enum Event: CaseIterable {
        /// One click of the ring.
        case detent
        /// The value could not move — the start or end of a track, the top or bottom of a list.
        case limit
        /// A choice was taken.
        case commit
        /// A trim handle landed on a marker (#74).
        ///
        /// **Its own case rather than reusing `.limit`, which is what the issue asks for by
        /// weight.** `DialNavigator`'s second rule is "a tick that changes nothing is a `.limit`; a
        /// tick that changes anything is a `.detent`" — and a snap changes something, so borrowing
        /// `.limit` would quietly make that law untrue. Reusing it would also make a marker feel
        /// identical to the end of the file, which is the one thing the pulse has to distinguish.
        case snap
    }

    /// CoreHaptics' two axes, both `0...1`. Intensity is how hard; sharpness is how crisp — a low
    /// sharpness reads as a dull thud, a high one as a tap.
    struct Pulse: Equatable {
        var intensity: Double
        var sharpness: Double
    }

    /// **Prototype-derived, and the snap in particular wants a device.** A browser cannot render a
    /// haptic at all, so these are reasoned rather than felt — the same caveat §5 of the design
    /// attaches to `RotaryTracker`'s constants.
    ///
    /// `.snap` carries `.limit`'s weight, which is what #74 asks for, at a crisper sharpness: both
    /// are things you run into, but one is the end of the file and the other is a point inside it,
    /// and a thumb that cannot tell them apart learns to trust neither.
    static func pulse(for event: Event) -> Pulse {
        switch event {
        case .detent: Pulse(intensity: 0.5, sharpness: 0.8)
        case .limit:  Pulse(intensity: 0.9, sharpness: 0.3)
        case .commit: Pulse(intensity: 1.0, sharpness: 0.9)
        case .snap:   Pulse(intensity: 0.9, sharpness: 0.5)
        }
    }
}
