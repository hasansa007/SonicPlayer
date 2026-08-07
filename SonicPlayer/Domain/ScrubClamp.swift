import Foundation

/// Clamps the audio editor's scrub position to the bounds of the recording.
///
/// Extracted from `RecordingFeature`'s `.skipForward` and `.skipBackward`, which each inlined
/// one half of the same rule along with a repeated `15` literal.
///
/// #11 called this `TrimRangeValidator`. Renamed because it validates no range and has nothing
/// to do with trimming: `trimStart` and `trimEnd` are assigned straight from the slider with no
/// validation at all. Adding some would be a behaviour change, so it stays out — see #34.
enum ScrubClamp {

    /// The editor scrubs in 15-second steps.
    static let interval: TimeInterval = 15

    /// Never scrubs past the end of the recording.
    ///
    /// A recording shorter than one interval clamps to its own duration, and a position already
    /// past the end stays there rather than moving backwards.
    static func forward(from currentTime: TimeInterval, duration: TimeInterval) -> TimeInterval {
        min(currentTime + interval, duration)
    }

    /// Never scrubs before the start.
    ///
    /// Takes no duration because the original did not — skipping backwards is bounded at zero
    /// only, and a position past the end can be scrubbed back from freely.
    static func backward(from currentTime: TimeInterval) -> TimeInterval {
        max(currentTime - interval, 0)
    }
}
