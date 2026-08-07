import Foundation
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
    @Test func test_quickActionRecord_opensTheRecordingSheet() {
        let app = makeApp()
        #expect(!app.isRecordingSheetPresented)

        app.quickActionRecord()

        #expect(app.isRecordingSheetPresented)
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
    @Test func test_homeImportTap_opensTheImportSheet() {
        let app = makeApp()

        app.home.onImportTapped()

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
    private func makeApp() -> AppViewModel {
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
            onboarding: nil
        )
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
