import Foundation
import Observation
import SwiftUI
import UIKit

/// Replaces `PlayerFeature` (#15) — the largest and most-depended-on reducer in the app.
///
/// Three things here are load-bearing and easy to lose in a rewrite:
///
/// 1. **The time observer is cancelled by identity at six sites plus `deinit`.** TCA's
///    `.cancel(id: CancelID.timeObserver)` did this centrally; here it is an owned `Task` and
///    every site that stops or replaces playback must cancel it, or observers accumulate and
///    playback appears to jump.
/// 2. **`AudioPlayerClient` wraps a process-lifetime `AVPlayer` shared with the recording
///    editor.** Every `stop()`-before-file-move exists because of that. Preserved verbatim.
/// 3. **Session persistence writes the same JSON to the same path** as the `@Shared` version it
///    replaces, or existing users stop resuming after an update.
@MainActor
@Observable
final class PlayerViewModel {

    // MARK: - Persisted

    private let sessionStore: SessionStore
    private var session: PlaybackSession

    // MARK: - Preferences

    var playbackSpeed: PlaybackSpeed
    var skipDuration: SkipDuration
    var repeatMode: RepeatMode
    var isShuffleEnabled: Bool

    // MARK: - Runtime

    var currentTrack: AudioFile?
    var artwork: UIImage?
    var colors: [Color] = []

    var queue: [AudioFile] = []
    var currentIndex: Int = 0
    var currentPlaylistSource: PlaylistSource?
    var originalQueue: [AudioFile] = []

    var isPlaying = false
    /// `0...1`, this app's own gain. See `setVolume(_:)` for why it is not the system volume.
    var volume: Double = 1
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isLoadingTrack = false
    var isExpanded = false

    /// Why a file handed over by another app could not be played. Presented with the app's
    /// existing "Action Failed" alert rather than a new surface. Was a `try?` that dropped the
    /// reason on the floor and left the user on Home with no explanation (#33).
    var openError: String?

    /// Set the moment an open-from-Files arrives, and never cleared: for the life of this launch
    /// the user has named the track they want, and a restored session must not override it.
    ///
    /// A flag rather than cancelling the restore task, because `.onOpenURL` and `.onAppear` have
    /// no guaranteed order — cancelling only covers the case where the restore started first.
    private var didOpenExplicitly = false

    /// True from the moment an open-from-Files is requested until its detached import finishes.
    /// Read by `AppViewModel` before draining iOS's staging directory (#41) — that import is the
    /// one other thing that touches the same files.
    private(set) var isImporting = false

    // MARK: - Derived

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var currentTimeFormatted: String? { Self.formatTime(currentTime) }
    var durationFormatted: String? { Self.formatTime(duration) }

    var hasNextTrack: Bool { !queue.isEmpty && currentIndex < queue.count - 1 }
    var hasPreviousTrack: Bool { !queue.isEmpty && currentIndex > 0 }
    var shouldShowMiniPlayer: Bool { currentTrack != nil && !isExpanded && duration > 0 }

    /// Past this point into a track, "previous" is understood as *restart this one* — which is
    /// why the button stays live at the head of the queue.
    static let restartThreshold: TimeInterval = 3

    /// Kept off the view so `PlayerView` holds no thresholds of its own (#47). The literal `3`
    /// used to sit inline in the button's `.disabled(...)`, where nothing named it.
    var canRestartCurrentTrack: Bool { currentTime >= Self.restartThreshold }

    // MARK: - Effects

    /// Replaces `CancelID.timeObserver`. Must be cancelled wherever the reducer cancelled it.
    private var timeObserverTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var volumeObserverTask: Task<Void, Never>?

    private let audioPlayer: AudioPlayerClient
    private let systemVolume: SystemVolumeClient
    private let fileManager: FileManagerClient
    private let artworkClient: ArtworkClient
    private let repository: PlaybackRepository

