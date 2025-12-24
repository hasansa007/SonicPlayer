import ComposableArchitecture
import Foundation
import Sharing
import SwiftUI
import UIKit

struct QueueItem: Codable, Equatable {
    var fileURL: String
}

struct PlaybackSession: Codable, Equatable {
    var fileURL: String
    var currentTime: TimeInterval
    var queue: [QueueItem]
    var playlistSource: PlaylistSource?

    init(fileURL: String = "", currentTime: TimeInterval = 0, queue: [QueueItem] = [], playlistSource: PlaylistSource? = nil) {
        self.fileURL = fileURL
        self.currentTime = currentTime
        self.queue = queue
        self.playlistSource = playlistSource
    }

    var isEmpty: Bool {
        fileURL.isEmpty
    }
}

enum PlaylistSource: Equatable, Codable {
    case folder(URL)
    case singleFile
}

@Reducer
struct PlayerFeature {
    @ObservableState
    struct State: Identifiable, Equatable {
        var id: String? { currentTrack?.url.absoluteString ?? UUID().uuidString } // Use currentTrack's URL for ID, if any.
        // Session storage in temp directory
        static var sessionURL: URL {
            let tempDir = FileManager.default.temporaryDirectory
            let sonicDir = tempDir.appendingPathComponent("SonicPlayer", isDirectory: true)
            try? FileManager.default.createDirectory(at: sonicDir, withIntermediateDirectories: true)
            return sonicDir.appendingPathComponent("session.json")
        }

        @Shared(.fileStorage(State.sessionURL))
        var session = PlaybackSession()

        var playbackSpeed: PlaybackSpeed
        var skipDuration: SkipDuration

        // Runtime state (not persisted)
        var currentTrack: AudioFile?
        var artwork: UIImage?
        var colors: [Color] = []
        
        var queue: [AudioFile] = []
        var currentIndex: Int = 0
        var currentPlaylistSource: PlaylistSource?

        var isPlaying = false
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var isLoadingTrack = false
        var isExpanded: Bool = false

        var progress: Double {
            guard duration > 0 else { return 0 }
            return currentTime / duration
        }

        var currentTimeFormatted: String? {
            formatTime(currentTime)
        }

        var durationFormatted: String? {
            formatTime(duration)
        }

        var hasNextTrack: Bool {
            !queue.isEmpty && currentIndex < queue.count - 1
        }

        var hasPreviousTrack: Bool {
            !queue.isEmpty && currentIndex > 0
        }

        var shouldShowMiniPlayer: Bool {
            currentTrack != nil && !isExpanded && duration > 0
        }

        init() {
            // Load persisted settings
            self.playbackSpeed = UserDefaults.standard.savedPlaybackSpeed
            self.skipDuration = UserDefaults.standard.savedSkipDuration
            // Will restore from session on .restoreSession action
            self.isExpanded = false
        }

        private func formatTime(_ time: TimeInterval) -> String? {
            guard time.isFinite, !time.isNaN else { return nil }
            let hours = Int(time) / 3600
            let minutes = Int(time) / 60 % 60
            let seconds = Int(time) % 60

            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                return String(format: "%d:%02d", minutes, seconds)
            }
        }
        
