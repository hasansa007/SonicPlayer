import Foundation
import SwiftUI          // ScenePhase
import Synchronization  // Mutex — the drain closure is @Sendable
import Testing

@testable import SonicPlayer

/// The composition root (#19), which replaced `AppFeature` and the root `Store`.
///
/// These tests are the point of owning the children here rather than on `AppView`: the wiring is
/// constructor work now, so every cross-feature edge can be exercised without a view, a store or a
/// simulator. Under the old shape the same edges lived in `AppView.wireViewModels()` and were
/// reachable only by rendering.
///
/// `.serialized` because `SettingsViewModel` reads and writes `UserDefaults.standard`.
@Suite(.serialized)
struct AppViewModelTests {

    // MARK: - The reason this type exists

    /// `AppDelegate` calls these from UIKit, outside any view. They are the only reason the root
    /// object is reachable statically, and the only reason it exists at all.
    @MainActor
    /// **It opens the dial's recorder, not a sheet.**
    ///
    /// This asserted `isRecordingSheetPresented`, which raised `RecordingView` — so long-pressing
    /// the app icon gave a different recording experience from the one the dial gives: a modal with
    /// a navigation bar, no wheel, and no way to drop a marker. One app, two recorders, chosen by
    /// how you happened to start it.
    @Test func test_quickActionRecord_opensTheDialsRecorder() {
        let app = makeApp()

        app.quickActionRecord()

        #expect(app.dial.screen.chrome.breadcrumb == ["LIBRARY", "RECORDING"])
        #expect(app.dial.screen.ring.hub == .recordDot, "arrived, not started")
    }

    /// **It resets rather than pushes.** A quick action means "start here", and stacking the
    /// recorder on wherever the app was left would put a Back on it leading somewhere nobody chose.
    @MainActor
    @Test func test_quickActionRecord_startsFromTheRootWhereverYouWere() {
        let app = makeApp()
        app.dial.receive(.press)            // into whatever the first row is

        app.quickActionRecord()

        app.dial.receive(.action("back"))
        #expect(app.dial.screen.chrome.breadcrumb == ["LIBRARY"], "one level, and no further")
    }

    @MainActor
    @Test func test_quickActionImport_opensTheImportSheet() {
        let app = makeApp()

        app.quickActionImport()

        #expect(app.isImportSheetPresented)
    }

    // MARK: - The wiring

    /// #22's other half, end to end through the coordinator: the browser announces a removal, and
    /// the player — which owns the track — decides whether it is affected.
    @MainActor
    @Test func test_removingThePlayingFile_stopsPlayback() {
        let app = makeApp()
        let url = URL(fileURLWithPath: "/Docs/Podcasts/Ep1.mp3")
        app.player.currentTrack = audioFile(at: url)

        app.filesRoot.onWillRemoveItems([.file(audioFile(at: url))])

        #expect(app.player.currentTrack == nil)
    }

    @MainActor
    @Test func test_removingAnUnrelatedFile_leavesPlaybackAlone() {
        let app = makeApp()
        app.player.currentTrack = audioFile(at: URL(fileURLWithPath: "/Docs/Podcasts/Ep1.mp3"))

        app.filesRoot.onWillRemoveItems([.file(audioFile(at: URL(fileURLWithPath: "/Docs/Music/Song.mp3")))])

        #expect(app.player.currentTrack != nil)
    }

    @MainActor
    @Test func test_finishingARecording_dismissesTheSheet() {
        let app = makeApp()
        app.isRecordingSheetPresented = true

        app.recording.onFinished()

        #expect(!app.isRecordingSheetPresented)
    }

    @MainActor
    /// **Import is the dial's now, and Home's edge is gone.**
    ///
    /// `home.onImportTapped` was called from exactly one place — the pre-dial Home screen, which
    /// stopped being rendered when the dial became the root. The verb did not go anywhere: it is
    /// pinned above the library in Listen mode, and this is the path that actually runs.
    @Test func test_theDialsImportOpensTheImportSheet() {
        let app = makeApp()

        app.dial.receive(.action("import"))

        #expect(app.isImportSheetPresented)
    }

    @MainActor
    @Test func test_tappingACollection_pushesItOntoThePath() {
        let app = makeApp()
        let folder = CollectionItem(
            id: URL(fileURLWithPath: "/Docs/Lectures"),
            url: URL(fileURLWithPath: "/Docs/Lectures"),
            name: "Lectures",
            creationDate: Date(timeIntervalSince1970: 0)
        )

        app.filesRoot.onCollectionTapped(folder)

        #expect(app.path == [folder.url])
    }

