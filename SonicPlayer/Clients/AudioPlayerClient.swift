import AVFoundation
import Foundation
import MediaPlayer
import UIKit

struct AudioPlayerClient: Sendable {
    var prepare: @Sendable (URL) async throws -> Void
    var play: @Sendable (URL) async throws -> Void
    var pause: @Sendable () async -> Void
    var resume: @Sendable () async -> Void
    var stop: @Sendable () async -> Void
    var seek: @Sendable (TimeInterval) async -> Void
    var setRate: @Sendable (Float) async -> Void
    /// **This player's output level, not the device's.**
    ///
    /// The dial's volume axis had nowhere to land before this: the effect was emitted, clamped and
    /// then dropped, under a note saying volume belongs to `MPVolumeView`, which owns the system
    /// slider and offers no setter worth having. That was right about the *system* volume and wrong
    /// as a conclusion — `AVPlayer.volume` is per-player gain, so turning the wheel changes how loud
    /// this app is without touching the hardware buttons or the slider they drive.
    ///
    /// Defaulted, so every `.test` client and every existing initialiser keeps compiling.
    var setVolume: @Sendable (Float) async -> Void = { _ in }

    /// **Writes the device's level.** Paired with `systemVolumeUpdates`, this is what makes the
    /// dial's volume the phone's volume rather than a second one beside it.
    ///
    /// See `SystemVolumeControl` for the cost, which is real and was accepted deliberately.
    var setSystemVolume: @Sendable (Float) async -> Void = { _ in }

    /// The device's level as it changes — seeded immediately, then every hardware button press,
    /// Control Centre drag and route change.
    var systemVolumeUpdates: @Sendable () async -> AsyncStream<Float> = { AsyncStream { $0.finish() } }

    /// **The device's level, read-only.** `AVAudioSession.outputVolume` is the one half of system
    /// volume an app may have without cost: reading it and observing it are free, and only
    /// *writing* it needs the `MPVolumeView` that suppresses the hardware HUD.
    ///
    /// Used to seed this app's gain at launch, so the dial opens at the level the phone is actually
    /// at rather than at full — see `PlayerViewModel.setVolume`. Defaulted to 1 so `.test` clients
    /// and every existing initialiser keep compiling, and so a stub is the old behaviour exactly.
    var systemVolume: @Sendable () async -> Float = { 1 }
    var skipForward: @Sendable (TimeInterval) async -> Void
    var skipBackward: @Sendable (TimeInterval) async -> Void
    var updateNowPlaying: @Sendable () async -> Void
    var setRemoteHandlers: @Sendable (@escaping () -> Void, @escaping () -> Void) -> Void = { _, _ in }
    var currentTime: @Sendable () async -> TimeInterval = { 0 }
    var duration: @Sendable () async -> TimeInterval = { 0 }
    var isPlaying: @Sendable () async -> Bool = { false }
    var timeUpdates: @Sendable () async -> AsyncStream<TimeInterval> = { AsyncStream { $0.finish() } }
}


extension AudioPlayerClient {
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
            setVolume: { volume in
                await player.setVolume(volume)
            },
            setSystemVolume: { level in
                await SystemVolumeControl.shared.set(level)
            },
            systemVolumeUpdates: {
                AsyncStream { continuation in
                    let session = AVAudioSession.sharedInstance()
                    try? session.setActive(true)
                    continuation.yield(session.outputVolume)

                    // KVO rather than a notification: `outputVolume` is the documented observable,
                    // and it fires for the hardware buttons, Control Centre and a route change to
                    // headphones alike — all three are "the device's level moved under us".
                    let observation = session.observe(\.outputVolume, options: [.new]) { _, change in
                        guard let level = change.newValue else { return }
                        continuation.yield(level)
                    }
                    continuation.onTermination = { _ in observation.invalidate() }
                }
            },
            systemVolume: {
                // Activating first: before the session is active the value is documented as
                // unreliable, and at cold launch this is read early enough to matter.
                try? AVAudioSession.sharedInstance().setActive(true)
                return AVAudioSession.sharedInstance().outputVolume
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

    static let live: AudioPlayerClient = makeLive()

}

// ...

private final class AudioPlayerManager: NSObject, ObservableObject {
    private var player: AVPlayer?
    /// Survives the player it applies to — see `setVolume(_:)`.
    private var volume: Float = 1
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
        // Configure and activate off the main thread: setCategory(_:mode:) and
        // setActive(_:) are synchronous calls that AVAudioSession warns can block
        // the main thread while the session is active.
        try await Task.detached {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio)
            try audioSession.setActive(true)
        }.value

        // Create player
        let playerItem = AVPlayerItem(url: url)
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        // A new `AVPlayer` starts at full volume, so the level the user chose has to be reapplied
        // here or the next track is abruptly loud.
        player?.volume = volume

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

    /// Held as well as applied, because `player` is replaced on every track change and a fresh
    /// `AVPlayer` starts at 1. Without the stored copy, volume would silently reset to full the
    /// moment you moved to the next track — which is worse than not having the control.
    @MainActor
    func setVolume(_ volume: Float) {
        self.volume = min(max(0, volume), 1)
        player?.volume = self.volume
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


/// **The one way an app can set the system volume, and what it costs.**
///
/// There is no public setter for `AVAudioSession.outputVolume`. The only route is the `UISlider`
/// that `MPVolumeView` embeds: put the view in the window, move its slider, and the device level
/// moves with it.
///
/// **The cost is the hardware HUD.** An `MPVolumeView` in the window is precisely how an app
/// *suppresses* the system volume overlay — so pressing the buttons stops drawing anything. That is
/// not a bug to be worked around and there is no API to summon the overlay back; an app may only
/// suppress it.
///
/// **It is accepted here on purpose**, and the dial's own volume arc is what was built to replace
/// it: the ring reports the level while it changes and fades out after `volumeLinger`. This was
/// tried, reverted for exactly this reason while the app had no indicator of its own, and taken
/// back up once it did. If the arc is ever removed, this has to go with it.
///
/// Off-screen at 1×1 rather than hidden: `isHidden` stops the embedded slider responding at all on
/// some iOS versions, and a zero-size frame has the same problem. One point, parked outside the
/// bounds, is the shape that works.
@MainActor
final class SystemVolumeControl {

    static let shared = SystemVolumeControl()

    private let host = MPVolumeView(frame: CGRect(x: -offscreen, y: -offscreen, width: 1, height: 1))
    private var isAttached = false

    private var slider: UISlider? {
        host.subviews.compactMap { $0 as? UISlider }.first
    }

    func set(_ level: Float) {
        attachIfNeeded()
        guard let slider else { return }
        slider.setValue(min(max(0, level), 1), animated: false)
        // **The value alone does nothing.** `MPVolumeView`'s slider only pushes the level through
        // when it thinks a finger let go of it, so the action has to be sent by hand.
        slider.sendActions(for: .touchUpInside)
    }

    /// Attached lazily, so a launch that never touches volume never adds the view — and therefore
    /// never suppresses the HUD before the user has asked for anything.
    private func attachIfNeeded() {
        guard !isAttached else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard let window else { return }
        window.addSubview(host)
        isAttached = true
    }

    private static let offscreen: CGFloat = 1000
}
