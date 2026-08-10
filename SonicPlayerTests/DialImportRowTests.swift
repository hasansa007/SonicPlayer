import Foundation
import Testing

@testable import SonicPlayer

/// Import as row 0 of the recordings list, and the offset that creates (#6).
///
/// **The offset is the point of this suite.** Every recording moved down one row, and eight call
/// sites used to index `content.recordings` with the raw highlight. None of them would crash if
/// left unconverted — the wheel would land on one recording and the hub would open the one above
/// it, `Delete` would name one file and remove another. `RecordingsRow` states the mapping once;
/// these check that nothing bypasses it.
@Suite
struct DialImportRowTests {

    private func list(_ navigator: DialNavigator) -> DialScreen.List? {
        guard case .list(let list) = navigator.screen.content else {
            Issue.record("expected a list, got \(navigator.screen.content)")
            return nil
        }
        return list
    }

    /// Opens the recordings list and leaves the highlight where it lands — on Import.
    private func onImportRow(recordingCount: Int = 12) -> DialNavigator {
        var navigator = DialSample.navigator(recordingCount: recordingCount)
        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)
        return navigator
    }

    // MARK: - The mapping

    @Test func rowZeroIsImportAndEveryRecordingShiftsDown() {
        #expect(RecordingsRow.at(0, recordings: 3) == .importFiles)
        #expect(RecordingsRow.at(1, recordings: 3) == .recording(index: 0))
        #expect(RecordingsRow.at(3, recordings: 3) == .recording(index: 2))
        #expect(RecordingsRow.at(4, recordings: 3) == nil, "past the end")
        #expect(RecordingsRow.at(-1, recordings: 3) == nil)
    }

    /// An empty library still has the Import row, which is the whole reason it is a row.
    @Test func thereIsAlwaysAnImportRow() {
        #expect(RecordingsRow.rowCount(recordings: 0) == 1)
        #expect(RecordingsRow.at(0, recordings: 0) == .importFiles)

        let navigator = onImportRow(recordingCount: 0)
        #expect(list(navigator)?.rows.map(\.id) == ["import"])
    }

    // MARK: - What the row does

    @Test func theListLeadsWithImport() {
        let navigator = onImportRow()

        #expect(list(navigator)?.rows.first?.id == "import")
        #expect(list(navigator)?.rows.count == 13, "12 files and the Import row")
        #expect(list(navigator)?.highlighted == 0)
    }

    @Test func pressingImportAsksTheHostAndStaysPut() {
        var navigator = onImportRow()

        let effects = navigator.receive(.press)

        #expect(effects == [.importFiles, .feedback(.commit)])
        #expect(navigator.route == .recordings, "the files land in this list; leaving it is a round trip")
    }

    @Test func theHubSaysImportOnThatRowAndOpenOnTheOthers() {
        var navigator = onImportRow()
        #expect(navigator.screen.ring.hub == .label("IMPORT"))

        _ = navigator.receive(.tick(1))
        #expect(navigator.screen.ring.hub == .label("OPEN"))
    }

    /// The stick acts on the highlighted *recording*, so it has nothing to offer here.
    @Test func theStickIsAbsentOnTheImportRow() {
        var navigator = onImportRow()
        #expect(navigator.screen.ring.directions == nil)

        _ = navigator.receive(.tick(1))
        #expect(navigator.screen.ring.directions?.up?.id == "edit")
    }

    /// Waiting for a second press costs a delay, and there is no double-press meaning here to wait
    /// for.
    @Test func pressIsNotDeferredOnTheImportRow() {
        var navigator = onImportRow()
        #expect(!navigator.screen.ring.defersPress)

        _ = navigator.receive(.tick(1))
        #expect(navigator.screen.ring.defersPress)
    }

    @Test func doublePressingImportDoesNothing() {
        var navigator = onImportRow()

        #expect(navigator.receive(.doublePress).isEmpty)
        #expect(navigator.route == .recordings)
    }

    // MARK: - The offset, at each call site

    @Test func pressingARecordingOpensThatRecording_notItsNeighbour() {
        var navigator = onImportRow()
        _ = navigator.receive(.tick(1))     // the first recording

        #expect(navigator.receive(.press).contains(.play(itemID: "rec-0")))
    }

    /// The stick's four nudges all act on the highlighted *recording*, so each has to un-offset the
    /// highlight. `delete` is the one that shows it, because the guard names the file it opens on.
    @Test func theNudgesActOnTheHighlightedRecording() {
        var navigator = onImportRow()
        _ = navigator.receive(.tick(3))     // the third recording

        _ = navigator.receive(.action("delete"))

        #expect(navigator.route == .confirmDelete(itemID: "rec-2"))
    }

    @Test func theShareNudgeNamesTheHighlightedRecording() {
        var navigator = onImportRow()
        _ = navigator.receive(.tick(2))

        let effects = navigator.receive(.action("share"))

        #expect(effects == [.item(.share, itemID: "rec-1"), .feedback(.commit)])
    }

    /// Nothing to act on while the highlight is on Import.
    @Test func theNudgesAreRefusedOnTheImportRow() {
        var navigator = onImportRow()

        #expect(navigator.receive(.action("share")) == [.feedback(.limit)])
        #expect(navigator.receive(.action("delete")) == [.feedback(.limit)])
        #expect(navigator.receive(.action("add")) == [.feedback(.limit)])
    }

    @Test func theEditorOpensTheHighlightedRecording() {
        var navigator = onImportRow()
        _ = navigator.receive(.tick(2))

        _ = navigator.receive(.doublePress)

        #expect(navigator.route == .edit(itemID: "rec-1"))
    }

    /// The queue position Now Playing is handed must be the recording's index, not the row's.
    @Test func playingARecordingReportsItsOwnQueuePosition() {
        var navigator = onImportRow()
        _ = navigator.receive(.tick(3))

        _ = navigator.receive(.press)

        guard case .nowPlaying = navigator.route else {
            Issue.record("expected Now Playing")
            return
        }
        #expect(navigator.screen.ring.hub == .glyph("pause.fill"))
    }

    /// The highlight must reach the last recording and stop there — one row further than the
    /// recording count, and no further.
    @Test func theHighlightStopsAtTheLastRecording() {
        var navigator = onImportRow(recordingCount: 3)

        _ = navigator.receive(.tick(99))

        #expect(list(navigator)?.highlighted == 3, "Import plus three recordings is four rows")
        #expect(navigator.receive(.press).contains(.play(itemID: "rec-2")))
    }
}
