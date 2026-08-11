import Foundation
import Testing

@testable import SonicPlayer

/// Guards the one behavioural claim made by #10, at the seam that owns it after #17.
///
/// Before #10, `AppFeature` dismissed the recording sheet only when
/// `state.recording.editRecording == nil` — a guard that was always true, because the only action
/// that could have falsified it was never sent by any view. Collapsing it to an unconditional
/// dismiss was therefore behaviour-preserving, and this pins the result so no future change
/// quietly reintroduces a path where saving a recording leaves the sheet open.
///
/// #17 moved where that is observable. The reducer no longer has a `.recording` case at all;
/// `RecordingViewModel` calls `onFinished()` and `AppView` turns that into
/// `.dismissRecordingSheet`. So the claim is now "the view model always reports finishing" —
/// same guarantee, one layer down, and testable without a `TestStore`.
///
/// Deliberately no `import ComposableArchitecture`.
@Suite(.serialized)
struct RecordingSaveDismissTests {

    @MainActor
    @Test func test_saving_reportsFinished() async {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = Self.makeModel()
        // saveRecording moves the edited temp file to its final home, so it has to exist.
        let editURL = dir.appendingPathComponent("edit-\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: editURL.path, contents: Data([0x00]))
        model.currentRecordingURL = dir.appendingPathComponent("raw.m4a")
        model.saveFileName = "Verify \(UUID().uuidString.prefix(8))"
        model.inlineEdit = EditRecordingViewModel(
            recording: Self.file(at: editURL), audioPlayer: Self.player(), fileManager: .test
        )

        await withCheckedContinuation { continuation in
            model.onFinished = { continuation.resume() }
            model.saveRecording()
        }

        #expect(!model.isSaveFlowPresented, "Saving must always close the save flow.")
        #expect(model.inlineEdit == nil)
        #expect(model.currentRecordingURL == nil)
    }

    @MainActor
    @Test func test_discarding_reportsFinished() async {
        let model = Self.makeModel()
        model.currentRecordingURL = URL(fileURLWithPath: "/tmp/does-not-exist.m4a")
        model.isSaveFlowPresented = true

        await withCheckedContinuation { continuation in
            model.onFinished = { continuation.resume() }
            model.discardRecording()
        }

        #expect(!model.isSaveFlowPresented)
        #expect(model.currentRecordingURL == nil)
    }

    /// Dismissing the sheet mid-recording throws the take away. `AppFeature` used to decide this by
    /// reading `state.recording.currentRecordingURL`; it cannot see that any more, so the decision
    /// moved here and the guard has to move with it — not silently become unconditional.
    @MainActor
    @Test func test_discardIfUnsaved_withNothingInProgress_isANoOp() async {
        let model = Self.makeModel()
        var finished = false
        model.onFinished = { finished = true }

        model.discardIfUnsaved()

        #expect(!finished, "Nothing was recorded, so there is nothing to discard or report.")
    }

    @MainActor
    @Test func test_discardIfUnsaved_withARecordingInProgress_discardsIt() async {
        let model = Self.makeModel()
        model.currentRecordingURL = URL(fileURLWithPath: "/tmp/does-not-exist.m4a")

        await withCheckedContinuation { continuation in
            model.onFinished = { continuation.resume() }
            model.discardIfUnsaved()
        }

        #expect(model.currentRecordingURL == nil)
    }

    /// The level meter's cadence is the tested unit; the `Task.sleep` loop consuming it is glue and
    /// is deliberately not tested. `clock.timer(interval: .milliseconds(100))` came from swift-clocks
    /// via TCA — when that leaves at #20 there is nothing left to catch a change to this number.
    @Test func test_meterCadence_is100ms() {
        #expect(RecordingViewModel.meterInterval == .milliseconds(100))
    }

    // MARK: -

    @MainActor
    private static func makeModel() -> RecordingViewModel {
        RecordingViewModel(audioRecorder: .test, audioPlayer: player(), fileManager: .test)
    }

    /// Every closure on `.test` reports rather than silently succeeding (`TestClients.swift`).
    /// Both finishing paths stop the shared player, so `stop` is stubbed.
    private static func player() -> AudioPlayerClient {
        var client = AudioPlayerClient.test
        client.stop = {}
        return client
    }

    private static func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SonicPlayerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func file(at url: URL) -> AudioFile {
        AudioFile(url: url, title: url.deletingPathExtension().lastPathComponent,
            duration: 1, fileSize: 1, format: .m4a,
            creationDate: Date(timeIntervalSince1970: 0))
    }
}