    init(
        audioPlayer: AudioPlayerClient = .live,
        systemVolume: SystemVolumeClient = .live,
        fileManager: FileManagerClient = .live,
        artworkClient: ArtworkClient = .live,
        sessionStore: SessionStore = SessionStore(),
        repository: PlaybackRepository? = nil
    ) {
        self.audioPlayer = audioPlayer
        self.systemVolume = systemVolume
        self.fileManager = fileManager
        self.artworkClient = artworkClient
        self.sessionStore = sessionStore
        // Defaulted from `fileManager` rather than from `.live`, so a caller that substitutes the
        // client gets a repository built on that substitute. Defaulting to `.live` here would let
        // a test pass a stub client and still hit the real filesystem, which is the failure this
        // whole change exists to remove.
        self.repository = repository ?? LivePlaybackRepository(files: fileManager)
        self.session = sessionStore.load()

        playbackSpeed = UserDefaults.standard.savedPlaybackSpeed
        skipDuration = UserDefaults.standard.savedSkipDuration
        repeatMode = UserDefaults.standard.savedRepeatMode
        isShuffleEnabled = UserDefaults.standard.savedShuffleEnabled

        // Seeded, then followed. Without the seed the dial's arc would read full until the first
        // change; without the stream the hardware buttons would move the volume behind its back,
        // which is half of what "not synced with the device" meant.
        volume = systemVolume.level()
        volumeObserverTask = Task { [weak self, changes = systemVolume.changes] in
            for await level in changes() {
                guard let self else { return }
                self.volume = level
            }
        }
    }

    /// TCA cancelled in-flight effects when the store scope died. Nothing does that here.
    ///
    /// `isolated` because a plain `deinit` on a `@MainActor` class is nonisolated and so cannot
    /// read the two task properties at all. Both tasks capture `self` weakly, so this is
    /// reachable rather than kept alive by what it is cancelling.
    isolated deinit {
        timeObserverTask?.cancel()
        loadTask?.cancel()
        volumeObserverTask?.cancel()
    }

    // MARK: - Transport

    func playPauseTapped() {
        if isPlaying {
            isPlaying = false
            stopTimeObserver()
            Task { [audioPlayer] in await audioPlayer.pause() }
        } else if currentTrack != nil {
            isPlaying = true
            let rate = playbackSpeed.rawValue
            Task { [audioPlayer] in
                await audioPlayer.resume()
                await audioPlayer.setRate(rate)
            }
            startTimeObserver()
        }
    }

    func loadTrack(_ track: AudioFile, queue newQueue: [AudioFile]?, source: PlaylistSource?) {
        isLoadingTrack = true
        isPlaying = false
        currentTrack = track

        if let newQueue {
            if isShuffleEnabled {
                originalQueue = newQueue
                if let result = QueueMath.shuffling(newQueue, keeping: track) {
                    queue = result.queue
                    currentIndex = result.currentIndex
                }
            } else {
                queue = newQueue
                currentIndex = newQueue.firstIndex(of: track) ?? 0
            }
            // A new queue always replaces the source
            currentPlaylistSource = source
        } else if let source {
            // Navigating within the existing queue only updates it when given
            currentPlaylistSource = source
        }
        currentTime = 0

        stopTimeObserver()
        loadArtwork()

        loadTask?.cancel()
        loadTask = Task { [audioPlayer] in
            do {
                try await audioPlayer.play(track.url)
                guard !Task.isCancelled else { return }
                await trackLoaded()
            } catch {
                guard !Task.isCancelled else { return }
                trackLoadFailed()
            }
        }
    }

    private func trackLoaded() async {
        isLoadingTrack = false
        isPlaying = true
        let rate = playbackSpeed.rawValue
        let seekTo = currentTime

        // Standing registration, not a one-shot effect: these fire whenever the lock screen does.
        audioPlayer.setRemoteHandlers(
            { [weak self] in Task { @MainActor in self?.nextTrack() } },
            { [weak self] in Task { @MainActor in self?.previousTrack() } }
        )

        await audioPlayer.setRate(rate)
        if seekTo > 0 { await audioPlayer.seek(seekTo) }
        let loaded = await audioPlayer.duration()
        durationUpdated(loaded)
        startTimeObserver()
    }

    private func trackLoadFailed() {
        isLoadingTrack = false
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        currentTime = time
        Task { [audioPlayer] in await audioPlayer.seek(time) }
    }

    /// Clamping is delegated to AVFoundation, exactly as the reducer did.
    func skipForward() {
        let interval = skipDuration.rawValue
        Task { [audioPlayer] in await audioPlayer.skipForward(interval) }
    }

    func skipBackward() {
        let interval = skipDuration.rawValue
        Task { [audioPlayer] in await audioPlayer.skipBackward(interval) }
    }

