import Foundation
import Observation

/// Replaces `EditRecordingFeature` (#17).
///
/// Three things here are load-bearing:
///
/// 1. **Editing is non-destructive until save.** The editor works on a temp copy in
///    `<tmp>/SonicPlayer/edit/`; `originalURL` is only overwritten by `saveChanges()`. Every trim
///    replaces the temp file and deletes the previous one, so a discarded edit leaves the original
///    untouched and nothing accumulates in temp.
/// 2. **`AudioPlayerClient` wraps a process-lifetime `AVPlayer` shared with the main player.**
///    Every `stop()`-before-a-file-move is why moving a file out from under a playing `AVPlayer`
///    does not wedge it. Preserved verbatim from the reducer.
/// 3. **`playbackTask` replaces `.cancellable(id:, cancelInFlight: true)`** — cancel before
///    reassigning, or two time-update loops race and the scrubber jumps.
@MainActor
@Observable
final class EditRecordingViewModel: Identifiable {

    var id: UUID { recording.id }

    private(set) var recording: AudioFile
    /// The untouched original. Only `saveChanges()` replaces it.
    let originalURL: URL

    var hasEdits = false
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var trimStart: TimeInterval = 0
    var trimEnd: TimeInterval
    var isTrimming = false
    var isTrimming_InProgress = false
    var trimError: String?

    /// Called after the editor finishes with the file — save or discard. The parent uses it to
    /// dismiss and refresh; it replaces `PresentationAction.dismiss` being observed by AppFeature.
    var onFinished: () -> Void = {}

    /// Replaces `CancelID.playbackTimeUpdates`.
    private var playbackTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?

    private let audioPlayer: AudioPlayerClient
    private let audioTrimmer: AudioTrimmerClient
    private let fileManager: FileManagerClient

    init(
        recording: AudioFile,
        audioPlayer: AudioPlayerClient = .live,
        audioTrimmer: AudioTrimmerClient = .live,
        fileManager: FileManagerClient = .live
    ) {
        self.recording = recording
        self.originalURL = recording.url
        self.trimEnd = recording.duration
        self.audioPlayer = audioPlayer
        self.audioTrimmer = audioTrimmer
        self.fileManager = fileManager
    }

