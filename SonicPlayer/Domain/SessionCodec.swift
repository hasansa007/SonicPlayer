import Foundation

/// Decides what the persisted playback session should contain when the app leaves the
/// foreground, lifted from `PlayerFeature.scenePhaseChanged`.
enum SessionCodec {

    /// True when the queue has run out and the final track has effectively played to the end,
    /// in which case the session is cleared rather than saved — reopening the app should not
    /// resume a track the user already finished.
    ///
    /// The 1-second tolerance mirrors the polling interval: position is sampled roughly twice a
    /// second, so "finished" cannot mean an exact match against `duration`.
    static func isFinishedAtEndOfQueue(
        currentIndex: Int,
        queueCount: Int,
        currentTime: TimeInterval,
        duration: TimeInterval
    ) -> Bool {
        let isLastTrack = currentIndex == queueCount - 1
        let hasFinished = abs(currentTime - duration) < 1.0 && duration > 0
        return isLastTrack && hasFinished
    }

    /// Builds the session to persist. URLs are stored as `path` strings, matching the on-disk
    /// format that already exists in users' `session.json`.
    static func session(
        trackURL: URL,
        currentTime: TimeInterval,
        queueURLs: [URL],
        playlistSource: PlaylistSource?
    ) -> PlaybackSession {
        PlaybackSession(
            fileURL: trackURL.path,
            currentTime: currentTime,
            queue: queueURLs.map { QueueItem(fileURL: $0.path) },
            playlistSource: playlistSource
        )
    }
}
