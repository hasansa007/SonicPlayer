import Foundation
import Testing

@testable import SonicPlayer

/// The eight screens of the design, produced as values (#6).
///
/// **This is the acceptance test for the whole navigator.** Every screen in the spec — 1a to 1h —
/// has to be reachable by commands alone, and has to come out with the header, rows, ring, hub and
/// caption the design asks for. Nothing here renders anything; a `DialScreen` *is* the screen, and
/// checking it is checking the design.
@Suite
struct DialScreenshotTests {

    private func rows(_ navigator: DialNavigator) -> DialScreen.List? {
        guard case .list(let list) = navigator.screen.content else {
            Issue.record("expected a list, got \(navigator.screen.content)")
            return nil
        }
        return list
    }

    // MARK: - 1a Library home


    // MARK: - 1b Recordings

    @Test func recordings() {
        let navigator = DialSample.inRecordings()
        let screen = navigator.screen

        #expect(screen.chrome.breadcrumb == ["LIBRARY"])
        // The list is only its contents: Import is pinned above it, so row 0 is a file.
        #expect(rows(navigator)?.rows.first?.trailing == "01:00")
        #expect(rows(navigator)?.rows.first?.subtitle == "Today 14:02 · 2 markers")
        #expect(rows(navigator)?.rows.dropFirst().first?.subtitle == nil)
        #expect(screen.actions.map(\.id) == ["back", "record", "import", "newFolder", "sort", "settings"])
        // **All four nudges, and no mode deciding which.** Up was absent in Listen and Rename in
        // Record; the fork is gone, so every verb a file answers is here, always.
        #expect(screen.ring.directions?.up?.id == "edit")
        #expect(screen.ring.directions?.down?.id == "delete")
        #expect(screen.ring.directions?.left?.id == "move")
        #expect(screen.ring.directions?.right?.id == "share")
        #expect(!screen.chrome.canGoBack, "the library is the root now")
        #expect(screen.actions.map(\.id) == ["back", "record", "import", "newFolder", "sort", "settings"])
        #expect(screen.ring.hub == .label("PLAY"))
        // **The nudge clause has gone out of the caption and onto the stick.** It named the same
        // four things `ring.directions` names, one line of prose away from them, so the sentence
        // and the control could disagree — and it was permanent text describing gestures nobody
        // was making while they read it.
        #expect(screen.hint == "rotate to scroll · press to play")
    }

    // MARK: - 1c Now playing

    @Test func nowPlaying() {
        var navigator = DialSample.navigator()
        _ = navigator.receive(.hold)
        let screen = navigator.screen

        guard case .nowPlaying(let playing) = screen.content else {
            Issue.record("expected the now playing screen")
            return
        }
        #expect(playing.title == "Deep Work, Chapter 4")
        #expect(playing.subtitle == "Cal Newport")
        #expect(playing.elapsed == "20:34")
        #expect(playing.remaining == "−25:11")
        #expect(abs(playing.progress - 1234.0 / 2745.0) < 1e-9)
        #expect(playing.isPlaying)

        // The screen owns the transport, so the chrome does not repeat it.
        #expect(screen.chrome.status == nil)
        // No mode row: volume and track-stepping are on the stick. What is here is the way out
        // and the two queue toggles, which were a bar inside the card until the card lost its bar.
        #expect(screen.actions.map(\.id) == ["back", "repeat", "shuffle", "settings"])
        #expect(screen.chrome.canGoBack)
        // Every *verb* the row held moved onto the stick's four nudges.
        #expect(screen.ring.directions?.up?.id == "volumeUp")
        #expect(screen.ring.directions?.down?.id == "volumeDown")
        #expect(screen.ring.directions?.left?.id == "previous")
        #expect(screen.ring.directions?.right?.id == "next")
        #expect(screen.ring.isLive, "the border moves while audio moves")
        #expect(screen.ring.hub == .glyph("pause.fill"))
        #expect(screen.hint == "rotate to seek · press to pause")
    }

    // MARK: - 1d Recording