    /// Settings reaching the player was a cross-feature action tap in `AppFeature`.
    @MainActor
    @Test func test_changingTheDefaultSpeed_reachesThePlayer() {
        let app = makeApp()

        app.settings.setDefaultPlaybackSpeed(.double)

        #expect(app.player.playbackSpeed == .double)
    }

    /// Home holds the *same* player instance — that is what let `HomeFeature`'s three mirrored
    /// playback properties be deleted rather than ported (#16). If they were ever built
    /// independently the mirror would silently come back.
    @MainActor
    @Test func test_homeAndTheCoordinator_shareOnePlayer() {
        let app = makeApp()

        #expect(app.home.player === app.player)
    }

    // MARK: - Lifetime

    /// `wire()` hands closures to the children. If any of them captured `self` strongly, the
    /// coordinator would be kept alive by the objects it owns. A process-lifetime root would never
    /// notice — a test that builds one leaks, which is what this catches.
    @MainActor
    @Test func test_theCoordinator_isNotRetainedByItsChildren() {
        var app: AppViewModel? = makeApp()
        weak var leaked = app
        #expect(leaked != nil)

        app = nil

        #expect(leaked == nil, "wire() created a child → closure → coordinator cycle.")
    }

    // MARK: - Helpers

    /// `.test` clients throughout, so constructing this touches no audio session and no real
    /// file system. `onboarding` is nil because every test here is past first launch.
    @MainActor
    private func makeApp(fileManager: FileManagerClient = .test) -> AppViewModel {
        var audioPlayer = AudioPlayerClient.test
        // Reached by `clearSessionIfAffected` — clearing the session must stop playback, not just
        // forget the track.
        audioPlayer.stop = {}
        audioPlayer.setRate = { _ in }

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

    // MARK: - Draining iOS's staging directory (#41)

    /// Installs that predate #41 still hold copies iOS left in `Documents/Inbox`, and the browser
    /// now filters that directory — so they are invisible as well as orphaned. This is what clears
    /// them.
    ///
    /// The assertion has no `await` in it deliberately. The drain must have **finished** by the
    /// time the handler returns, because after that the app may be suspended: an earlier version
    /// dispatched into a `Task` and, measured on the simulator, ran on the next foreground instead
    /// — which is where an `.onOpenURL` import can be in flight over the same directory. A test
    /// that polled for the flag passed against that version too.
    @MainActor
    @Test func test_backgrounding_drainsTheStagingDirectory() {
        let drained = Mutex(false)
        var fileManager = FileManagerClient.test
        fileManager.drainStagingDirectory = { drained.withLock { $0 = true } }
        let app = makeApp(fileManager: fileManager)

        app.scenePhaseChanged(.background)

        #expect(drained.withLock { $0 }, "The drain must complete before the handler returns (#41).")
    }

    /// **The race this placement exists to avoid.** Launching the app *by opening a file* is
    /// precisely when a staged file is sitting in `Inbox` waiting for `.onOpenURL`, and the
    /// ordering of `.onOpenURL` against the launch path is not guaranteed. Draining on any phase
    /// but `.background` could delete the file the user just asked to open.
    /// `openFromFiles` runs its move detached, so it can still be working inside `Inbox` when the
    /// app backgrounds. Draining then deletes the file mid-import — the import is lost, and the
    /// user gets "Action Failed" for an open iOS already accepted.
    @MainActor
    @Test func test_backgrounding_doesNotDrainWhileAnImportIsInFlight() throws {
        let drained = Mutex(false)
        var fileManager = FileManagerClient.test
        fileManager.drainStagingDirectory = { drained.withLock { $0 = true } }
        let app = makeApp(fileManager: fileManager)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DrainRace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        app.player.openFromFiles(dir.appendingPathComponent("Never Resolves.mp3"))
        app.scenePhaseChanged(.background)

        #expect(!drained.withLock { $0 }, "An in-flight import outranks the drain (#41).")
    }

    @MainActor
    @Test func test_becomingActiveOrInactive_neverDrains() {
        let drained = Mutex(false)
        var fileManager = FileManagerClient.test
        fileManager.drainStagingDirectory = { drained.withLock { $0 = true } }
        let app = makeApp(fileManager: fileManager)

        app.scenePhaseChanged(.active)
        app.scenePhaseChanged(.inactive)

        #expect(!drained.withLock { $0 }, "Only backgrounding may drain — anything earlier races the open (#41).")
    }

    private func audioFile(at url: URL) -> AudioFile {
        AudioFile(
            url: url,
            title: url.deletingPathExtension().lastPathComponent,
            duration: 100,
            fileSize: 1,
            format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0)
        )
    }
}
