import Foundation
import Observation

/// Holds the dial's navigator and connects it to the rest of the app (#6).
///
/// **It is deliberately thin.** `DialNavigator` decides everything — what a press means, where the
/// highlight goes, which feedback fires — and this type does the two things a pure struct cannot:
/// it keeps the navigator's content fed with the app's real data, and it turns `DialEffect`s into
/// calls on the things that own the hardware.
///
/// Out-edges are closures wired in `AppViewModel.wire()`, like every other cross-feature edge here,
/// which is what makes them reachable from a test with no view rendered.
@MainActor
@Observable
final class DialViewModel {

    /// What the view renders. Recomputed from the navigator, which is the single source of truth.
    var screen: DialScreen { navigator.screen }

    var onPlay: ((String) -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?
    var onSelectTrack: ((Int) -> Void)?
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?

    private var navigator: DialNavigator
    private let haptics: HapticsClient
    /// The live waveform's bar history. See `refresh`.
    private var levels: [Double] = []
    /// Input gain, `0...1`. Held here because nothing else in the app has a notion of it yet —
    /// `setGain` is inert until the recorder gains one.
    private var gain: Double = 0.7

    init(haptics: HapticsClient = .live) {
        self.navigator = DialNavigator()
        self.haptics = haptics
        haptics.prepare()
    }

    /// The single entry point. Every turn, press and chip tap arrives here.
    func receive(_ command: DialCommand) {
        for effect in navigator.receive(command) {
            apply(effect)
        }
    }

    /// Re-feeds the navigator from the app's current state.
    ///
    /// Called whenever the underlying data moves. The navigator re-clamps every level's highlight
    /// against the new content, so a list shrinking under a screen you are not looking at cannot
    /// leave a highlight pointing past the end.
    func refresh(recentFiles: [AudioFile], player: PlayerViewModel, recorder: RecordingViewModel) {
        var content = DialContent()

        content.sections = [
            DialContent.Section(
                id: "recordings",
                icon: .recording,
                title: String(localized: "Recordings"),
                count: recentFiles.count,
                destination: .recordings
            ),
            DialContent.Section(
                id: "nowPlaying",
                icon: .session,
                title: String(localized: "Now Playing"),
                count: nil,
                destination: .nowPlaying
            ),
            // Without this the recording screen is unreachable. `startRecording()` pushes it, but
            // nothing reached `startRecording()`: the Record chip only appears when the recordings
            // list is *empty*, and the mode chooser is not the root. Opening the route directly
            // lands on its "Not recording — press the hub to start" state, which is the honest
            // resting state of that screen rather than a placeholder.
            DialContent.Section(
                id: "record",
                icon: .add,
                title: String(localized: "Record"),
                count: nil,
                destination: .recording
            )
        ]

        content.recordings = recentFiles.map { file in
            DialContent.Item(
                id: file.url.absoluteString,
                title: file.title,
                duration: file.duration,
                subtitle: nil
            )
        }

        if let track = player.currentTrack {
            content.playback = DialContent.Playback(
                title: track.title,
                subtitle: nil,
                position: player.currentTime,
                duration: player.duration,
                isPlaying: player.isPlaying,
                queueIndex: player.currentIndex,
                queueCount: max(1, player.queue.count)
            )
        }

        // The live capture, which is what turns the ring into a level meter. `peakLevel` is a
        // single instantaneous value, so the bar history is kept here — the navigator holds a
        // snapshot and has nowhere to accumulate one.
        if recorder.isRecording {
            levels.append(Double(max(0, min(1, recorder.peakLevel))))
            if levels.count > Self.levelHistory { levels.removeFirst(levels.count - Self.levelHistory) }
            content.capture = DialContent.Capture(
                elapsed: recorder.recordingTime,
                levels: levels,
                gain: gain,
                markers: [],
                isPaused: false
            )
        } else {
            levels.removeAll()
        }

        navigator.update(content)
    }

    /// How many bars the live waveform keeps. Enough to read as movement, few enough that each one
    /// is still wide enough to see.
    private static let levelHistory = 40

    private func apply(_ effect: DialEffect) {
        switch effect {
        case .feedback(let event):
            haptics.fire(DetentFeedback.pulse(for: event))
        case .play(let itemID):
            onPlay?(itemID)
        case .togglePlayPause:
            onTogglePlayPause?()
        case .seek(let time):
            onSeek?(time)
        case .selectTrack(let index):
            onSelectTrack?(index)
        case .startRecording:
            levels.removeAll()
            onStartRecording?()
        case .stopRecording:
            onStopRecording?()
        case .setGain(let value):
            // Held locally: the recorder has no gain control yet, so this moves the meter's
            // reference without pretending to change the hardware.
            gain = min(max(0, value), 1)

        // Recording and trimming are slices of their own. Their effects are deliberately inert
        // rather than faked — a control that appears to work and does not is worse than one that
        // visibly does nothing yet.
        default:
            break
        }
    }
}