    func nextTrack() {
        if hasNextTrack {
            currentIndex += 1
            loadTrack(queue[currentIndex], queue: nil, source: nil)
        } else if repeatMode == .all, !queue.isEmpty {
            jumpToTrack(0)
        }
    }

    func previousTrack() {
        switch QueueMath.decideOnPrevious(
            currentTime: currentTime,
            hasPreviousTrack: hasPreviousTrack,
            currentIndex: currentIndex
        ) {
        case .restart:
            seek(to: 0)
        case let .previous(index):
            currentIndex = index
            loadTrack(queue[index], queue: nil, source: nil)
        }
    }

    func jumpToTrack(_ index: Int) {
        guard index >= 0, index < queue.count else { return }
        currentIndex = index
        loadTrack(queue[index], queue: nil, source: nil)
    }

    // MARK: - Preferences

    func setPlaybackSpeed(_ speed: PlaybackSpeed) {
        playbackSpeed = speed
        UserDefaults.standard.savedPlaybackSpeed = speed
        let rate = speed.rawValue
        Task { [audioPlayer] in await audioPlayer.setRate(rate) }
    }

    /// **The device's media volume, not this app's gain.** It used to be the latter, on the
    /// reasoning that per-player gain cannot fight the hardware buttons. True, and the wrong trade:
    /// what it bought was two levels that disagreed, so pressing the buttons left the dial's arc
    /// where it was and turning the dial left the system slider where it was. A volume control on a
    /// media player is expected to mean the volume. See `SystemVolumeClient` for what writing it
    /// costs.
    ///
    /// Not persisted, and now it cannot be: the level belongs to the device and outlives the app.
    func setVolume(_ value: Double) {
        volume = min(max(0, value), 1)
        systemVolume.setLevel(volume)
    }

    func setSkipDuration(_ duration: SkipDuration) {
        skipDuration = duration
        UserDefaults.standard.savedSkipDuration = duration
    }

    func toggleRepeatMode() {
        repeatMode = QueueMath.nextRepeatMode(after: repeatMode)
        UserDefaults.standard.savedRepeatMode = repeatMode
    }

    func toggleShuffle() {
        isShuffleEnabled.toggle()
        UserDefaults.standard.savedShuffleEnabled = isShuffleEnabled

        if isShuffleEnabled {
            originalQueue = queue
            if let result = QueueMath.shuffling(queue, keeping: currentTrack) {
                queue = result.queue
                currentIndex = result.currentIndex
            }
        } else if !originalQueue.isEmpty {
            let track = currentTrack
            queue = originalQueue
            if let track {
                currentIndex = originalQueue.firstIndex(of: track) ?? 0
            }
            originalQueue = []
        }
    }

    func toggleExpansion() { isExpanded.toggle() }
    func setExpanded(_ expanded: Bool) { isExpanded = expanded }

    // MARK: - Time observation

    private func startTimeObserver() {
        timeObserverTask?.cancel()
        timeObserverTask = Task { [weak self, audioPlayer] in
            for await time in await audioPlayer.timeUpdates() {
                if Task.isCancelled { return }
                await MainActor.run { self?.timeUpdate(time) }
            }
        }
    }

    private func stopTimeObserver() {
        timeObserverTask?.cancel()
        timeObserverTask = nil
    }

    private func timeUpdate(_ time: TimeInterval) {
        currentTime = time

        switch QueueMath.decideOnTrackEnd(
            isPlaying: isPlaying,
            duration: duration,
            currentTime: time,
            repeatMode: repeatMode,
            hasNextTrack: hasNextTrack,
            queueIsEmpty: queue.isEmpty
        ) {
        case .repeatCurrent:
            currentTime = 0
            let rate = playbackSpeed.rawValue
            Task { [audioPlayer] in
                await audioPlayer.seek(0)
                await audioPlayer.resume()
                await audioPlayer.setRate(rate)
            }
            return

        case .advance:
            nextTrack()
            return

        case .wrapToStart:
            jumpToTrack(0)
            return

        case .stop:
            // Stay on the current track, parked at the end
            isPlaying = false
            currentTime = duration
            stopTimeObserver()
            Task { [audioPlayer] in await audioPlayer.pause() }
            return

        case .none:
            break // still playing — fall through to the periodic work
        }

        if duration == 0 {
            Task { [weak self, audioPlayer] in
                let loaded = await audioPlayer.duration()
                if loaded > 0 { await MainActor.run { self?.durationUpdated(loaded) } }
            }
        } else if Int(time) % 3 == 0 {
            // Keep the lock screen in sync, roughly every 3s at a 0.5s tick
            Task { [audioPlayer] in await audioPlayer.updateNowPlaying() }
        }
    }

