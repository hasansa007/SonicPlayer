import Foundation
import Testing

@testable import SonicPlayer

/// The half of #22 that moved out of `AppFeature` when the player stopped being a reducer (#15).
///
/// `AppFeature` used to read `state.player.currentTrack` and run `PathMatching` itself. It cannot
/// reach the track any more, so it forwards what is being removed and the decision lands here.
/// `ExtractionScaffoldTests` pins the forwarding; this pins the deciding.
///
/// Deliberately no `import ComposableArchitecture`. The whole claim of #15 is that the player is
/// testable as a plain object — a `TestStore` appearing in this file would mean it is not.
@Suite(.serialized)
struct PlayerViewModelTests {

    @MainActor
    @Test func test_removingTheContainingFolder_stopsPlayback() {
        let player = makePlayer(playing: "/Docs/Podcasts/Ep1.mp3")

        player.clearSessionIfAffected(by: [URL(fileURLWithPath: "/Docs/Podcasts")])

        #expect(player.currentTrack == nil, "Deleting the folder the track lives in must stop playback (#22).")
    }

    @MainActor
    @Test func test_removingTheTrackItself_stopsPlayback() {
        let player = makePlayer(playing: "/Docs/Podcasts/Ep1.mp3")

        player.clearSessionIfAffected(by: [URL(fileURLWithPath: "/Docs/Podcasts/Ep1.mp3")])

        #expect(player.currentTrack == nil)
    }

    @MainActor
    @Test func test_removingAnUnrelatedFile_leavesPlaybackAlone() {
        let player = makePlayer(playing: "/Docs/Podcasts/Ep1.mp3")

        player.clearSessionIfAffected(by: [URL(fileURLWithPath: "/Docs/Music/Song.mp3")])

        #expect(player.currentTrack != nil, "Moving an unrelated file must not stop playback.")
    }

    /// The prefix match is on path *components*, not characters — `/Docs/Rock` must not be treated
    /// as containing `/Docs/Rocks/Ep1.mp3`. `PathMatchingTests` covers the predicate; this checks
    /// the view model actually reaches it rather than doing its own looser comparison.
    @MainActor
    @Test func test_aSiblingFolderWithASharedPrefix_leavesPlaybackAlone() {
        let player = makePlayer(playing: "/Docs/Rocks/Ep1.mp3")

        player.clearSessionIfAffected(by: [URL(fileURLWithPath: "/Docs/Rock")])

        #expect(player.currentTrack != nil)
    }

    @MainActor
    @Test func test_withNothingPlaying_isANoOp() {
        let player = makePlayer(playing: nil)

        player.clearSessionIfAffected(by: [URL(fileURLWithPath: "/Docs/Podcasts")])

        #expect(player.currentTrack == nil)
    }

    // MARK: -

    /// `.test` clients throughout and an in-memory store, so nothing here touches the real audio
    /// session or the on-disk `session.json`.
    @MainActor
    private func makePlayer(playing path: String?) -> PlayerViewModel {
        var audioPlayer = AudioPlayerClient.test
        // Every closure on `.test` reports rather than silently succeeding (`TestClients.swift`).
        // `stop` needs a stub precisely *because* the behaviour under test reaches it: clearing
        // the session must stop playback, not just forget the track.
        audioPlayer.stop = {}

        let player = PlayerViewModel(
            audioPlayer: audioPlayer,
            fileManager: .test,
            artworkClient: .test,
            sessionStore: .inMemory()
        )
        if let path {
            let url = URL(fileURLWithPath: path)
            let track = AudioFile(url: url, title: url.deletingPathExtension().lastPathComponent,
                duration: 100, fileSize: 1, format: .mp3,
                creationDate: Date(timeIntervalSince1970: 0))
            player.currentTrack = track
            player.queue = [track]
            player.duration = 100
        }
        return player
    }
}
