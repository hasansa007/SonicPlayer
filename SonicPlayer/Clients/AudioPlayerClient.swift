import AVFoundation
import ComposableArchitecture
import Foundation
import MediaPlayer

@DependencyClient
struct AudioPlayerClient {
    var prepare: @Sendable (URL) async throws -> Void
    var play: @Sendable (URL) async throws -> Void
    var pause: @Sendable () async -> Void
    var resume: @Sendable () async -> Void
    var stop: @Sendable () async -> Void
    var seek: @Sendable (TimeInterval) async -> Void
    var setRate: @Sendable (Float) async -> Void
    var skipForward: @Sendable (TimeInterval) async -> Void
    var skipBackward: @Sendable (TimeInterval) async -> Void
    var updateNowPlaying: @Sendable () async -> Void
    var setRemoteHandlers: @Sendable (@escaping () -> Void, @escaping () -> Void) -> Void = { _, _ in }
    var currentTime: @Sendable () async -> TimeInterval = { 0 }
    var duration: @Sendable () async -> TimeInterval = { 0 }
    var isPlaying: @Sendable () async -> Bool = { false }
    var timeUpdates: @Sendable () async -> AsyncStream<TimeInterval> = { .finished }
}

extension DependencyValues {
    var audioPlayer: AudioPlayerClient {
        get { self[AudioPlayerClient.self] }
        set { self[AudioPlayerClient.self] = newValue }
    }
}

extension AudioPlayerClient: DependencyKey {
    static func makeLive() -> AudioPlayerClient {
        let player = AudioPlayerManager()
        return Self(
            prepare: { url in
                try await player.prepare(url: url)
            },
            play: { url in
                try await player.play(url: url)
            },
            pause: {
                await player.pause()
            },
            resume: {
                await player.resume()
            },
            stop: {
                await player.stop()
            },
            seek: { time in
                await player.seek(to: time)
            },
            setRate: { rate in
                await player.setRate(rate)
            },
            skipForward: { interval in
                await player.skip(by: interval)
            },
            skipBackward: { interval in
                await player.skip(by: -interval)
            },
            updateNowPlaying: {
                await player.updateNowPlaying()
            },
            setRemoteHandlers: { nextTrackHandler, previousTrackHandler in
                Task { @MainActor in
                    player.setRemoteHandlers(nextTrack: nextTrackHandler, previousTrack: previousTrackHandler)
                }
            },
            currentTime: {
                await player.currentTime
            },
            duration: {
                await player.duration
            },
            isPlaying: {
                await player.isPlaying
            },
            timeUpdates: {
                await player.timeUpdates()
            }
        )
    }

    static let liveValue: AudioPlayerClient = makeLive()

    static let testValue = Self()
}

// ...

private final class AudioPlayerManager: NSObject, ObservableObject {
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var continuation: AsyncStream<TimeInterval>.Continuation?
    private var nextTrackHandler: (() -> Void)?
    private var previousTrackHandler: (() -> Void)?

    @MainActor
    var currentTime: TimeInterval {
        player?.currentTime().seconds ?? 0
    }

    @MainActor
    var duration: TimeInterval {
        get async {
            guard let item = player?.currentItem else { return 0 }
            
            // Try player item duration first
            let itemDuration = item.duration
            if itemDuration.isValid && itemDuration.isNumeric && !itemDuration.isIndefinite {
                return itemDuration.seconds
            }
            
            // Fallback to asset duration
            if let asset = item.asset as? AVURLAsset {
                let assetDuration = try? await asset.load(.duration)
                if let assetDuration, assetDuration.isValid && assetDuration.isNumeric && !assetDuration.isIndefinite {
                    return assetDuration.seconds
                }
            }
            
            return 0
        }
    }

    @MainActor
    var isPlaying: Bool {
        player?.timeControlStatus == .playing
    }

    @MainActor
    func prepare(url: URL) async throws {
        // Setup audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio)
        // Activate off the main thread: setActive(_:) is a synchronous call
        // that AVAudioSession warns can block the main thread.
        try await Task.detached {
            try AVAudioSession.sharedInstance().setActive(true)
        }.value

        // Create player
        let playerItem = AVPlayerItem(url: url)
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }

        // Wait for the player item to be ready
        guard let currentItem = player?.currentItem else { return }

        // Wait for status to be ready and duration to be valid
        var attempts = 0
        let maxAttempts = 100 // 5 seconds maximum wait

        while attempts < maxAttempts {
            if currentItem.status == .failed {
                throw currentItem.error ?? NSError(domain: "AudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load audio"])
            }

            // Check if both status is ready and duration is valid
            if currentItem.status == .readyToPlay &&
               currentItem.duration.isNumeric &&
               !currentItem.duration.isIndefinite {
                break
            }

            try await Task.sleep(for: .milliseconds(50))
            attempts += 1
        }

        // Setup Now Playing
        await setupNowPlaying(for: url)

        // Setup remote commands
        setupRemoteCommands()
    }

    @MainActor
    func play(url: URL) async throws {
        try await prepare(url: url)
        player?.play()
    }

    @MainActor
    func pause() {
        player?.pause()
    }

    @MainActor
    func resume() {
        player?.play()
    }

    @MainActor
    func stop() {
        player?.pause()
        player = nil
        removeTimeObserver()
    }

    @MainActor
    func seek(to time: TimeInterval) async {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        await player?.seek(to: cmTime)
    }

    @MainActor
    func setRate(_ rate: Float) {
        player?.rate = rate
    }

    @MainActor
    func skip(by interval: TimeInterval) async {
        let newTime = currentTime + interval
        await seek(to: max(0, min(newTime, duration)))
    }

    @MainActor
    func timeUpdates() -> AsyncStream<TimeInterval> {
        AsyncStream { continuation in
            self.continuation = continuation

            let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
            timeObserver = player?.addPeriodicTimeObserver(
                forInterval: interval,
                queue: .main
            ) { time in
                continuation.yield(time.seconds)
            }

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.removeTimeObserver()
                }
            }
        }
    }

    @MainActor
    private func removeTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        continuation?.finish()
        continuation = nil
    }

    @MainActor
    func updateNowPlaying() async {
        guard let url = player?.currentItem?.asset as? AVURLAsset else { return }

        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()

        nowPlayingInfo[MPMediaItemPropertyTitle] = url.url.deletingPathExtension().lastPathComponent
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = await duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player?.rate ?? 1.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    @MainActor
    private func setupNowPlaying(for url: URL) async {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = url.deletingPathExtension().lastPathComponent
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = await duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player?.rate ?? 1.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    @MainActor
    func setRemoteHandlers(nextTrack: @escaping () -> Void, previousTrack: @escaping () -> Void) {
        self.nextTrackHandler = nextTrack
        self.previousTrackHandler = previousTrack
    }

    @MainActor
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resume()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pause()
            }
            return .success
        }

        // Next track command
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextTrackHandler?()
            return .success
        }

        // Previous track command
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previousTrackHandler?()
            return .success
        }

        // Skip forward/backward commands
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            if let skipEvent = event as? MPSkipIntervalCommandEvent {
                Task { @MainActor [weak self] in
                    await self?.skip(by: skipEvent.interval)
                }
            }
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            if let skipEvent = event as? MPSkipIntervalCommandEvent {
                Task { @MainActor [weak self] in
                    await self?.skip(by: -skipEvent.interval)
                }
            }
            return .success
        }
    }
}