    /// See `PlayerViewModel` — a plain `deinit` on a `@MainActor` class is nonisolated and cannot
    /// read these at all.
    isolated deinit {
        playbackTask?.cancel()
        workTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Copies the original to a temp file so edits are non-destructive. Skips when the recording
    /// already *is* a temp copy — the inline recording editor hands one over already made.
    func onAppear() {
        currentTime = 0
        guard recording.url == originalURL else { return }

        let originalURL = self.originalURL
        let tempURL = Self.tempEditURL(pathExtension: originalURL.pathExtension)

        workTask?.cancel()
        workTask = Task { [weak self, fileManager] in
            do {
                try FileManager.default.copyItem(at: originalURL, to: tempURL)
                guard let metadata = try? await fileManager.getMetadata(tempURL) else { return }
                guard !Task.isCancelled else { return }
                self?.adoptTempCopy(metadata)
            } catch {
                print("Failed to create temp edit copy: \(error.localizedDescription)")
            }
        }
    }

    static func tempEditURL(pathExtension: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SonicPlayer/edit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("edit-\(UUID().uuidString).\(pathExtension)")
    }

    private func adoptTempCopy(_ audioFile: AudioFile) {
        recording = audioFile
        trimEnd = audioFile.duration
    }

    // MARK: - Playback

    func playPauseTapped() {
        if isPlaying {
            isPlaying = false
            stopPlaybackObserver()
            Task { [audioPlayer] in await audioPlayer.pause() }
            return
        }

        isPlaying = true
        let url = recording.url
        let startTime = currentTime
        let duration = recording.duration

        // `.cancellable(cancelInFlight: true)` — cancel the previous loop before starting another.
        playbackTask?.cancel()
        playbackTask = Task { [weak self, audioPlayer] in
            do {
                try await audioPlayer.prepare(url)
                await audioPlayer.seek(startTime)
                try await audioPlayer.play(url)
            } catch {
                self?.playbackEnded()
                return
            }

            for await time in await audioPlayer.timeUpdates() {
                if Task.isCancelled { return }
                if time >= duration, duration > 0 {
                    self?.playbackEnded()
                    return
                }
                self?.currentTime = time
            }
        }
    }

    func playbackEnded() {
        isPlaying = false
        currentTime = 0
        stopPlaybackObserver()
        Task { [audioPlayer] in await audioPlayer.stop() }
    }

    /// The scrubber writes straight through — the view drives position while dragging.
    func scrub(to time: TimeInterval) {
        currentTime = time
    }

    func skipForward() {
        let newTime = ScrubClamp.forward(from: currentTime, duration: recording.duration)
        currentTime = newTime
        Task { [audioPlayer] in await audioPlayer.seek(newTime) }
    }

    func skipBackward() {
        let newTime = ScrubClamp.backward(from: currentTime)
        currentTime = newTime
        Task { [audioPlayer] in await audioPlayer.seek(newTime) }
    }

    private func stopPlaybackObserver() {
        playbackTask?.cancel()
        playbackTask = nil
    }

    // MARK: - Trimming

    func trimTapped() {
        isTrimming = true
    }

    func trimStartChanged(_ time: TimeInterval) { trimStart = time }
    func trimEndChanged(_ time: TimeInterval) { trimEnd = time }

    func cancelTrim() {
        isTrimming = false
        trimStart = 0
        trimEnd = recording.duration
        trimError = nil
    }

    func applyTrim() {
        guard !isTrimming_InProgress else { return }
        beginTrimWork()

        let url = recording.url, start = trimStart, end = trimEnd
        workTask = Task { [weak self, audioPlayer, audioTrimmer] in
            do {
                await audioPlayer.stop()
                let trimmedURL = try await audioTrimmer.trimAudio(url, start, end)
                await self?.trimSucceeded(replacing: url, with: trimmedURL)
            } catch {
                self?.trimFailed(error)
            }
        }
    }

    func deleteRangeTapped() {
        guard isTrimming, !isTrimming_InProgress else { return }
        beginTrimWork()

        let url = recording.url, start = trimStart, end = trimEnd
        workTask = Task { [weak self, audioPlayer, audioTrimmer] in
            do {
                await audioPlayer.stop()
                let updatedURL = try await audioTrimmer.deleteAudioRange(url, start, end)
                await self?.trimSucceeded(replacing: url, with: updatedURL)
            } catch {
                self?.trimFailed(error)
            }
        }
    }

    private func beginTrimWork() {
        isTrimming_InProgress = true
        trimError = nil
        isPlaying = false
    }

    /// Shared by trim and delete-range — they differed only in which client call produced the URL.
    private func trimSucceeded(replacing previousURL: URL, with newURL: URL) async {
        if previousURL != newURL {
            try? FileManager.default.removeItem(at: previousURL)
        }
        isTrimming_InProgress = false
        isTrimming = false
        hasEdits = true
        currentTime = 0
        trimStart = 0

        if let metadata = try? await fileManager.getMetadata(newURL) {
            adoptTempCopy(metadata)
        }
    }

    private func trimFailed(_ error: Error) {
        isTrimming_InProgress = false
        trimError = error.localizedDescription
    }

    // MARK: - Finishing

    /// Replaces the original with the edited temp file. A no-op when nothing was edited.
    func saveChanges() {
        let tempURL = recording.url
        let originalURL = self.originalURL
        guard tempURL != originalURL else { onFinished(); return }

        Task { [audioPlayer] in
            await audioPlayer.stop()
            do {
                if FileManager.default.fileExists(atPath: originalURL.path) {
                    try FileManager.default.removeItem(at: originalURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: originalURL)
            } catch {
                print("Failed to save edits: \(error.localizedDescription)")
            }
        }
        onFinished()
    }

    func discardChanges() {
        let tempURL = recording.url
        let originalURL = self.originalURL

        Task { [audioPlayer] in
            await audioPlayer.stop()
            if tempURL != originalURL {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
        onFinished()
    }

    func renameTapped(_ newName: String) {
        let url = recording.url
        let fileExtension = url.pathExtension
        let finalName = newName.contains(".") ? newName : "\(newName).\(fileExtension)"
        let newURL = url.deletingLastPathComponent().appendingPathComponent(finalName)

        workTask = Task { [weak self, fileManager] in
            do {
                try await fileManager.renameItem(url, finalName)
                if let updated = try? await fileManager.getMetadata(newURL) {
                    self?.recording = updated
                } else {
                    self?.trimError = "Rename failed."
                }
            } catch {
                self?.trimError = error.localizedDescription
            }
        }
    }
}
