import Foundation
import Testing

@testable import SonicPlayer

/// The I/O half of session restore (#44).
///
/// Every case here was previously unreachable without constructing a `PlayerViewModel` with four
/// clients: the resolution ran inside `restoreSession`, and it probed the filesystem through
/// `FileManager.default` rather than the injected client, so no test could control what it found.
@Suite
struct PlaybackRepositoryTests {

    private func session(_ current: String, queue: [String]) -> PlaybackSession {
        PlaybackSession(
            fileURL: "/Docs/\(current).mp3",
            currentTime: 12,
            queue: queue.map { QueueItem(fileURL: "/Docs/\($0).mp3") }
        )
    }

    /// Missing files are reported by `getMetadata` throwing, which is what removed the separate
    /// `FileManager.default.fileExists` probe: the metadata read already fails for a file that is
    /// not there, and it fails through the *injected* client, where a test can drive it.
    private static func metadataThatIsMissing(_ names: Set<String>) -> @Sendable (URL) async throws -> AudioFile {
        { url in
            guard !names.contains(url.lastPathComponent) else {
                throw CocoaError(.fileNoSuchFile)
            }
            return AudioFile(
                url: url,
                title: url.deletingPathExtension().lastPathComponent,
                duration: 100,
                fileSize: 1,
                format: .mp3,
                creationDate: Date(timeIntervalSince1970: 0)
            )
        }
    }

    @Test func test_restore_dropsQueueEntriesThatNoLongerResolve() async {
        var files = FileManagerClient.test
        files.getMetadata = Self.metadataThatIsMissing(["gone.mp3"])

        let repository = LivePlaybackRepository(files: files)
        let resolved = await repository.restore(session("a", queue: ["a", "gone", "b"]))

        #expect(resolved?.queue.map(\.title) == ["a", "b"])
    }

    /// The anchor track going missing is not the same as a queue entry going missing: without it
    /// there is nothing to resume, so the whole restore is abandoned and the caller clears.
    @Test func test_restore_abandonsEverythingWhenTheCurrentTrackIsGone() async {
        var files = FileManagerClient.test
        files.getMetadata = Self.metadataThatIsMissing(["a.mp3"])

        let repository = LivePlaybackRepository(files: files)

        #expect(await repository.restore(session("a", queue: ["a", "b"])) == nil)
    }

    /// The empty-session guard lives in `SessionRestorePlan`, and the repository must not reach
    /// the filesystem before it runs — `URL(fileURLWithPath: "")` resolves to the process's
    /// current directory, which exists and answers metadata reads (#33).
    @Test func test_restore_touchesNoFilesystemForAnEmptySession() async {
        // Every closure on `.test` reports an issue when called, so reaching the client at all
        // fails this test rather than quietly returning something plausible.
        let repository = LivePlaybackRepository(files: FileManagerClient.test)

        #expect(await repository.restore(PlaybackSession()) == nil)
    }
}
