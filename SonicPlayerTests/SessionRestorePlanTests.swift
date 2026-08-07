import Foundation
import Testing

@testable import SonicPlayer

/// The restore decision, extracted from `PlayerViewModel.restoreSession` (#44).
///
/// Pure: no filesystem, no clients, no view model. Every case here used to be reachable only by
/// constructing a player with four clients and a real `session.json` on disk.
@Suite
struct SessionRestorePlanTests {

    private func file(_ name: String) -> AudioFile {
        AudioFile(
            url: URL(fileURLWithPath: "/Docs/\(name).mp3"),
            title: name,
            duration: 100,
            fileSize: 1,
            format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0)
        )
    }

    private func session(_ current: String, queue: [String] = []) -> PlaybackSession {
        PlaybackSession(
            fileURL: "/Docs/\(current).mp3",
            currentTime: 12,
            queue: queue.map { QueueItem(fileURL: "/Docs/\($0).mp3") }
        )
    }

    /// `URL(fileURLWithPath: "")` resolves to the process's *current directory*, which exists and
    /// answers `resourceValues` — so an empty session that reaches the filesystem restores a
    /// folder as a track, and shows up as a mini player titled `/` (#33).
    ///
    /// The guard belongs here, before anything touches disk, rather than being re-derived by
    /// whichever caller happens to run first.
    @Test func test_anEmptySession_restoresNothing() {
        let track = file("a")

        #expect(
            SessionRestorePlan.resolve(
                saved: PlaybackSession(),
                current: track,
                surviving: [track]
            ) == nil
        )
    }

    /// The track the user was on is no longer on disk. Restoring a queue without the track that
    /// anchors it would resume the wrong file, so this restores nothing and the caller clears.
    @Test func test_aCurrentTrackThatNoLongerExists_restoresNothing() {
        #expect(
            SessionRestorePlan.resolve(
                saved: session("b", queue: ["a", "b"]),
                current: nil,
                surviving: [file("a")]
            ) == nil
        )
    }

    @Test func test_theCurrentTrackInItsQueue_resolvesTheIndexItSitsAt() {
        let (a, b, c) = (file("a"), file("b"), file("c"))

        #expect(
            SessionRestorePlan.resolve(
                saved: session("b", queue: ["a", "b", "c"]),
                current: b,
                surviving: [a, b, c]
            ) == SessionRestorePlan.Resolved(track: b, queue: [a, b, c], index: 1)
        )
    }

    /// Deleting a queue entry between launches leaves the current track un-findable in what
    /// survived. Falling back to the start keeps the index in bounds — the alternative is an
    /// index pointing past the end of a shortened queue.
    @Test func test_aCurrentTrackMissingFromTheSurvivingQueue_fallsBackToTheStart() {
        let (a, b, c) = (file("a"), file("b"), file("c"))

        #expect(
            SessionRestorePlan.resolve(
                saved: session("b", queue: ["a", "b", "c"]),
                current: b,
                surviving: [a, c]
            ) == SessionRestorePlan.Resolved(track: b, queue: [a, c], index: 0)
        )
    }

    /// Every queue entry vanished but the track itself survived — playing one file alone is still
    /// a restore, so this is not the same case as a missing current track.
    @Test func test_aQueueWhoseEntriesAllVanished_stillRestoresTheTrack() {
        let a = file("a")

        #expect(
            SessionRestorePlan.resolve(
                saved: session("a", queue: ["a", "b"]),
                current: a,
                surviving: []
            ) == SessionRestorePlan.Resolved(track: a, queue: [], index: 0)
        )
    }
}
