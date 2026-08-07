import Foundation
import Testing

@testable import SonicPlayer

/// #33 — opening a file handed over by another app.
///
/// The issue attributed the failure to `refreshFiles` relocating the imported file so that the
/// metadata read returned nil. It does not: `listItems` is a pure read, and the file was always
/// where the code looked for it. The real cause is the first test below.
///
/// Deliberately no `import ComposableArchitecture` — the player is a plain object (#15) and the
/// whole path under test is reachable without a store.
@Suite(.serialized)
struct OpenFromFilesTests {

    // MARK: - The root cause

    /// `PlaybackSession()` carries `fileURL: ""`, and `URL(fileURLWithPath: "")` resolves to the
    /// process's **current directory** rather than to nothing. That directory exists, and
    /// `resourceValues` succeeds on a directory, so `restoreSession`'s existence guard passed and
    /// a *folder* was restored as a track. On the simulator it showed as a mini player titled
    /// `/` — the app's working directory on iOS.
    @MainActor
    @Test func test_restoringAnEmptySession_loadsNoTrack() async {
        let player = makePlayer()

        player.restoreSession()
        await settle(player)

        #expect(
            player.currentTrack == nil,
            "An empty session must restore nothing — not the current directory (#33)."
        )
    }

    /// The race the root cause hid behind, with a *real* saved session so it stands on its own.
    ///
    /// Launching the app by opening a file runs `.onOpenURL` and `.onAppear` against the same
    /// `currentTrack` and the same AVPlayer. Whichever finished last used to win, which is why a
    /// repeat open looked like it did nothing while the first open worked.
    @MainActor
    @Test func test_anExplicitOpen_outranksTheRestoredSession() async throws {
        let dir = try TempDir()
        let previous = try dir.write("Previously Playing.mp3")
        let opened = try dir.write("Opened From Files.mp3", in: dir.source)

        let store = SessionStore(url: dir.url.appendingPathComponent("session.json"))
        store.save(SessionCodec.session(
            trackURL: previous, currentTime: 42, queueURLs: [previous], playlistSource: nil
        ))
        let player = makePlayer(documentsDirectory: dir.url, sessionStore: store)

        // The order .onOpenURL / .onAppear fire in is not guaranteed, so the claim has to hold
        // for the harder one: the restore starting *after* the open has been requested.
        player.openFromFiles(opened)
        player.restoreSession()
        await settleUntilTrackLoaded(player)

        #expect(player.currentTrack?.url.lastPathComponent == "Opened From Files.mp3")
        #expect(
            player.currentTrack?.url.lastPathComponent != "Previously Playing.mp3",
            "A restored session must never replace the file the user explicitly opened (#33)."
        )
    }

    // MARK: - Resolving what to play

    /// The played track comes from what the import actually wrote, not from a path computed
    /// before it ran.
    @MainActor
    @Test func test_openingAFile_playsTheFileThatWasWritten() async throws {
        let dir = try TempDir()
        let opened = try dir.write("Lecture 3.m4a", in: dir.source)
        let player = makePlayer(documentsDirectory: dir.url)

        player.openFromFiles(opened)
        await settleUntilTrackLoaded(player)

        #expect(player.currentTrack?.url == dir.url.appendingPathComponent("Lecture 3.m4a"))
        #expect(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("Lecture 3.m4a").path))
    }

    /// The reported symptom: the second open of a file that is already imported.
    @MainActor
    @Test func test_openingAnAlreadyImportedFile_stillStartsPlayback() async throws {
        let dir = try TempDir()
        let opened = try dir.write("Lecture 3.m4a", in: dir.source)
        _ = try dir.write("Lecture 3.m4a")          // already imported, same name

        let player = makePlayer(documentsDirectory: dir.url)
        player.openFromFiles(opened)
        await settleUntilTrackLoaded(player)

        #expect(
            player.currentTrack?.url == dir.url.appendingPathComponent("Lecture 3.m4a"),
            "Re-opening an imported file must play it, not silently do nothing (#33)."
        )
    }

    /// `try?` used to drop the reason on the floor and leave the user on Home with no explanation.
    @MainActor
    @Test func test_anImportThatFails_reportsInsteadOfGoingQuiet() async throws {
        let dir = try TempDir()
        let missing = dir.source.appendingPathComponent("Not There.mp3")
        let player = makePlayer(documentsDirectory: dir.url)

        player.openFromFiles(missing)
        for _ in 0..<40 where player.openError == nil {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(player.openError != nil, "A failed open must surface, not be swallowed (#33).")
        #expect(player.currentTrack == nil)
    }

    // MARK: - OpenInImport

    @Test func test_import_returnsTheURLItWrote() throws {
        let dir = try TempDir()
        let source = try dir.write("Track.mp3", in: dir.source)

        let written = try OpenInImport.run(url: source, into: dir.url)

        #expect(written == dir.url.appendingPathComponent("Track.mp3"))
        #expect(try Data(contentsOf: written) == Data(contentsOf: source))
    }

    /// Preserved from the code this replaces: a name already present means already imported, so
    /// it is returned untouched rather than copied a second time.
    @Test func test_import_doesNotOverwriteAFileAlreadyThere() throws {
        let dir = try TempDir()
        let source = try dir.write("Track.mp3", in: dir.source, contents: "new")
        let existing = try dir.write("Track.mp3", contents: "original")

        let written = try OpenInImport.run(url: source, into: dir.url)

        #expect(written == existing)
        #expect(try String(contentsOf: written, encoding: .utf8) == "original")
    }

    @Test func test_import_throwsWhenTheSourceIsMissing() throws {
        let dir = try TempDir()

        #expect(throws: (any Error).self) {
            try OpenInImport.run(url: dir.source.appendingPathComponent("Gone.mp3"), into: dir.url)
        }
    }

    // MARK: - Helpers

    /// A documents directory and a separate source directory, both under one temp root, so a
    /// test never writes into the test host's real `Documents`.
    private struct TempDir {
        let url: URL
        let source: URL

        init() throws {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("OpenFromFilesTests-\(UUID().uuidString)")
            url = root.appendingPathComponent("Documents")
            source = root.appendingPathComponent("Elsewhere")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        }

        @discardableResult
        func write(_ name: String, in directory: URL? = nil, contents: String = "audio") throws -> URL {
            let target = (directory ?? url).appendingPathComponent(name)
            try Data(contents.utf8).write(to: target)
            return target
        }
    }

    /// `.test` clients throughout. Every closure is stubbed rather than only the obvious ones:
    /// `AudioPlayerClient.test` is `Self()`, and `@DependencyClient` replaces even the inline
    /// defaults with unimplemented versions, so `setRemoteHandlers` / `duration` / `timeUpdates`
    /// report failures the moment a track finishes loading.
    ///
    /// `prepare`/`seek`/`pause`/`stop` belong to the session restore that must NOT run. They are
    /// stubbed deliberately so a regression there shows up as a failed expectation about which
    /// track is playing, rather than as an unimplemented-client error that says nothing.
    @MainActor
    private func makePlayer(
        documentsDirectory: URL? = nil,
        sessionStore: SessionStore = .inMemory()
    ) -> PlayerViewModel {
        var audioPlayer = AudioPlayerClient.test
        audioPlayer.play = { _ in }
        audioPlayer.prepare = { _ in }
        audioPlayer.setRate = { _ in }
        audioPlayer.seek = { _ in }
        audioPlayer.pause = {}
        audioPlayer.stop = {}
        audioPlayer.updateNowPlaying = {}
        audioPlayer.setRemoteHandlers = { _, _ in }
        audioPlayer.duration = { 0 }
        // Not `.finished` — that is ConcurrencyExtras', and this target has no third-party
        // dependencies. An immediately-finishing stream is the same thing in stdlib terms.
        audioPlayer.timeUpdates = { AsyncStream { $0.finish() } }

        var fileManager = FileManagerClient.test
        if let documentsDirectory {
            fileManager.documentsDirectory = { documentsDirectory }
        }
        // `.test` returns a fixed stub; echoing the URL back is what lets a test assert WHICH
        // file was resolved, which is the whole point of #33.
        fileManager.getMetadata = { url in
            AudioFile(
                url: url,
                title: url.deletingPathExtension().lastPathComponent,
                duration: 1,
                fileSize: 1,
                format: .mp3,
                creationDate: Date(timeIntervalSince1970: 0)
            )
        }

        return PlayerViewModel(
            audioPlayer: audioPlayer,
            fileManager: fileManager,
            artworkClient: .test,
            sessionStore: sessionStore
        )
    }

    /// `restoreSession` has no completion callback, and once fixed it produces no observable
    /// change at all — so there is nothing to await on and `withCheckedContinuation` has no hook.
    ///
    /// A bounded poll is the honest shape: it exits early when the bug is present, which is the
    /// case this file exists to catch, and burns its full budget when it is not.
    @MainActor
    private func settle(_ player: PlayerViewModel) async {
        for _ in 0..<40 {
            if player.currentTrack != nil { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Waits for the open to land. Unlike `settle` this expects a track, so it exits as soon as
    /// there is one and the assertion that follows decides whether it is the right one.
    @MainActor
    private func settleUntilTrackLoaded(_ player: PlayerViewModel) async {
        for _ in 0..<60 {
            if player.currentTrack != nil || player.openError != nil { break }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        // Give a late-landing session restore a chance to clobber, so the race test can catch it.
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
