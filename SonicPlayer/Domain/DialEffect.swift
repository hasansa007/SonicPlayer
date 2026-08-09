import Foundation

/// What the navigator needs someone else to do (#6).
///
/// The same trick as `ShellEffect`, for the same reason: a value rather than a call, so the tests
/// assert intent instead of observing side effects, and so a pure `Domain/` type can ask for
/// playback and recording without importing either.
///
/// **Positions are absolute, not deltas.** `ShellEffect.seekBy` hands the shell a delta and lets it
/// do the clamping, which means the bounds of a seek live wherever the effect is applied. Here the
/// navigator already holds the position and the duration, so it clamps once with `ScrubClamp` and
/// says where to land. An effect that has already been bounded cannot be applied wrongly.
enum DialEffect: Equatable {

    case feedback(DetentFeedback.Event)

    // MARK: - Playback

    case play(itemID: String)
    case togglePlayPause
    /// Absolute, already inside `0...duration`.
    case seek(to: TimeInterval)
    /// Absolute, already inside `0...1`.
    case setVolume(Double)
    /// Absolute index, already inside the queue.
    case selectTrack(index: Int)

    // MARK: - Recording

    case startRecording
    case stopRecording
    case toggleRecordingPause
    case addMarker
    /// Absolute, already inside `0...1`.
    case setGain(Double)

    // MARK: - Editing

    /// Both handles at once, because they are one selection and `DialTrimRange` is what keeps them
    /// from crossing. Sending them separately would let a listener see a crossed intermediate.
    case setTrim(start: TimeInterval, end: TimeInterval)
    /// Carries its item and its bounds for the same reason `commitTrim` does, and the reason stated
    /// at the top of this file: the navigator already holds both, so an effect that arrives complete
    /// cannot be applied against a stale selection — or against the wrong recording.
    case previewTrim(itemID: String, start: TimeInterval, end: TimeInterval)
    case commitTrim(itemID: String, start: TimeInterval, end: TimeInterval)

    // MARK: - Items

    case item(DialItemAction, itemID: String)

    /// Open the system file picker. The only way into the app for audio it did not record itself,
    /// and with Home gone there was no longer anywhere else to ask for it.
    case importFiles

    /// Open Settings. Still a push rather than a dial route — when it becomes one, this goes.
    case openSettings
}
