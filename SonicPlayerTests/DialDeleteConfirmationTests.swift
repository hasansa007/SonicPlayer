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

        // Home is Library then Record, and the highlight opens on row 0 — so Library is already
        // under it and a tick here would land on Record instead.
        app.dial.receive(.press)            // into the recordings list, highlight on Import
        app.dial.receive(.tick(1))          // onto the recording
        app.dial.receive(.action("more"))   // the actions menu
        app.dial.receive(.tick(4))          // Rename, Edit, Share, Add to playlist, Delete
        app.dial.receive(.press)
    }

    @MainActor
    @Test func pressingDeleteAsksBeforeDoingAnything() {
        let deletions = Mutex<[URL]>([])
        let app = makeApp { url in deletions.withLock { $0.append(url) } }

        pressDelete(app)

        #expect(app.dial.pendingDelete?.title == "Lecture", "the alert has to name what it will destroy")
        #expect(deletions.withLock { $0 }.isEmpty, "nothing may leave disk before the answer")
    }

    @MainActor
    @Test func cancellingLeavesTheFileAlone() {
        let deletions = Mutex<[URL]>([])
        let app = makeApp { url in deletions.withLock { $0.append(url) } }
        pressDelete(app)

        app.dial.cancelDelete()

        #expect(app.dial.pendingDelete == nil)
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
            app.dial.confirmDelete()
        }

        #expect(deleted == Self.url)
        #expect(app.dial.pendingDelete == nil)
    }

    /// The dial's delete travels through `onWillRemoveItems`, the same edge the browser's delete
    /// uses — which is what stops playback of a file about to vanish. Re-implementing it here would
    /// be a second copy free to drift.
    @MainActor
    @Test func deletingWhatIsPlayingStopsPlayback() async {
        let app = makeApp()
        app.player.currentTrack = file()
        pressDelete(app)

        app.dial.confirmDelete()
        await Task.yield()

        #expect(app.player.currentTrack == nil)
    }
}
