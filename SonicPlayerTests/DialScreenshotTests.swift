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

        #expect(screen.chrome.breadcrumb == ["LIBRARY"])
        #expect(screen.chrome.status == "20:34 ▸ playing")
        #expect(rows(navigator)?.rows.map(\.title) == [
            "Playlists", "Recordings", "Focus Sessions", "Podcasts", "Stats"
        ])
        // The chevron is the affordance, and only Recordings has somewhere to go.
        #expect(rows(navigator)?.rows.map(\.trailing) == ["6", "12 ▸", "24", "9", nil])
        #expect(rows(navigator)?.position == nil)
        #expect(screen.ring.hub == .label("OPEN"))
        #expect(screen.hint == "rotate to browse · press to open · hold for now playing")
    }

    // MARK: - 1b Recordings

    @Test func recordings() {
        let navigator = DialSample.inRecordings()
        let screen = navigator.screen

        #expect(screen.chrome.breadcrumb == ["LIBRARY", "RECORDINGS"])
        #expect(rows(navigator)?.position == "1 of 12")
        #expect(rows(navigator)?.rows.first?.trailing == "01:00")
        #expect(rows(navigator)?.rows.first?.subtitle == "Today 14:02 · 2 markers")
        #expect(rows(navigator)?.rows.dropFirst().first?.subtitle == nil)
        // Back moved to the top bar — it is navigation, not one of the things this screen does.
        #expect(screen.actions.map(\.id) == ["edit", "more"])
        #expect(screen.chrome.canGoBack)
        #expect(screen.ring.hub == .label("OPEN"))
        #expect(screen.hint == "rotate to scroll · press to open · double-press to edit")
    }

    @Test func theCountedPositionFollowsTheHighlight() {
        var navigator = DialSample.inRecordings()

        _ = navigator.receive(.tick(6))

        #expect(rows(navigator)?.position == "7 of 12")
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
        #expect(screen.ring.volume != nil, "the volume segment needs its level")
        #expect(screen.ring.showsTrackStepper, "a queue of more than one gets the track segment")
        #expect(screen.ring.hub == .glyph("pause.fill"))
        #expect(screen.hint == "rotate to seek · press to pause · slide to change track")
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
        #expect(screen.actions.map(\.label) == ["＋ Marker", "Pause"])
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

        #expect(screen.chrome.breadcrumb == ["LIBRARY", "RECORDINGS", "EDIT"])
        #expect(screen.actions.map(\.label) == ["Start handle", "End handle", "Preview"])
        #expect(screen.ring.hub == .label("DONE"))
        #expect(screen.hint == "rotate to nudge the active handle · press when done")
    }

    // MARK: - 1f Item actions

    @Test func itemActions() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.action("more"))
        let screen = navigator.screen

        #expect(rows(navigator)?.rows.map(\.title) == [
            "Share file…", "Add to playlist", "Export as MP3", "Rename", "Delete"
        ])
        #expect(rows(navigator)?.position == "1 of 5")
        #expect(screen.chrome.breadcrumb == ["LIBRARY", "RECORDINGS", "RECORDING 1"])
        #expect(screen.ring.hub == .label("SELECT"))
        #expect(screen.hint == "rotate to highlight an action · press to confirm")

        // Without a subject this screen is five verbs and no object — "Delete" with nothing saying
        // what. The breadcrumb names it in shouting caps; the header names it as the file is named.
        #expect(rows(navigator)?.subject?.title == "Recording 1")
        #expect(rows(navigator)?.subject?.icon == .recording)

        // Export gets its own glyph. Reusing `.share` would put one symbol on two rows of the five
        // above and read as a bug rather than as a pair.
        #expect(rows(navigator)?.rows.map(\.icon) == [.share, .playlist, .export, .rename, .delete])
    }

    // MARK: - 1g Empty

    @Test func emptyRecordings() {
        var navigator = DialSample.navigator(recordingCount: 0)
        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)
        let screen = navigator.screen

        guard case .message(let message) = screen.content else {
            Issue.record("expected the empty state, got \(screen.content)")
            return
        }
        #expect(message.icon == .recording)
        #expect(message.title == "No recordings yet")

        #expect(screen.chrome.breadcrumb == ["LIBRARY", "RECORDINGS"])
        #expect(screen.actions.map(\.id) == ["record"])
        #expect(screen.chrome.canGoBack)
        // Destructive, not primary. It is the obvious action on this screen *and* the one you
        // cannot casually undo, and the design draws it red for that reason — `.primary` renders
        // in the accent, which would make starting a recording look like opening a playlist.
        #expect(screen.actions.last?.emphasis == .destructive)
        #expect(screen.ring.hub == .label("RECORD"))
        #expect(screen.hint == "press to start recording · nothing to scroll yet")
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

        #expect(navigator.screen.chrome.breadcrumb == ["LIBRARY"])
    }

    // MARK: - Data that changes under a screen

    /// The contract promises `highlighted` is always valid when `rows` is non-empty, so a list that
    /// shrinks under a highlight near its end must not hand the UI an out-of-range index.
    @Test func aShrinkingListPullsTheHighlightBackIntoRange() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.tick(11))

        navigator.update(DialSample.content(recordingCount: 3))

        #expect(rows(navigator)?.highlighted == 2)
        #expect(rows(navigator)?.position == "3 of 3")
    }

    @Test func aListThatEmptiesFallsBackToTheEmptyState() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.tick(5))

        navigator.update(DialSample.content(recordingCount: 0))

        guard case .message = navigator.screen.content else {
            Issue.record("expected the empty state, got \(navigator.screen.content)")
            return
        }
        #expect(navigator.screen.ring.hub == .label("RECORD"))
    }
}