        static func == (lhs: State, rhs: State) -> Bool {
            lhs.id == rhs.id &&
            lhs.session == rhs.session &&
            lhs.playbackSpeed == rhs.playbackSpeed &&
            lhs.skipDuration == rhs.skipDuration &&
            lhs.currentTrack == rhs.currentTrack &&
            lhs.colors == rhs.colors &&
            lhs.queue == rhs.queue &&
            lhs.currentIndex == rhs.currentIndex &&
            lhs.currentPlaylistSource == rhs.currentPlaylistSource &&
            lhs.isPlaying == rhs.isPlaying &&
            lhs.currentTime == rhs.currentTime &&
            lhs.duration == rhs.duration &&
            lhs.isLoadingTrack == rhs.isLoadingTrack &&
            lhs.isExpanded == rhs.isExpanded
            // Exclude artwork from comparison
        }
    }

    enum Action {
        case playPauseButtonTapped
        case loadTrack(AudioFile, [AudioFile]?, PlaylistSource?)
        case trackLoaded
        case trackLoadFailed
        case seekToPosition(TimeInterval)
        case skipForward
        case skipBackward
        case nextTrack
        case previousTrack
        case jumpToTrack(Int) // Jump to specific index in queue
        case setPlaybackSpeed(PlaybackSpeed)
        case setSkipDuration(SkipDuration)
        case timeUpdate(TimeInterval)
        case durationUpdated(TimeInterval)
        case startTimeObserver
        case stopTimeObserver
        case toggleExpansion
        case setExpanded(Bool)
        case scenePhaseChanged // Action to handle scene changes for persistence
        case restoreSession
        case sessionLoaded(AudioFile, [AudioFile], Int) // currentTrack, queue, currentIndex
        case retryRestoreSession(AudioFile, TimeInterval, Float, Int) // track, time, rate, attemptNumber
        case sessionRestored
        case clearSession
        case suspendSession
        
        case loadArtwork
        case artworkLoaded(UIImage?, [Color])
    }

    @Dependency(\.audioPlayer) var audioPlayer
    @Dependency(\.continuousClock) var clock
    @Dependency(\.fileManager) var fileManager
    @Dependency(\.artworkClient) var artworkClient

    private enum CancelID { case timeObserver }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .restoreSession:
                return Effect.run { [state] send in
                    let sessionFileURL = state.session.fileURL
                    let sessionTime = state.session.currentTime
                    let queueURLs = state.session.queue.map { $0.fileURL }

                    let currentURL = URL(fileURLWithPath: sessionFileURL)
                    guard FileManager.default.fileExists(atPath: currentURL.path) else {
                        // File deleted - clear session
                        await send(.clearSession)
                        return
                    }

                    // 2. Load AudioFile metadata for current track
                    guard let currentFile = try? await fileManager.getMetadata(currentURL) else {
                        await send(.clearSession)
                        return
                    }

                    // 3. Load all queue files (filter out deleted ones)
                    var queueFiles: [AudioFile] = []
                    for urlString in queueURLs {
                        let url = URL(fileURLWithPath: urlString)
                        if FileManager.default.fileExists(atPath: url.path),
                           let file = try? await fileManager.getMetadata(url) {
                            queueFiles.append(file)
                        }
                    }

                    // 4. Find current index in queue
                    let currentIndex = queueFiles.firstIndex(of: currentFile) ?? 0

                    // 5. Update state with loaded data
                    await send(.sessionLoaded(currentFile, queueFiles, currentIndex))

                    // 6. Start restore attempt with saved playback speed
                    await send(.retryRestoreSession(currentFile, sessionTime, state.playbackSpeed.rawValue, 0))
                }

            case let .sessionLoaded(track, queue, index):
                state.currentTrack = track
                state.queue = queue
                state.currentIndex = index
                state.currentPlaylistSource = state.session.playlistSource
                state.isPlaying = false
                return .send(.loadArtwork)

            case let .retryRestoreSession(track, time, rate, attemptNumber):
                return Effect.run { send in
                    let maxRetries = 3
                    do {
                        try await audioPlayer.prepare(track.url)
                        await audioPlayer.setRate(rate)
                        await audioPlayer.seek(time)
                        await audioPlayer.pause()

                        // Check if duration is valid
                        let duration = await audioPlayer.duration()

                        if duration > 0 {
                            // Success!
                            await send(.durationUpdated(duration))
                            await send(.sessionRestored)
                        } else if attemptNumber < maxRetries {
                            // Duration not ready, retry after delay
                            let delayMs = 500 * (1 << attemptNumber) // 500ms, 1s, 2s
                            try await clock.sleep(for: .milliseconds(delayMs))
                            await send(.retryRestoreSession(track, time, rate, attemptNumber + 1))
                        } else {
                            // Max retries reached, but keep session
                            await send(.durationUpdated(duration))
                        }
                    } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                        // File doesn't exist, clear session
                        await send(.trackLoadFailed)
                    } catch {
                        // Other error - retry if attempts remain
                        if attemptNumber < maxRetries {
                            let delayMs = 500 * (1 << attemptNumber)
                            try? await clock.sleep(for: .milliseconds(delayMs))
                            await send(.retryRestoreSession(track, time, rate, attemptNumber + 1))
                        }
                        // Otherwise keep session for manual retry
                    }
                }

            case .sessionRestored:
                // Session successfully restored
                return .none

            case .clearSession:
                state.$session.withLock { session in
                    session = PlaybackSession()
                }
                state.currentTrack = nil
                state.artwork = nil
                state.colors = []
                state.queue = []
                state.currentIndex = 0
                state.currentPlaylistSource = nil
                state.isPlaying = false
                state.currentTime = 0
                state.duration = 0
                state.isLoadingTrack = false
                state.isExpanded = false // Dismiss PlayerView
                return .merge(
                    .cancel(id: CancelID.timeObserver),
                    .run { _ in
                        await audioPlayer.stop()
                    }
                )

            case .suspendSession:
                if let currentTrack = state.currentTrack {
                    let queueItems = state.queue.map { QueueItem(fileURL: $0.url.path) }
                    state.$session.withLock { session in
                        session = PlaybackSession(
                            fileURL: currentTrack.url.path,
                            currentTime: state.currentTime,
                            queue: queueItems,
                            playlistSource: state.currentPlaylistSource
                        )
                    }
                }

                state.currentTrack = nil
                state.artwork = nil
                state.colors = []
                state.queue = []
                state.currentIndex = 0
                state.currentPlaylistSource = nil
                state.isPlaying = false
                state.currentTime = 0
                state.duration = 0
                state.isLoadingTrack = false
                state.isExpanded = false
                return .merge(
                    .cancel(id: CancelID.timeObserver),
                    .run { _ in
                        await audioPlayer.stop()
                    }
                )

            case .playPauseButtonTapped:
                if state.isPlaying {
                    state.isPlaying = false
                    return Effect.merge(
                        Effect.run { send in await audioPlayer.pause() },
                        Effect.cancel(id: CancelID.timeObserver)
                    )
                } else {
                    if state.currentTrack != nil {
                        state.isPlaying = true

                        return Effect.merge(
                            Effect.run { send in await audioPlayer.resume() },
                            Effect.send(.startTimeObserver)
                        )
                    }
                    return .none
                }

            case let .loadTrack(track, queue, playlistSource):
                state.isLoadingTrack = true
                state.isPlaying = false

                // Update runtime state
                state.currentTrack = track
                if let newQueue = queue {
                    state.queue = newQueue
                    state.currentIndex = newQueue.firstIndex(of: track) ?? 0
                    // When loading a new queue, always update the playlist source
                    state.currentPlaylistSource = playlistSource
                } else {
                    // When navigating within existing queue, only update if provided
                    if let newPlaylistSource = playlistSource {
                        state.currentPlaylistSource = newPlaylistSource
                    }
                }
                state.currentTime = 0
                state.isExpanded = true

                return Effect.merge(
                    Effect.cancel(id: CancelID.timeObserver),
                    Effect.run { send in
                        do {
                            try await audioPlayer.play(track.url)
                            await send(.trackLoaded)
                        } catch {
                            await send(.trackLoadFailed)
                        }
                    },
                    Effect.send(.loadArtwork)
                )

            case .trackLoaded:
                state.isLoadingTrack = false
                state.isPlaying = true
                let rate = state.playbackSpeed.rawValue

                return Effect.run { [state] send in
                    // Set up remote command handlers for next/previous track
                    audioPlayer.setRemoteHandlers(
                        { Task { @MainActor in send(.nextTrack) } },
                        { Task { @MainActor in send(.previousTrack) } }
                    )

                    await audioPlayer.setRate(rate)
                    if state.currentTime > 0 { await audioPlayer.seek(state.currentTime) } // Seek to restored time if applicable
                    let duration = await audioPlayer.duration()
                    await send(.durationUpdated(duration))
                    await send(.startTimeObserver)
                }

            case .trackLoadFailed:
                state.isLoadingTrack = false
                state.isPlaying = false
                return .none

            case let .seekToPosition(time):
                state.currentTime = time
                return Effect.run { send in await audioPlayer.seek(time) }

            case .skipForward:
                let interval = state.skipDuration.rawValue
                return Effect.run { send in await audioPlayer.skipForward(interval) }

            case .skipBackward:
                let interval = state.skipDuration.rawValue
                return Effect.run { send in await audioPlayer.skipBackward(interval) }
                
            case .nextTrack:
                guard state.hasNextTrack else { return .none }
                state.currentIndex += 1
                let next = state.queue[state.currentIndex]
                return Effect.send(.loadTrack(next, nil, nil))

            case .previousTrack:
                if state.currentTime > 3 {
                    return Effect.send(.seekToPosition(0))
                }
                guard state.hasPreviousTrack else { return .send(.seekToPosition(0)) }
                state.currentIndex -= 1
                let prev = state.queue[state.currentIndex]
                                    return Effect.send(.loadTrack(prev, nil, nil))
            case let .jumpToTrack(index):
                guard index >= 0 && index < state.queue.count else { return .none }
                state.currentIndex = index
                let track = state.queue[index]
                return Effect.send(.loadTrack(track, nil, nil))

            case let .setPlaybackSpeed(speed):
                state.playbackSpeed = speed
                UserDefaults.standard.savedPlaybackSpeed = speed
                let rate = speed.rawValue
                return Effect.run { send in await audioPlayer.setRate(rate) }

            case let .setSkipDuration(duration):
                state.skipDuration = duration
                UserDefaults.standard.savedSkipDuration = duration
                return .none

            case let .timeUpdate(time):
                state.currentTime = time

                // Check if track finished
                if state.isPlaying && state.duration > 0 && (state.duration - time) < 1.0 {
                    if state.hasNextTrack {
                        return .send(.nextTrack)
                    } else {
                        // End of queue - dismiss player
                        return .send(.clearSession)
                    }
                }

                // Update Now Playing info periodically (every ~3 seconds based on 0.5s interval)
                let shouldUpdateNowPlaying = Int(time) % 3 == 0

                // Only fetch duration if we don't have it yet
                if state.duration == 0 {
                    return Effect.run { send in
                        let duration = await audioPlayer.duration()
                        if duration > 0 {
                            await send(.durationUpdated(duration))
                        }
                    }
                } else if shouldUpdateNowPlaying {
                    // Update Now Playing info to keep lock screen in sync
                    return Effect.run { send in
                        await audioPlayer.updateNowPlaying()
                    }
                }
                return .none

            case let .durationUpdated(duration):
                state.duration = duration
                // Update Now Playing info with the correct duration"Move To" only under /SonicPlayer path 
                return Effect.run { send in
                    await audioPlayer.updateNowPlaying()
                }

            case .startTimeObserver:
                return Effect.run { send in
                    for await time in await audioPlayer.timeUpdates() {
                        await send(.timeUpdate(time))
                    }
                }
                .cancellable(id: CancelID.timeObserver)

            case .stopTimeObserver:
                return Effect.cancel(id: CancelID.timeObserver)

            case .toggleExpansion:
                state.isExpanded.toggle()
                return .none

            case let .setExpanded(expanded):
                state.isExpanded = expanded
                return .none
                
            case .scenePhaseChanged:
                // Save session when app backgrounds
                guard let currentTrack = state.currentTrack else {
                    state.$session.withLock { session in
                        session = PlaybackSession()
                    }
                    return .none
                }

                // Check if last track finished
                let isLastTrack = state.currentIndex == state.queue.count - 1
                let hasFinished = abs(state.currentTime - state.duration) < 1.0 && state.duration > 0

                if isLastTrack && hasFinished {
                    // Clear session when last track completes
                    state.$session.withLock { session in
                        session = PlaybackSession()
                    }
                } else {
                    // Save current state
                    let queueItems = state.queue.map { QueueItem(fileURL: $0.url.path) }
                    state.$session.withLock { session in
                        session = PlaybackSession(
                            fileURL: currentTrack.url.path,
                            currentTime: state.currentTime,
                            queue: queueItems,
                            playlistSource: state.currentPlaylistSource
                        )
                    }
                }
                return .none
                
            case .loadArtwork:
                guard let track = state.currentTrack else {
                    state.artwork = nil
                    state.colors = []
                    return .none
                }
                return .run { send in
                    async let artwork = artworkClient.getArtwork(track.url)
                    async let colors = artworkClient.getColors(track.url, false, Color.sonicTealColors)
                    await send(.artworkLoaded(await artwork, await colors))
                }
                
            case let .artworkLoaded(artwork, colors):
                state.artwork = artwork
                state.colors = colors
                return .none
            }
        }
    }
}
