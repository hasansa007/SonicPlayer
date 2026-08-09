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
    func refresh(recentFiles: [AudioFile], player: PlayerViewModel) {
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

        navigator.update(content)
    }

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
            onStartRecording?()
        case .stopRecording:
            onStopRecording?()

        // Recording and trimming are slices of their own. Their effects are deliberately inert
        // rather than faked — a control that appears to work and does not is worse than one that
        // visibly does nothing yet.
        default:
            break
        }
    }
}
