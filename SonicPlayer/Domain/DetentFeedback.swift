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
    }

    /// CoreHaptics' two axes, both `0...1`. Intensity is how hard; sharpness is how crisp — a low
    /// sharpness reads as a dull thud, a high one as a tap.
    struct Pulse: Equatable {
        var intensity: Double
        var sharpness: Double
    }

    static func pulse(for event: Event) -> Pulse {
        switch event {
        case .detent: Pulse(intensity: 0.5, sharpness: 0.8)
        case .limit:  Pulse(intensity: 0.9, sharpness: 0.3)
        case .commit: Pulse(intensity: 1.0, sharpness: 0.9)
        }
    }
}
