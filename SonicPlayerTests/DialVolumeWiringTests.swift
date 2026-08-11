import Foundation
import Testing

@testable import SonicPlayer

/// The volume path from the stick to the player, which is the half that was actually broken (#6).
///
/// **`DialModeTests` already proved the navigator emits `.setVolume`, and it always did.** The
/// nudges routed, the value clamped, the effect came out — and then `DialViewModel` dropped it on
/// the floor with a `break`, under a note explaining that volume belongs to `MPVolumeView`. So
/// every test in the suite passed while the control did nothing on the device.
///
/// That is what these cover: not that the effect is produced, but that something receives it.
@Suite(.serialized)
struct DialVolumeWiringTests {

    @MainActor
    private func makeApp() -> AppViewModel {
        var audioPlayer = AudioPlayerClient.test
        audioPlayer.stop = {}
        audioPlayer.setRate = { _ in }
        audioPlayer.setVolume = { _ in }

        return AppViewModel(
            player: PlayerViewModel(
                audioPlayer: audioPlayer,
                fileManager: .test,
                artworkClient: .test,
                sessionStore: .inMemory()
            ),
            recording: RecordingViewModel(audioRecorder: .test, audioPlayer: audioPlayer, fileManager: .test),
            settings: SettingsViewModel(),
            filesRoot: CollectionsViewModel(currentDirectory: nil, fileManager: .test),
            onboarding: nil,
            fileManager: .test
        )
    }

    @MainActor
    private func playing(_ app: AppViewModel) {
        app.player.currentTrack = AudioFile(
            url: URL(fileURLWithPath: "/Docs/Recordings/Lecture.m4a"),
            title: "Lecture",
            duration: 600,
            fileSize: 1,
            format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0)
        )
        app.player.duration = 600
        app.refreshDial()
        app.dial.receive(.action("nowPlaying"))
    }

    @MainActor
    @Test func nudgingUpRaisesThePlayersVolume() {
        let app = makeApp()
        playing(app)
        app.player.setVolume(0.5)
        app.refreshDial()

        app.dial.receive(.action("volumeUp"))

        #expect(app.player.volume > 0.5, "the nudge has to reach the player, not stop at the effect")
    }

    @MainActor
    @Test func nudgingDownLowersIt() {
        let app = makeApp()
        playing(app)
        app.player.setVolume(0.5)
        app.refreshDial()

        app.dial.receive(.action("volumeDown"))

        #expect(app.player.volume < 0.5)
    }

    @MainActor
    @Test func volumeStopsAtTheEndsRatherThanWrappingOrOverflowing() {
        let app = makeApp()
        playing(app)

        app.player.setVolume(0)
        for _ in 0..<50 { app.refreshDial(); app.dial.receive(.action("volumeDown")) }
        #expect(app.player.volume == 0)

        app.player.setVolume(1)
        for _ in 0..<50 { app.refreshDial(); app.dial.receive(.action("volumeUp")) }
        #expect(app.player.volume == 1)
    }

    /// **The second bug, and the one that would have hidden the fix for the first.**
    ///
    /// `DialContent.Playback.volume` defaults to 1 and `refresh` never filled it in, so every pass
    /// handed the navigator a full-volume picture. Wired but unfed, the wheel would have moved the
    /// player and then been overwritten on the next refresh — the arc snapping back to full while
    /// the audio stayed quiet.
    ///
    /// Asserted through the consequence rather than by reading the navigator's copy, which is
    /// private: with the player silent and the dial told so, a downward nudge has nothing to give
    /// and must leave it at zero. Fed the default instead, the dial would believe it was at full
    /// and this nudge would *raise* the player to 0.96.
    @MainActor
    @Test func refreshCarriesTheCurrentVolumeIntoTheDial() {
        let app = makeApp()
        playing(app)

        app.player.setVolume(0)
        app.refreshDial()

        app.dial.receive(.action("volumeDown"))

        #expect(app.player.volume == 0, "the dial was told the player is silent, so there is nothing below")
    }
}
