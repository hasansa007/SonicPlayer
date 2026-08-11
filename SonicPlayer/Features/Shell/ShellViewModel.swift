import Foundation
import Observation

/// Owns what currently has the wheel, and applies what the router decides (#6).
///
/// **It applies effects; it does not decide them.** Every "what should this do" question belongs to
/// `WheelRouter`, which is what keeps this type small while the epic adds focuses.
///
/// The outbound edges are closures rather than direct calls on `PlayerViewModel`, following
/// `CollectionsViewModel.onWillRemoveItems` — the shape that lets a test exercise an edge without
/// rendering a view. `AppViewModel.wire()` connects them.
@MainActor
@Observable
final class ShellViewModel {

    private(set) var focus: WheelFocus = .default

    /// What the transient pill is showing, or `nil` when nothing has claimed the wheel.
    private(set) var hud: HUD?

    struct HUD: Equatable {
        var label: String
        var value: String
    }

    var onSeek: ((TimeInterval) -> Void)?
    var onPlayPause: (() -> Void)?
    var onNextTrack: (() -> Void)?
    var onPreviousTrack: (() -> Void)?
    var onVolumeBy: ((Double) -> Void)?
    var onSpeedBy: ((Int) -> Void)?

    private let player: PlayerViewModel
    private let haptics: HapticsClient

    init(player: PlayerViewModel, haptics: HapticsClient = .live) {
        self.player = player
        self.haptics = haptics
        haptics.prepare()
    }

    /// The single entry point. Every turn, tap and VoiceOver adjustment arrives here.
    ///
    /// **A refused effect cancels the rest of the command.** The router emits the value change and
    /// its detent tick together, so without this a turn against the end of a track fires the limit
    /// thump *and* an ordinary tick — two pulses, which reads as a stutter rather than as a wall.
    func receive(_ command: WheelCommand) {
        for effect in WheelRouter.route(command, focus: focus) {
            guard apply(effect) else { return }
        }
    }

    /// A control claims the wheel. Touching a control takes it, and it returns to seeking when the
    /// pill fades — there is deliberately no mode that persists invisibly.
    func claim(_ axis: WheelFocus.Axis) {
        focus = .nowPlaying(axis)
        hud = hudContents(for: axis)
    }

    func release() {
        focus = .default
        hud = nil
    }

    /// Returns `false` when the effect was refused, which stops the rest of the command.
    private func apply(_ effect: ShellEffect) -> Bool {
        switch effect {
        case .seekBy(let delta):
            let target = ScrubClamp.position(player.currentTime + delta, duration: player.duration)
            guard target != player.currentTime else {
                // At a limit. Its own pulse rather than nothing, so turning against the end of a
                // track feels like a wall instead of a wheel that has stopped working.
                haptics.fire(DetentFeedback.pulse(for: .limit))
                return false
            }
            onSeek?(target)
            hud = HUD(label: String(localized: "Seek"), value: Self.formatted(target))

        case .volumeBy(let delta):
            onVolumeBy?(delta)

        case .speedBy(let steps):
            onSpeedBy?(steps)

        case .playPause:
            onPlayPause?()

        case .nextTrack:
            onNextTrack?()

        case .previousTrack:
            onPreviousTrack?()

        case .feedback(let event):
            haptics.fire(DetentFeedback.pulse(for: event))
        }
        return true
    }

    private func hudContents(for axis: WheelFocus.Axis) -> HUD {
        switch axis {
        case .seek:
            HUD(label: String(localized: "Seek"), value: Self.formatted(player.currentTime))
        case .volume:
            // The value is the system slider's, which `MPVolumeView` owns and does not publish.
            HUD(label: String(localized: "Volume"), value: "")
        case .speed:
            HUD(label: String(localized: "Speed"), value: player.playbackSpeed.displayText)
        }
    }

    private static func formatted(_ time: TimeInterval) -> String {
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
