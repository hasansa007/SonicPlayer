import Foundation
import Synchronization  // Mutex — the client closures are @Sendable
import Testing

@testable import SonicPlayer

/// Delete asks first (#6).
///
/// **The wheel is what makes this necessary rather than merely polite.** The actions menu is
/// reached by turning, and the menu now wraps — so one detent past the first row is `Delete`. An
/// unguarded destructive row one click from the top of a menu you scroll blind is a trap, and that
/// is precisely why this and the wrap-around belong to the same change.
///
/// The guard is a **screen**, not an alert: two rows, `Cancel` first so the highlight rests on the
/// safe answer, with the file named above them. Confirming is the same turn-and-press as everything
/// else, which the system alert it replaced was the one place to interrupt.
@Suite(.serialized)
struct DialDeleteConfirmationTests {

    @MainActor
    private func makeApp(deleted: @escaping @Sendable (URL) -> Void = { _ in }) -> AppViewModel {
        var audioPlayer = AudioPlayerClient.test
        audioPlayer.stop = {}
        audioPlayer.setRate = { _ in }
        audioPlayer.setVolume = { _ in }

        var fileManager = FileManagerClient.test
        fileManager.deleteItem = { url in deleted(url) }

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
            fileManager: fileManager
        )
    }

    private static let url = URL(fileURLWithPath: "/Docs/Recordings/Lecture.m4a")

    private func file() -> AudioFile {
        AudioFile(
            url: Self.url,
            title: "Lecture",
            duration: 100,
            fileSize: 1,
            format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0)
        )
    }

    /// Drives the dial to `Delete` on the actions menu of the only recording there is.
    @MainActor
    private func pressDelete(_ app: AppViewModel) {
        app.home.allFiles = [file()]
        app.refreshDial()

        // **The library is the root, so there is nothing to press through.** Delete used to be
        // Record's alone, which meant taking the far side of a fork to reach it; the fork is gone
        // and the two-row guard is what makes it safe.
        app.dial.receive(.action("delete"))     // the stick's down nudge, on the only file
    }

    @MainActor
    @Test func pressingDeleteOpensTheGuardAndDoesNothingElse() {
        let deletions = Mutex<[URL]>([])
        let app = makeApp { url in deletions.withLock { $0.append(url) } }

        pressDelete(app)

        let screen = app.dial.screen
        #expect(screen.chrome.breadcrumb.last == "DELETE")
        guard case .list(let list) = screen.content else {
            Issue.record("expected the two-row guard, got \(screen.content)")
            return
        }
        #expect(list.rows.map(\.id) == ["cancel", "delete"])
        #expect(list.highlighted == 0, "the safe answer is the one a stray press gives you")
        #expect(list.subject?.title == "Lecture", "it has to name what it will destroy")
        #expect(deletions.withLock { $0 }.isEmpty, "nothing may leave disk before the answer")
    }

    @MainActor
    @Test func cancellingLeavesTheFileAlone() {
        let deletions = Mutex<[URL]>([])
        let app = makeApp { url in deletions.withLock { $0.append(url) } }
        pressDelete(app)

        app.dial.receive(.press)            // Cancel is row 0

        #expect(app.dial.screen.chrome.breadcrumb.last == "LIBRARY", "and it comes back")
        #expect(deletions.withLock { $0 }.isEmpty)
    }

    /// **Waits for the deletion rather than yielding once and hoping.**
    ///
    /// The first version of this called `await Task.yield()` and passed on its own and failed in the
    /// full suite — the delete runs inside a `Task`, and a single yield is not a promise that it has
    /// been reached. A continuation waits exactly as long as the work takes, and a delete that never
    /// arrives hangs the test instead of passing it.
    @MainActor
    @Test func confirmingDeletesIt() async {
        let pending = Mutex<CheckedContinuation<URL, Never>?>(nil)
        let app = makeApp { url in
            pending.withLock { continuation in
                continuation?.resume(returning: url)
                continuation = nil
            }
        }
        pressDelete(app)

        let deleted = await withCheckedContinuation { (continuation: CheckedContinuation<URL, Never>) in
            pending.withLock { $0 = continuation }
            app.dial.receive(.tick(1))      // onto Delete
            app.dial.receive(.press)
        }

        #expect(deleted == Self.url)
        #expect(app.dial.screen.chrome.breadcrumb.last == "LIBRARY")
    }

    /// **The release belongs to editing, which is the thing that rewrites a file.**
    ///
    /// It sat on mode-entry while the fork existed — entering Record let go of the player, so the
    /// editor could never rewrite a file something was holding. With one library it moves to the
    /// edit nudge, which is the moment it was always about.
    @MainActor
    @Test func openingTheEditorReleasesWhateverWasLoaded() {
        let app = makeApp()
        app.home.allFiles = [file()]
        app.player.currentTrack = file()
        app.refreshDial()

        app.dial.receive(.action("edit"))

        #expect(app.player.currentTrack == nil, "before the editor can rewrite it")
    }

    /// The browser's edge is where "stop playing what is about to vanish" lives, and it is still
    /// reachable — from the Files sheet, which has no modes.
    @MainActor
    @Test func removingAPlayingFileThroughTheBrowserStopsPlayback() {
        let app = makeApp()
        app.player.currentTrack = file()

        app.filesRoot.onWillRemoveItems([.file(file())])

        #expect(app.player.currentTrack == nil)
    }
}
