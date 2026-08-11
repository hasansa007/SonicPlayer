import Foundation

/// Plays back what a trim would keep, and stops where it ends (#74).
///
/// **It exists because "play from X, stop at Y" is not something `PlayerViewModel` can do.** That
/// type plays a queue to its end; bounding a range is a different job, and pushing it in would put
/// a preview's lifetime inside the object that owns the user's listening session.
///
/// The shape is lifted from `EditRecordingViewModel.playPauseTapped` — `prepare`, `seek`, `play`,
/// then watch `timeUpdates` — because that is the pattern already proven against this client, down
/// to `playbackTask` standing in for `.cancellable(cancelInFlight: true)`: cancel before
/// reassigning, or two loops race and each stops the other's preview.
///
/// **It shares the process-lifetime `AVPlayer` with the main player, so previewing interrupts
/// playback.** That is not incidental — `AudioPlayerClient` has one engine, and the recording
/// editor has always behaved this way. The caller pauses the player first so the transport does not
/// go on claiming it is playing something it no longer owns.
@MainActor
final class TrimPreview {

    private var task: Task<Void, Never>?
    private let audioPlayer: AudioPlayerClient

    init(audioPlayer: AudioPlayerClient = .live) {
        self.audioPlayer = audioPlayer
    }

    /// See `PlayerViewModel` — a plain `deinit` on a `@MainActor` class is nonisolated and cannot
    /// read this at all.
    isolated deinit {
        task?.cancel()
    }

    func play(url: URL, from start: TimeInterval, to end: TimeInterval) {
        task?.cancel()
        task = Task { [audioPlayer] in
            do {
                try await audioPlayer.prepare(url)
                await audioPlayer.seek(start)
                try await audioPlayer.play(url)
            } catch {
                return
            }

            for await time in await audioPlayer.timeUpdates() {
                if Task.isCancelled { return }
                guard time < end else {
                    await audioPlayer.pause()
                    return
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        Task { [audioPlayer] in await audioPlayer.pause() }
    }
}
