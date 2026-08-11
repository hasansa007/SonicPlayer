import Foundation

/// Which markers belong to which recording (#75).
///
/// **In memory, and deliberately so for this slice.** #75's "markers survive save and reload" needs
/// an on-disk contract, and the obvious one — a sidecar next to the `.m4a` — has to answer what
/// happens when the file is renamed, moved between collections, or deleted, all of which this app
/// does. That is a decision with alternatives and it deserves an ADR rather than being smuggled in
/// behind a dictionary. This type is the seam that decision will land on: every reader and writer
/// already goes through it, so swapping the backing store touches this file and nothing else.
///
/// Keyed by URL rather than by `AudioFile.id`, because the id is derived from the URL anyway and
/// the writer — a recording that has just been saved — has the URL and not the model.
@MainActor
final class MarkerRegistry {

    private var byRecording: [URL: RecordingMarkers] = [:]

    func markers(for url: URL) -> RecordingMarkers {
        byRecording[url] ?? RecordingMarkers()
    }

    func set(_ markers: RecordingMarkers, for url: URL) {
        guard !markers.isEmpty else {
            byRecording.removeValue(forKey: url)
            return
        }
        byRecording[url] = markers
    }

    /// **Forgetting is not tidiness, it is correctness.** A path can be reused — delete
    /// `Recording 3.m4a` and record another one, and `UniqueNameResolver` is free to hand out that
    /// exact name again. Without this, the new take inherits the dead one's markers and the editor
    /// snaps to points that were never in the audio.
    func forget(_ url: URL) {
        byRecording.removeValue(forKey: url)
    }
}