    private func durationUpdated(_ newDuration: TimeInterval) {
        duration = newDuration
        Task { [audioPlayer] in await audioPlayer.updateNowPlaying() }
    }

    // MARK: - Artwork

    private func loadArtwork() {
        guard let track = currentTrack else {
            artwork = nil
            colors = []
            return
        }
        Task { [weak self, artworkClient] in
            async let image = artworkClient.getArtwork(track.url)
            async let palette = artworkClient.getColors(track.url, false, Color.sonicTealColors)
            let (loadedImage, loadedColors) = await (image, palette)
            await MainActor.run {
                self?.artwork = loadedImage
                self?.colors = loadedColors
            }
        }
    }

    // MARK: - Open in

    /// Import a file handed over by another app, then play **what was actually written**.
    ///
    /// Lives here rather than in the root reducer (where it was) because it is playback
    /// orchestration and because the session-restore it has to outrank is right below it. Three
    /// things differ from the version it replaces, all of them #33:
    ///
    /// - the track is resolved from `OpenInImport`'s return value, not from a path computed
    ///   before the copy ran
    /// - the copy and the metadata read can fail, and the failure reaches the user
    /// - it claims priority over `restoreSession` synchronously, before any `await`, so the
    ///   ordering holds whichever of `.onOpenURL` / `.onAppear` fires first
    ///
    /// `onImported` fires once the file is on disk and before playback starts, so the browser and
    /// the recents list refresh in the same order the reducer's `.refreshFiles` did.
    func openFromFiles(_ url: URL, onImported: @escaping @MainActor () -> Void = {}) {
        didOpenExplicitly = true
        // Set synchronously, before the task exists, so `.onOpenURL` returning already means "an
        // import is in flight". The staging drain (#41) reads this: the move below runs detached
        // and can still be going when the app backgrounds, and a drain that fired then would
        // delete the file out from under it — losing the import and reporting a failure for an
        // open iOS had already accepted.
        isImporting = true
        let documentsDirectory = fileManager.documentsDirectory()
        Task { [weak self, fileManager] in
            defer { self?.isImporting = false }
            do {
                // Detached because the copy must not run on the main actor: an audiobook-sized
                // file would freeze the UI for the length of the write. `Effect.run` gave this
                // for free — a bare `Task` inside a `@MainActor` type inherits the actor and
                // would not.
                let imported = try await Task.detached {
                    try OpenInImport.run(url: url, into: documentsDirectory)
                }.value
                onImported()
                let file = try await fileManager.getMetadata(imported)
                self?.loadTrack(file, queue: [file], source: .singleFile)
            } catch {
                self?.openError = error.localizedDescription
            }
        }
    }

    // MARK: - Session

    func restoreSession() {
        // Nothing was saved. This has to be checked here rather than relying on the guard below,
        // because `URL(fileURLWithPath: "")` resolves to the process's *current directory* — not
        // to nothing. That directory exists and `resourceValues` succeeds on it, so the guard
        // passes and a folder gets restored as a track: on iOS it surfaced as a mini player
        // titled `/` (#33).
        guard !session.isEmpty else { return }

        // An explicit open outranks a restored session. Launching the app BY opening a file runs
        // both this and `openFromFiles` against the same `currentTrack` and the same AVPlayer,
        // and whichever finished last won — which is why a repeat open looked like it did
        // nothing (#33).
        guard !didOpenExplicitly else { return }

        let saved = session
        Task { [weak self, repository] in
            // Resolution — which files still exist, and which index the track sits at — is the
            // repository's job now (#44). It used to be inline here, reaching `FileManager`
            // directly while this type held an injected client, so no test could drive it.
            guard let resolved = await repository.restore(saved) else {
                await MainActor.run { self?.clearSession() }
                return
            }

            // Re-checked after the await above: an open can arrive while the repository is
            // resolving, and `restoreWithRetry` drives the shared player, so landing late would
            // replace the opened track *and* pause it.
            let claimed = await MainActor.run { [weak self] in
                guard let self, !self.didOpenExplicitly else { return false }
                self.sessionLoaded(
                    track: resolved.track, queue: resolved.queue, index: resolved.index
                )
                return true
            }
            guard claimed else { return }
            await self?.restoreWithRetry(track: resolved.track, time: saved.currentTime)
        }
    }

