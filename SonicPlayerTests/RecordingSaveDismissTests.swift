import ComposableArchitecture
import Foundation
import Testing

@testable import SonicPlayer

/// Guards the one behavioural claim made by #10.
///
/// Before that change `AppFeature` dismissed the recording sheet only when
/// `state.recording.editRecording == nil`. `editRecording` was written in exactly
/// one place — the `if let audioFile` branch of `RecordingFeature.recordingSaved` —
/// and the only action carrying a non-nil `AudioFile` was `saveAndEditRecording`,
/// which no view ever sent. The live `saveRecording` path sends `.recordingSaved`
/// on both its success and failure branches, so the guard was always true.
///
/// Collapsing it to an unconditional dismiss is therefore behaviour-preserving.
/// This test pins the resulting behaviour so a future change cannot quietly
/// reintroduce a path where saving a recording leaves the sheet open.
@Suite(.serialized)
struct RecordingSaveDismissTests {

    @MainActor
    @Test func test_recordingSaved_dismissesTheRecordingSheet() async {
        let store = makeStore()

        await store.send(.recording(.recordingSaved))

        #expect(!(store.state.isRecordingSheetPresented), "Saving a recording must always dismiss the recording sheet.")
    }

    @MainActor
    @Test func test_discardRecording_dismissesTheRecordingSheet() async {
        let store = makeStore()

        await store.send(.recording(.discardRecording))

        #expect(!(store.state.isRecordingSheetPresented))
    }

    /// A non-exhaustive store focused on the sheet flag. The overrides keep the
    /// downstream `refreshFiles` / `loadRecentFiles` / `audioPlayer.stop` effects
    /// inert so the test only observes the dismissal behaviour under scrutiny.
    @MainActor
    private func makeStore() -> TestStore<AppFeature.State, AppFeature.Action> {
        var initialState = AppFeature.State()
        initialState.isRecordingSheetPresented = true

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.fileManager.listItems = { _ in [] }
            $0.audioPlayer.stop = {}
            // PlayerFeature.State holds @Shared(.fileStorage(session.json)). Without this the
            // shared value is read from and written to the real temp directory while the test
            // runs, so PlayerFeature.State compares unequal mid-assertion and TestStore reports
            // "State was not expected to change" with no visible diff.
            $0.defaultFileStorage = .inMemory
        }
        store.exhaustivity = .off
        return store
    }
}
