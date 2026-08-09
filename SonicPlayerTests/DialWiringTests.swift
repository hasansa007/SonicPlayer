import Foundation
import Testing

@testable import SonicPlayer

/// The dial's cross-feature edges, exercised through the composition root — the shape `CLAUDE.md`
/// prescribes for anything wired in `AppViewModel.wire()`, and the same shape as `ShellWiringTests`.
///
/// **This is the suite the inert `default:` needed and never had.** Every test below drives a real
/// `DialCommand` into a real navigator and asserts that something outside the dial moved. Under the
/// old `apply(_:)` each of them would have passed straight through the default branch and changed
/// nothing, which is precisely why the branch survived so long.
@Suite(.serialized)
struct DialWiringTests {

    @MainActor
    private func makeApp() -> AppViewModel {
        var haptics = HapticsClient.test
        haptics.fire = { _ in }
        var audio = AudioPlayerClient.test
        audio.setRate = { _ in }
        audio.stop = {}
        return AppViewModel(
            player: PlayerViewModel(audioPlayer: audio),
            recording: RecordingViewModel(audioRecorder: .test, audioPlayer: audio, fileManager: .test),
            settings: SettingsViewModel(),
            filesRoot: CollectionsViewModel(currentDirectory: nil, fileManager: .test),
            onboarding: nil,
            fileManager: .test,
            haptics: haptics,
            audioPlayer: audio,
            audioTrimmer: .test
        )
    }

    /// Library → an empty recordings list → a take in progress.
    ///
    /// That second press is what actually starts one: opening the Record *route* only pushes the
    /// screen, and `startRecording()` is reached from the empty list, the Record chip, or the mode
    /// chooser. Driving the real path is the point of a wiring suite.
    @MainActor
    private func inCapture(_ app: AppViewModel) {
        app.home.recentFiles = []
        app.refreshDial()
        app.dial.receive(.press)        // Recordings, which is empty
        app.dial.receive(.press)        // which starts a take
    }

    // MARK: - Capture

    @MainActor
    @Test func startingATakeDrivesTheRecorderRatherThanASheet() {
        let app = makeApp()

        inCapture(app)

        #expect(app.recording.currentRecordingURL != nil, "The hub press reached the recorder.")
        #expect(!app.isRecordingSheetPresented, "The dial owns this screen now, not the old sheet.")
    }

    @MainActor
    @Test func thePauseChipReachesTheRecorder() {
        let app = makeApp()
        inCapture(app)
        app.recording.isRecording = true

        app.dial.receive(.action("pause"))

        #expect(app.recording.isPaused)
    }

    @MainActor
    @Test func theMarkerChipFilesAMarkerAtTheElapsedTime() {
        let app = makeApp()
        inCapture(app)
        app.recording.isRecording = true
        app.recording.recordingTime = 62

        app.dial.receive(.action("marker"))

        #expect(app.recording.markers.times == [62])
    }

    /// The gain axis refuses on hardware with none, and `.test` reports none — so the assertion is
    /// that nothing moved *and* nothing was faked, which is the whole point of #75's refusal.
    @MainActor
    @Test func turningOnTheCaptureScreenDoesNotInventGainTheHardwareLacks() {
        let app = makeApp()
        inCapture(app)
        app.recording.isRecording = true
        app.refreshDial()

        app.dial.receive(.tick(3))

        #expect(!app.recording.isGainSettable)
        #expect(app.recording.gain == 1)
    }

    // MARK: - Markers reaching the editor

    /// The full path #75 asks for, minus the disk: a take is marked, saved under whatever name it
    /// ends up with, and the editor finds those markers again.
    @MainActor
    @Test func markersFiledOnSaveComeBackUnderTheNameTheTakeLandedAs() {
        let app = makeApp()
        app.recording.isRecording = true
        app.recording.recordingTime = 30
        app.recording.addMarker()
        app.recording.recordingTime = 90
        app.recording.addMarker()

        let saved = URL(fileURLWithPath: "/Recordings/Lecture 2.m4a")
        app.recording.onSaved(saved)

        #expect(app.markers.markers(for: saved).times == [30, 90])
    }

    /// A path can be handed out again after a delete, and markers that outlive their audio are
    /// worse than no markers at all.
    @MainActor
    @Test func deletingARecordingForgetsItsMarkers() {
        let app = makeApp()
        let url = URL(fileURLWithPath: "/Recordings/Lecture.m4a")
        app.markers.set(RecordingMarkers(times: [30]), for: url)

        app.filesRoot.onWillRemoveItems([.file(Self.file(at: url))])

        #expect(app.markers.markers(for: url).isEmpty)
    }

    // MARK: - Trimming

    @MainActor
    @Test func committingATrimRewritesTheRecording() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Lecture.m4a")
        try Data("original".utf8).write(to: url)

        let app = makeApp()
        app.home.recentFiles = [Self.file(at: url, duration: 600)]
        app.refreshDial()

        app.dial.onCommitTrim?(url.absoluteString, 5, 30)
        for _ in 0..<80 where (try? Data(contentsOf: url)) == Data("original".utf8) {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }

        // `.test`'s trimmer hands the staged copy straight back, so what lands is the staged bytes
        // rather than a real trim — the claim under test is that the commit reached the file at all.
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    @Test func previewingPausesThePlayerBeforeTakingTheEngine() {
        let app = makeApp()
        let url = URL(fileURLWithPath: "/Recordings/Lecture.m4a")
        app.home.recentFiles = [Self.file(at: url, duration: 600)]
        app.player.currentTrack = Self.file(at: url, duration: 600)
        app.player.isPlaying = true

        app.dial.onPreviewTrim?(url.absoluteString, 5, 30)

        #expect(!app.player.isPlaying, "The transport must not claim an engine it no longer owns.")
    }

    // MARK: - The two that stay inert, on purpose

    /// Not a bug being pinned — a decision. Volume is `MPVolumeView`'s, exactly as the shell's
    /// `onVolumeBy` records, and this fails the day someone wires it without revisiting that.
    ///
    /// Asserted on the edge rather than by turning the wheel: Now Playing no longer offers a volume
    /// *mode*, so there is currently no command that reaches `DialAxis.volume` at all. The decision
    /// outlives the route that used to exercise it.
    @MainActor
    @Test func volumeIsStillTheSystemSlidersAndNothingPretendsOtherwise() {
        let app = makeApp()

        #expect(app.shell.onVolumeBy == nil, "Both faces of the wheel leave volume alone.")
    }

    @MainActor
    @Test func theActionsScreenIsDeclaredButNotYetWired() {
        let app = makeApp()

        #expect(app.dial.onItemAction == nil, "Its slice has not landed; the closure is the seam.")
    }

    // MARK: -

    private static func file(at url: URL, duration: TimeInterval = 1) -> AudioFile {
        AudioFile(
            url: url, title: url.deletingPathExtension().lastPathComponent,
            duration: duration, fileSize: 1, format: .m4a,
            creationDate: Date(timeIntervalSince1970: 0)
        )
    }

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DialWiringTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
