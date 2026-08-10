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
        // The corner is the playing label alone now — the gear went back to being a chip. The
        // label was briefly a row here instead, which could name the track and could not follow you
        // down into the library, which is the job.
        #expect(screen.chrome.status == "20:34 ▸ playing")
        // **Home is the fork, and nothing else.** It was five sections — Playlists, Recordings,
        // Focus Sessions, Podcasts, Stats — three of which never went anywhere. They are two jobs
        // now, and each opens the same library with a different set of verbs over it.
        #expect(rows(navigator)?.rows.map(\.title) == ["Listen", "Record"])
        // The count and the affordance are separate fields now. They were one string — `"12 ▸"` —
        // until the card style drew a real chevron beside it and the row read `12 ▸ ›`.
        #expect(rows(navigator)?.rows.map(\.trailing) == ["12", nil])
        #expect(rows(navigator)?.rows.map(\.opensSomewhere) == [true, true])
        #expect(screen.actions.map(\.id) == ["settings"], "and it is this screen's leading stop")
        #expect(screen.ring.hub == .label("OPEN"))
        #expect(screen.hint == "rotate to browse · press to open · hold for now playing")
    }

    // MARK: - 1b Recordings

    @Test func recordings() {
        let navigator = DialSample.inRecordings()
        let screen = navigator.screen

        #expect(screen.chrome.breadcrumb == ["HOME", "LIBRARY"])
        // The list is only its contents: Import is pinned above it, so row 0 is a file.
        #expect(rows(navigator)?.rows.first?.trailing == "01:00")
        #expect(rows(navigator)?.rows.first?.subtitle == "Today 14:02 · 2 markers")
        #expect(rows(navigator)?.rows.dropFirst().first?.subtitle == nil)
        #expect(screen.actions.map(\.id) == ["back", "newFolder", "sort"])
        // **This is Listen, so the destructive nudges are not here at all.** They used to be on
        // every library: up edited, down deleted. Both belong to Record now, which is the point of
        // having modes — the side you can lose something on is the side you have to choose.
        #expect(screen.ring.directions?.up == nil)
        #expect(screen.ring.directions?.down == nil)
        #expect(screen.ring.directions?.left?.id == "add")
        #expect(screen.ring.directions?.right?.id == "share")
        #expect(screen.chrome.canGoBack)
        #expect(screen.chrome.primaryAction?.id == "import", "pinned above the list, and a stop")
        #expect(screen.ring.hub == .label("PLAY"))
        #expect(screen.hint == "rotate to scroll · press to play · nudge to add to a playlist or share")
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
        #expect(screen.actions.map(\.id) == ["back", "repeat", "shuffle"])
        #expect(screen.chrome.canGoBack)
        // Every *verb* the row held moved onto the stick's four nudges.
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
        // Marker and Pause moved onto the stick, up and left — so the row holds only the way out.
        #expect(screen.actions.map(\.id) == ["back"])
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
        // The handles are chosen by tapping them and everything else the editor does is a nudge,
        // so the row holds only the way out.
        #expect(screen.actions.map(\.id) == ["back"])
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
    /// **The stick is where the split is most visible.** There is no mode indicator anywhere, so
    /// which verbs the stick offers is how you tell which side of the fork you took.
    @Test func theStickCarriesTheModesVerbs() {
        let listening = DialSample.inRecordings().screen.ring.directions
        #expect(listening?.left?.id == "add")
        #expect(listening?.right?.id == "share")
        #expect(listening?.up == nil, "nothing in Listen edits")
        #expect(listening?.down == nil, "and nothing in Listen destroys")

        let directions = DialSample.inRecordMode().screen.ring.directions
        #expect(directions?.up?.id == "rename")
        #expect(directions?.down?.id == "delete")
        #expect(directions?.right?.id == "share")
        // **Left is Move, and it is the direction that stayed empty longest.** Listen files things
        // into playlists with `add`; Record files the recording itself into a folder. Same corner,
        // same idea, and neither is the other's verb.
        #expect(directions?.left?.id == "move", "filing a recording is Record's, not Listen's")

        // A nudge has no room for a word, so the glyph is the whole label.
        #expect(directions?.up?.icon == .rename)
        #expect(directions?.down?.icon == .delete)
        #expect(listening?.left?.icon == .playlist)
        #expect(directions?.right?.icon == .share)
    }

    // MARK: - 1g Empty

    @Test func emptyRecordings() {
        var navigator = DialSample.navigator(recordingCount: 0)
        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)
        let screen = navigator.screen

        // **An empty library is a message again.** It was the Import row alone, whose second line
        // carried the explanation — which worked exactly as long as Import was a row. With the verb
        // pinned above the list, a list with nothing in it has nothing to say for itself.
        //
        // This enters through home's second row, so it is **Record** mode, and the message is that
        // mode's — an empty library reached by way of "I want to record" should not open by
        // offering to import.
        guard case .message(let message) = screen.content else {
            Issue.record("expected the empty message, got \(screen.content)")
            return
        }
        #expect(message.title == "Nothing here yet")
        #expect(message.body == "Press the wheel to start recording.")
        #expect(navigator.isPinnedActionHighlighted, "and the wheel is already resting on it")
        #expect(screen.chrome.primaryAction?.id == "record")

        #expect(screen.chrome.breadcrumb == ["HOME", "LIBRARY"])
        // **No Record chip.** A red one used to sit in this row, appearing only when the library
        // was empty — which read as an alert rather than an offer. Recording is a mode on home, and
        // its verb is pinned above the list. What is here organises the list rather than adding to
        // it, which is why it survives an empty one.
        #expect(screen.actions.map(\.id) == ["back", "newFolder", "sort"])
        #expect(screen.chrome.canGoBack)
        #expect(screen.ring.hub == .label("RECORD"), "the hub names the row it is resting on")
        #expect(screen.hint == "nothing recorded yet · press to start one")
    }

    // MARK: - 1h Listen vs record

    /// **The fork is home**, not a screen in front of it.
    @Test func listenOrRecord() {
        let navigator = DialSample.navigator()
        let screen = navigator.screen

        #expect(rows(navigator)?.rows.map(\.title) == ["Listen", "Record"])
        #expect(rows(navigator)?.rows.map(\.subtitle) == [
            "Play, import, make playlists",
            "Capture, trim, rename, delete"
        ], "the only place the split is spelled out")
        #expect(screen.chrome.breadcrumb == ["HOME"])
        // Home is the root, so there is no way back — Settings is the whole row, and it is also
        // this screen's leading ring stop.
        #expect(screen.actions.map(\.id) == ["settings"])
        #expect(screen.ring.hub == .label("OPEN"))
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
