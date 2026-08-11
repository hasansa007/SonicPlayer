import Foundation
import Testing

@testable import SonicPlayer

/// The shell's cross-feature edges, exercised through the composition root — the shape `CLAUDE.md`
/// prescribes for anything wired in `AppViewModel.wire()`, and the reason that wiring lives in a
/// method rather than in a view's `.onAppear`.
@Suite(.serialized)
struct ShellWiringTests {

    @MainActor
    private func makeApp() -> AppViewModel {
        var haptics = HapticsClient.test
        haptics.fire = { _ in }
        // `setRate` is the only `AudioPlayerClient` closure these paths reach — changing the speed
        // pushes the new rate at the engine. Everything else stays unimplemented, which is what
        // makes an unexpected call show up as a failure rather than as silence.
        var audio = AudioPlayerClient.test
        audio.setRate = { _ in }
        return AppViewModel(
            player: PlayerViewModel(audioPlayer: audio),
            recording: RecordingViewModel(audioRecorder: .test, audioPlayer: .test, fileManager: .test),
            settings: SettingsViewModel(),
            filesRoot: CollectionsViewModel(currentDirectory: nil, fileManager: .test),
            onboarding: nil,
            fileManager: .test,
            haptics: haptics
        )
    }

    @MainActor
    @Test func turningTheWheelSeeksThePlayer() {
        let app = makeApp()
        var sought: TimeInterval?
        app.shell.onSeek = { sought = $0 }
        app.player.duration = 100
        app.player.currentTime = 10

        app.shell.receive(.tick(5))

        #expect(abs((sought ?? .nan) - 10.5) < 1e-9)
    }

    @MainActor
    @Test func theShellAndThePlayerAreTheSameEngine() {
        let app = makeApp()
        var toggled = false
        app.shell.onPlayPause = { toggled = true }

        app.shell.receive(.select)

        #expect(toggled)
    }

    /// Speed steps through the presets rather than by a raw amount, and stops at the ends.
    @MainActor
    @Test func speedStepsThroughThePresetsAndClampsAtTheTop() {
        let app = makeApp()
        app.player.setPlaybackSpeed(.double)

        app.shell.claim(.speed)
        app.shell.receive(.tick(1))

        #expect(app.player.playbackSpeed == .double)
    }

    @MainActor
    @Test func speedStepsUpFromNormal() {
        let app = makeApp()
        app.player.setPlaybackSpeed(.normal)

        app.shell.claim(.speed)
        app.shell.receive(.tick(1))

        #expect(app.player.playbackSpeed == .oneAndQuarter)
    }
}
