import Foundation
import Testing

@testable import SonicPlayer

/// `PlayerViewModel.restoreSession` resolving through `PlaybackRepository` (#44).
///
/// The point of every test here is what is **not** stubbed: `fileManager` stays `.test`
/// throughout, so any filesystem call the view model makes during a restore reports an issue and
/// fails the test. Before #44 that was impossible — the resolution ran inline and reached
/// `FileManager.default`, which no client substitution could intercept.
@Suite(.serialized)
struct PlayerRestoreTests {

    /// Mirrors the `.test` clients in `TestClients.swift`: a member reached without being stubbed
    /// reports rather than returning something plausible, so a path nobody expected to be on
    /// fails loudly instead of quietly resolving to nil.
    private struct StubPlaybackRepository: PlaybackRepository {
        var onRestore: (@Sendable (PlaybackSession) async -> SessionRestorePlan.Resolved?)?

        func restore(_ saved: PlaybackSession) async -> SessionRestorePlan.Resolved? {
            guard let onRestore else {
                Issue.record("PlaybackRepository.restore is unimplemented")
                return nil
            }
            return await onRestore(saved)
        }
    }

    private func track(_ name: String) -> AudioFile {
        AudioFile(
            url: URL(fileURLWithPath: "/Docs/\(name).mp3"),
            title: name,
            duration: 100,
            fileSize: 1,
            format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0)
        )
    }

    /// A store already holding a session, so `restoreSession` gets past its empty guard.
    private func storeHolding(_ file: AudioFile) -> SessionStore {
        let store = SessionStore.inMemory()
        store.save(SessionCodec.session(
            trackURL: file.url, currentTime: 42, queueURLs: [file.url], playlistSource: nil
        ))
        return store
    }

    @MainActor
    private func makePlayer(
        repository: StubPlaybackRepository,
        sessionStore: SessionStore
    ) -> PlayerViewModel {
        var audioPlayer = AudioPlayerClient.test
        // Only what `restoreWithRetry` reaches. A non-zero duration ends it on the first attempt.
        audioPlayer.prepare = { _ in }
        audioPlayer.setRate = { _ in }
        audioPlayer.seek = { _ in }
        audioPlayer.pause = {}
        audioPlayer.duration = { 100 }
        audioPlayer.updateNowPlaying = {}

        return PlayerViewModel(
            audioPlayer: audioPlayer,
            fileManager: .test,          // deliberately unstubbed — see the suite comment
            artworkClient: .test,
            sessionStore: sessionStore,
            repository: repository
        )
    }

    @MainActor
    private func settle(_ player: PlayerViewModel) async {
        for _ in 0..<40 {
            if player.currentTrack != nil { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor
    @Test func test_restore_resolvesThroughTheRepositoryAndNotTheFilesystem() async {
        let saved = track("Lecture 3")
        let repository = StubPlaybackRepository { _ in
            SessionRestorePlan.Resolved(track: saved, queue: [saved], index: 0)
        }

        let player = makePlayer(repository: repository, sessionStore: storeHolding(saved))
        player.restoreSession()
        await settle(player)

        #expect(player.currentTrack == saved)
        #expect(player.queue == [saved])
    }

    /// The repository reporting nothing to restore clears the session rather than leaving a
    /// half-restored player. This is the path that used to be a `FileManager.default.fileExists`
    /// check the test could not reach.
    @MainActor
    @Test func test_restore_clearsTheSessionWhenNothingResolves() async {
        let saved = track("Deleted")
        let store = storeHolding(saved)
        var audioPlayerStopped = false

        let repository = StubPlaybackRepository { _ in nil }
        var audioPlayer = AudioPlayerClient.test
        audioPlayer.stop = { audioPlayerStopped = true }

        let player = PlayerViewModel(
            audioPlayer: audioPlayer,
            fileManager: .test,
            artworkClient: .test,
            sessionStore: store,
            repository: repository
        )

        player.restoreSession()
        for _ in 0..<40 where !audioPlayerStopped {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(player.currentTrack == nil)
        #expect(store.load().isEmpty, "A restore that resolves nothing must clear the saved session.")
    }

    /// The #33 ordering, now that resolution is behind a repository: an explicit open claims
    /// priority synchronously, and a restore landing afterwards must not overwrite it.
    @MainActor
    @Test func test_anExplicitOpen_stillOutranksARestoreThatLandsLater() async {
        let saved = track("Previously Playing")
        let repository = StubPlaybackRepository { _ in
            SessionRestorePlan.Resolved(track: saved, queue: [saved], index: 0)
        }

        let player = makePlayer(repository: repository, sessionStore: storeHolding(saved))

        // Claim priority the way `.onOpenURL` does, before the restore is asked for.
        player.openFromFiles(URL(fileURLWithPath: "/nowhere/Opened.mp3"))
        player.restoreSession()

        for _ in 0..<40 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(
            player.currentTrack != saved,
            "A restored session must never replace the file the user explicitly opened (#33)."
        )
    }
}