    @Test func recording() {
        let navigator = DialSample.whileRecording()
        let screen = navigator.screen

        guard case .recording(let capture) = screen.content else {
            Issue.record("expected the recording screen")
            return
        }
        #expect(capture.elapsed == "12:07")
        #expect(capture.fraction == "4")
        #expect(capture.levels == [0.2, 0.5, 0.8, 0.42])
        #expect(capture.markers.map(\.time) == ["01:02"])

        #expect(screen.chrome.isRecording)
        #expect(screen.chrome.status == nil)
        // Marker and Pause moved onto the stick, up and left — so the row holds only the way out.
        #expect(screen.actions.map(\.id) == ["back", "settings"])
        #expect(screen.ring.directions?.up?.id == "marker")
        #expect(screen.ring.directions?.left?.id == "pause")
        #expect(screen.ring.isLive, "the border moves while a take is running")
        #expect(screen.ring.ticks == .level(0.42))
        #expect(screen.ring.hub == .recordDot)
        #expect(screen.hint == "ring shows input level · rotate to set gain · press to stop")
    }

    // MARK: - 1e Edit

    @Test func edit() {
        let navigator = DialSample.whileEditing()
        let screen = navigator.screen

        guard case .edit(let edit) = screen.content else {
            Issue.record("expected the editor")
            return
        }
        #expect(edit.title == "Recording 1")
        #expect(edit.keeping == "10:00")
        #expect(edit.waveform == [0.1, 0.9, 0.4, 0.7])
        #expect(edit.inFraction == 0)
        #expect(edit.outFraction == 1)
        #expect(edit.scale == ["00:00", "00:00", "10:00", "10:00"])

        #expect(screen.chrome.breadcrumb == ["LIBRARY", "EDIT"])
        // The handles are chosen by tapping them and everything else the editor does is a nudge,
        // so the row holds only the way out.
        #expect(screen.actions.map(\.id) == ["back", "settings"])
        #expect(edit.activeHandle == .start)
        #expect(edit.operation == .keep)
        #expect(screen.ring.hub == .label("DONE"))
        // The editor's caption was three clauses, two of them naming directions — instructions
        // rather than a caption. Keep, Delete and Preview are the stick's own names now.
        #expect(screen.hint == "rotate to move the handle · press to trim to the selection")
    }

    // MARK: - 1f The four nudges that replaced the actions menu

    /// **There is no actions screen.** Its five rows were reached by a `···` nudge, a turn and a
    /// press — three gestures for one verb, and a whole route to hold them. Four fit the four
    /// directions the stick already has; `Rename` moved onto the edit screen.
    /// **The stick is where the split is most visible.** There is no mode indicator anywhere, so
    /// which verbs the stick offers is how you tell which side of the fork you took.

    // MARK: - 1g Empty

    @Test func emptyRecordings() {
        let navigator = DialSample.navigator(recordingCount: 0)
        let screen = navigator.screen

        // **An empty library is a message.** It was the Import row alone, whose second line carried
        // the explanation — which worked exactly as long as Import was a row. Both verbs are chips
        // now and chips have no subtitle, so the sentence that was the empty state *is* the empty
        // state.
        guard case .message(let message) = screen.content else {
            Issue.record("expected the empty message, got \(screen.content)")
            return
        }
        #expect(message.title == "Nothing here yet")
        #expect(message.body == "Record a take, or import audio from Files — both are below the card.")

        #expect(screen.chrome.breadcrumb == ["LIBRARY"])
        // **The row is unchanged by the list being empty**, which is the point of it being a row
        // rather than a pinned element: nothing appears or disappears with the contents.
        #expect(screen.actions.map(\.id) == ["back", "record", "import", "newFolder", "sort", "settings"])
        #expect(!screen.chrome.canGoBack, "the library is the root")
        #expect(screen.ring.hub == .label("BACK"), "an empty list opens on the first chip")
    }

    // MARK: - 1h Listen vs record


    // MARK: - Data that changes under a screen

    /// The contract promises `highlighted` is always valid when `rows` is non-empty, so a list that
    /// shrinks under a highlight near its end must not hand the UI an out-of-range index.
    @Test func aShrinkingListPullsTheHighlightBackIntoRange() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.tick(11))            // the last recording, row 11

        navigator.update(DialSample.content(recordingCount: 3))

        #expect(rows(navigator)?.highlighted == 2, "three files is three rows")
    }

    /// A library that empties has no rows left at all, and says why rather than going blank.
    @Test func aListThatEmptiesSaysSo() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.tick(5))

        navigator.update(DialSample.content(recordingCount: 0))

        guard case .message(let message) = navigator.screen.content else {
            Issue.record("expected the empty message, got \(navigator.screen.content)")
            return
        }
        #expect(message.title == "Nothing here yet")
    }
}
