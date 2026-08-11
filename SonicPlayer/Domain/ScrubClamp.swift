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

    /// An arbitrary position, held inside the recording (#6).
    ///
    /// The two functions above step by a fixed `interval`; this one takes a position the caller has
    /// already computed — the wheel's detent seek, whose step is 0.1s and comes from `WheelRouter`.
    /// It lives here so the bounds of a scrub position have exactly one answer in this codebase.
    ///
    /// A non-positive duration means the asset has not loaded, and the answer is the start rather
    /// than a negative time: this feeds `seek(to:)`, and an `AVPlayer` seeked to a bad value does
    /// not recover.
    static func position(_ time: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard duration > 0 else { return 0 }
        return min(max(0, time), duration)
    }
}
