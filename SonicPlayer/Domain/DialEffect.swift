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
    /// Off → all → one, and round. The host owns the order; this only asks for the next.
    case cycleRepeat
    case toggleShuffle
    /// Silence whatever is playing, because the screen being opened needs the audio to itself.
    ///
    /// **Recording and trimming both take the audio session.** A capture with a lecture playing
    /// records the lecture through the microphone; the trim editor previews the region under the
    /// handles, and previewing one file over another playing file is two things at once with one
    /// pair of ears. Neither is a state the user would choose deliberately, and both are reached in
    /// one press from a list of things they were listening to.
    ///
    /// Pause rather than stop: the track, its position and the queue survive, so Now Playing is
    /// still there to go back to when the recording ends.
    case pausePlayback
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
    /// Play just the kept region, so the trim can be heard before it is kept.
    ///
    /// **Removed and restored within the hour**, which is worth recording: it went out with the
    /// `Preview` chip on the reasoning that a third control stood between you and the trim. The
    /// control was the problem, not the capability — hearing the result before committing is the
    /// whole point of an editor. It is the hub's second state now rather than a chip of its own.
    case previewTrim(itemID: String, start: TimeInterval, end: TimeInterval)
    case commitTrim(itemID: String, start: TimeInterval, end: TimeInterval)

    /// **The complement of `commitTrim`: throw the selection away and keep the rest.**
    ///
    /// Same bounds, opposite meaning — trim keeps what is between the handles, this removes it and
    /// joins what is left. `AudioTrimmerClient.deleteAudioRange` has existed all along and had one
    /// caller, in the old sheet editor; the dial could select a region and only ever keep it.
    case commitCut(itemID: String, start: TimeInterval, end: TimeInterval)

    // MARK: - Items

    case item(DialItemAction, itemID: String)

    /// Rename the recording open in the editor.
    ///
    /// Separate from `.item` because `DialItemAction` is the stick's four nudges now, and rename is
    /// not one of them — it lives on the edit screen, where you are already changing the recording.
    case renameItem(itemID: String)

    /// Open the system file picker. A library is the place you add to, and reaching one from a card
    /// marked `Library` with no way to put anything in is the gap this fills.
    /// Bring audio in from Files. `intoItemID` is the folder to land in — `nil` for the library
    /// root. It used to take no argument, because Import only existed at the root.
    case importFiles(intoItemID: String?)

    /// Make a folder inside `inItemID`, or at the library root when `nil`. The host asks for a name.
    case createFolder(inItemID: String?)

    /// Re-read the library from disk. Raised by the bottom bar's sync control.
    case reloadLibrary

    /// Open Settings. Still a push rather than a dial route — when it becomes one, this goes.
    case openSettings
}
