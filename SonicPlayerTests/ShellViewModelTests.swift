import Foundation
import Testing

@testable import SonicPlayer

/// The whole shell, driven with nothing rendered — which is what routing through a command stream
/// buys, and the same shape `AppViewModelTests` uses for cross-feature edges.
@Suite(.serialized)
struct ShellViewModelTests {

    @MainActor
    private func makeShell(
        currentTime: TimeInterval = 50,
        duration: TimeInterval = 100,
        haptics: HapticsClient? = nil
    ) -> (ShellViewModel, PlayerViewModel) {
        var silent = HapticsClient.test
        silent.fire = { _ in }
        let player = PlayerViewModel(audioPlayer: .test)
        player.duration = duration
        player.currentTime = currentTime
        let shell = ShellViewModel(player: player, haptics: haptics ?? silent)
        shell.onSeek = { _ in }
        return (shell, player)
    }

    @MainActor
    @Test func turningSeeksByTheDetentSize() {
        let (shell, _) = makeShell()
        var sought: TimeInterval?
        shell.onSeek = { sought = $0 }

        shell.receive(.tick(5))

        #expect(abs((sought ?? .nan) - 50.5) < 1e-9)
    }

    @MainActor
    @Test func seekingIsClampedToTheTrack() {
        let (shell, _) = makeShell(currentTime: 99.95)
        var sought: TimeInterval?
        shell.onSeek = { sought = $0 }

        shell.receive(.tick(20))

        #expect(sought == 100)
    }

    /// Turning against the end of a track has to feel like a wall, not like a dead wheel.
    @MainActor
    @Test func aRefusedSeekFeelsDifferentFromAnAcceptedOne() {
        var fired: [DetentFeedback.Pulse] = []
        var haptics = HapticsClient.test
        haptics.fire = { fired.append($0) }
        let (shell, _) = makeShell(currentTime: 100, haptics: haptics)

        shell.receive(.tick(3))

        #expect(fired == [DetentFeedback.pulse(for: .limit)])
    }

    @MainActor
    @Test func theHubTogglesPlayback() {
        let (shell, _) = makeShell()
        var toggled = false
        shell.onPlayPause = { toggled = true }

        shell.receive(.select)

        #expect(toggled)
    }

    @MainActor
    @Test func focusStartsOnSeek() {
        let (shell, _) = makeShell()

        #expect(shell.focus == .nowPlaying(.seek))
    }

    @MainActor
    @Test func claimingVolumeMovesTheFocusAndRaisesTheHUD() {
        let (shell, _) = makeShell()

        shell.claim(.volume)

        #expect(shell.focus == .nowPlaying(.volume))
        #expect(shell.hud != nil)
    }

    @MainActor
    @Test func releasingReturnsToSeekAndDropsTheHUD() {
        let (shell, _) = makeShell()
        shell.claim(.volume)

        shell.release()

        #expect(shell.focus == .nowPlaying(.seek))
        #expect(shell.hud == nil)
    }

    /// Slice 1's inert targets. They must not seek, and must not crash.
    @MainActor
    @Test func menuAndBackDoNothingYet() {
        let (shell, _) = makeShell()
        var sought = false
        shell.onSeek = { _ in sought = true }

        shell.receive(.menu)
        shell.receive(.back)

        #expect(!sought)
    }
}
