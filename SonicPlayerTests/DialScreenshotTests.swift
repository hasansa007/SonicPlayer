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

    @Test func libraryHome() {
        let navigator = DialSample.navigator()
        let screen = navigator.screen

        #expect(screen.chrome.breadcrumb == ["HOME"])
        // The gear and the label share the corner. The label was briefly a row here instead, which
        // could name the track — and could not follow you down into the library, which is the job.
        #expect(screen.chrome.status == "20:34 ▸ playing")
        #expect(rows(navigator)?.rows.map(\.title) == [
            "Playlists", "Recordings", "Focus Sessions", "Podcasts", "Stats"
        ])
        // The count and the affordance are separate fields now. They were one string — `"12 ▸"` —
        // until the card style drew a real chevron beside it and the row read `12 ▸ ›`.
        #expect(rows(navigator)?.rows.map(\.trailing) == ["6", "12", "24", "9", nil])
        #expect(rows(navigator)?.rows.map(\.opensSomewhere) == [false, true, false, false, false])
        #expect(screen.ring.hub == .label("OPEN"))
        #expect(screen.hint == "rotate to browse · press to open · hold for now playing")
    }

    // MARK: - 1b Recordings

    @Test func recordings() {
        let navigator = DialSample.inRecordings()
        let screen = navigator.screen

        #expect(screen.chrome.breadcrumb == ["HOME", "LIBRARY"])
        // The list is only its contents: Import and New folder are bar buttons, so row 0 is a file.
        #expect(rows(navigator)?.rows.first?.trailing == "01:00")
        #expect(rows(navigator)?.rows.first?.subtitle == "Today 14:02 · 2 markers")
        #expect(rows(navigator)?.rows.dropFirst().first?.subtitle == nil)
        // Back moved to the top bar. Edit came off the stick's right nudge and into the actions
        // menu as its top row, leaving one nudge — upward, because a lone sideways one on a
        // four-way stick reads as though the others are broken.
        #expect(screen.actions.isEmpty)
        #expect(screen.ring.directions?.up?.id == "edit")
        #expect(screen.ring.directions?.down?.id == "delete")
        #expect(screen.ring.directions?.left?.id == "add")
        #expect(screen.ring.directions?.right?.id == "share")
        #expect(screen.chrome.canGoBack)
        #expect(screen.ring.hub == .label("OPEN"))
        #expect(screen.hint == "rotate to scroll · press to open · double-press to edit")
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
        // No mode row: volume and track-stepping have their own controls beside the wheel, so the
        // only chip left is the way out.
        #expect(screen.actions.isEmpty, "the wheel seeks, the segments do the rest, Back is chrome")
        #expect(screen.chrome.canGoBack)
        // The chip row is gone: every action it held moved onto the stick's four nudges.
        #expect(screen.ring.directions?.up?.id == "volumeUp")
        #expect(screen.ring.directions?.down?.id == "volumeDown")
        #expect(screen.ring.directions?.left?.id == "previous")
        #expect(screen.ring.directions?.right?.id == "next")
        #expect(screen.ring.isLive, "the border moves while audio moves")
        #expect(screen.ring.hub == .glyph("pause.fill"))
        // The hint is no longer drawn — it is the dial's accessibility hint now — but it is still
        // produced, and it is still what a VoiceOver user is told.
        #expect(screen.hint == "rotate to seek · press to pause · nudge for track and volume")
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
        // The chip row is gone: both actions moved onto the stick, up and left.
        #expect(screen.actions.isEmpty)
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

        #expect(screen.chrome.breadcrumb == ["HOME", "LIBRARY", "EDIT"])
        // No chips. The handles are chosen by tapping them, and everything the editor can do is a
        // nudge — so the action row has nothing left to hold.
        #expect(screen.actions.isEmpty)
        #expect(edit.activeHandle == .start)
        #expect(edit.operation == .keep)
        #expect(screen.ring.hub == .label("DONE"))
        #expect(
            screen.hint
                == "press to trim to the selection · down to delete it instead · right to hear it"
        )
    }

    // MARK: - 1f The four nudges that replaced the actions menu

    /// **There is no actions screen.** Its five rows were reached by a `···` nudge, a turn and a
    /// press — three gestures for one verb, and a whole route to hold them. Four fit the four
    /// directions the stick already has; `Rename` moved onto the edit screen.
    @Test func theStickCarriesTheFourItemActions() {
        let navigator = DialSample.inRecordings()
        let directions = navigator.screen.ring.directions

        #expect(directions?.up?.id == "edit")
        #expect(directions?.down?.id == "delete")
        #expect(directions?.left?.id == "add")
        #expect(directions?.right?.id == "share")

        // A nudge has no room for a word, so the glyph is the whole label.
        #expect(directions?.up?.icon == .edit)
        #expect(directions?.down?.icon == .delete)
        #expect(directions?.left?.icon == .playlist)
        #expect(directions?.right?.icon == .share)
    }

    // MARK: - 1g Empty

    @Test func emptyRecordings() {
        var navigator = DialSample.navigator(recordingCount: 0)
        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)
        let screen = navigator.screen

        // **An empty library is a message again.** It was the Import row alone, whose second line
        // carried the explanation — which worked exactly as long as Import was a row. With the
        // verbs in the bottom bar, a list with nothing in it has nothing to say for itself.
        guard case .message(let message) = screen.content else {
            Issue.record("expected the empty message, got \(screen.content)")
            return
        }
        #expect(message.title == "Nothing here yet")
        #expect(message.body == "Import audio or make a folder using the buttons below.")
        #expect(screen.chrome.showsLibraryActions, "and the buttons it points at are there")

        #expect(screen.chrome.breadcrumb == ["HOME", "LIBRARY"])
        // **No chips at all.** A red `Record` used to sit in that band; it is dead space on every
        // other screen, and one lone control appearing there only when the library was empty read
        // as an alert. Recording is a card on home.
        #expect(screen.actions.isEmpty)
        #expect(screen.chrome.canGoBack)
        #expect(screen.ring.hub == .label("OPEN"), "nothing to open, but the verb has not changed")
        #expect(screen.hint == "nothing here yet · import or make a folder below")
    }

    // MARK: - 1h Listen vs record

    @Test func listenOrRecord() {
        let navigator = DialSample.navigator(root: .chooseMode)
        let screen = navigator.screen

        #expect(rows(navigator)?.rows.map(\.title) == ["Listen", "Record"])
        // A fork is not a place, and `DialScreen.Chrome` says an empty breadcrumb is valid.
        #expect(screen.chrome.breadcrumb.isEmpty)
        #expect(screen.actions.isEmpty)
        #expect(screen.ring.hub == .label("CHOOSE"))
        #expect(screen.hint == "rotate to switch mode · press to choose")
    }

    /// The fork is a root, not a level you fall back through — pressing Listen has to leave a
    /// breadcrumb that starts at the library rather than at nothing.
    @Test func theForkContributesNoCrumb() {
        var navigator = DialSample.navigator(root: .chooseMode)

        _ = navigator.receive(.press)

        #expect(navigator.screen.chrome.breadcrumb == ["HOME"])
    }

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