    private func sessionLoaded(track: AudioFile, queue loaded: [AudioFile], index: Int) {
        currentTrack = track
        queue = loaded
        currentIndex = index
        currentPlaylistSource = session.playlistSource
        isPlaying = false
        loadArtwork()
    }

    /// A loop rather than the reducer's self-resending action. `SessionRestorePolicy` returns nil
    /// once attempts are exhausted, so this cannot sleep-and-retry past the limit.
    private func restoreWithRetry(track: AudioFile, time: TimeInterval) async {
        var attempt = 0
        let rate = playbackSpeed.rawValue

        while true {
            do {
                try await audioPlayer.prepare(track.url)
                await audioPlayer.setRate(rate)
                await audioPlayer.seek(time)
                await audioPlayer.pause()

                // AVPlayer often reports 0 for a moment after prepare
                let loaded = await audioPlayer.duration()
                if loaded > 0 {
                    durationUpdated(loaded)
                    return
                }
                guard let delay = SessionRestorePolicy.delayMilliseconds(forAttempt: attempt) else {
                    // Attempts exhausted, but keep the session
                    durationUpdated(loaded)
                    return
                }
                try await Task.sleep(for: .milliseconds(delay))
                attempt += 1
            } catch let error as NSError
                where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                trackLoadFailed()
                return
            } catch {
                // Retry if attempts remain, else keep the session for a manual retry
                guard let delay = SessionRestorePolicy.delayMilliseconds(forAttempt: attempt) else {
                    return
                }
                try? await Task.sleep(for: .milliseconds(delay))
                attempt += 1
            }
        }
    }

    /// Stops playback when the playing track is one of `urls`, or lives inside a folder in it.
    ///
    /// `AppFeature` used to run this check itself, reading `state.player.currentTrack`. The track
    /// lives here now, so the check comes with it — the caller sends only what is being removed.
    /// The items still travel in the message rather than being read back from the file browser,
    /// because `CollectionsFeature` clears its selection before the removal completes (#22).
    func clearSessionIfAffected(by urls: [URL]) {
        guard
            let currentTrack,
            PathMatching.isAffected(trackURL: currentTrack.url, byAnyOf: urls)
        else { return }
        clearSession()
    }

    /// Recording takes over the shared `AVAudioSession`, so playback stops before the sheet opens.
    func pauseIfPlaying() {
        guard isPlaying else { return }
        playPauseTapped()
    }

    func clearSession() {
        persist(PlaybackSession())
        resetPlaybackState()
        stopTimeObserver()
        Task { [audioPlayer] in await audioPlayer.stop() }
    }

    func suspendSession() {
        if let currentTrack {
            persist(SessionCodec.session(
                trackURL: currentTrack.url,
                currentTime: currentTime,
                queueURLs: queue.map(\.url),
                playlistSource: currentPlaylistSource
            ))
        }
        resetPlaybackState()
        stopTimeObserver()
        Task { [audioPlayer] in await audioPlayer.stop() }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .active, isPlaying, currentTrack != nil {
            let rate = playbackSpeed.rawValue
            Task { [audioPlayer] in await audioPlayer.setRate(rate) }
            return
        }
        guard phase != .active else { return }

        guard let currentTrack else {
            persist(PlaybackSession())
            return
        }

        if SessionCodec.isFinishedAtEndOfQueue(
            currentIndex: currentIndex,
            queueCount: queue.count,
            currentTime: currentTime,
            duration: duration
        ) {
            persist(PlaybackSession())
        } else {
            persist(SessionCodec.session(
                trackURL: currentTrack.url,
                currentTime: currentTime,
                queueURLs: queue.map(\.url),
                playlistSource: currentPlaylistSource
            ))
        }
    }

    private func persist(_ newSession: PlaybackSession) {
        session = newSession
        sessionStore.save(newSession)
    }

    private func resetPlaybackState() {
        currentTrack = nil
        artwork = nil
        colors = []
        queue = []
        currentIndex = 0
        currentPlaylistSource = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        isLoadingTrack = false
        isExpanded = false // dismisses PlayerView
    }

    // MARK: -

    private static func formatTime(_ time: TimeInterval) -> String? {
        guard time.isFinite, !time.isNaN else { return nil }
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
