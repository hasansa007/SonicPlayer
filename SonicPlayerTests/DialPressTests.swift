import Foundation
import Testing

@testable import SonicPlayer

/// One hub, eight meanings (#6).
///
/// There is only one button, so what it does has to come from where you are. These are that table.
@Suite
struct DialPressTests {

    // `#expect` captures its expression in a closure, so a `mutating` call written inside one fails
    // to compile against an immutable copy. Every result below is bound to a local first.

    @Test func pressingASectionOpensIt() {
        var navigator = DialSample.navigator()
        _ = navigator.receive(.tick(1))

        let effects = navigator.receive(.press)

        #expect(effects == [.feedback(.commit)])
        #expect(navigator.route == .recordings)
    }

    @Test func pressingARecordingPlaysItAndOpensNowPlaying() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.tick(2))

        let effects = navigator.receive(.press)

        #expect(effects == [.play(itemID: "rec-2"), .feedback(.commit)])
        #expect(navigator.route == .nowPlaying)
    }

    /// The pushed screen must be right on the frame it appears, not blank until the host answers.
    @Test func openingATrackFillsInNowPlayingImmediately() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.tick(2))

        _ = navigator.receive(.press)

        guard case .nowPlaying(let playing) = navigator.screen.content else {
            Issue.record("expected the now playing screen")
            return
        }
        #expect(playing.title == "Recording 3")
        #expect(playing.elapsed == "00:00")
        #expect(playing.isPlaying)
    }

    @Test func pressingOnNowPlayingPausesAndTheHubFollows() {
        var navigator = DialSample.navigator()
        _ = navigator.receive(.hold)

        let effects = navigator.receive(.press)

        #expect(effects == [.togglePlayPause, .feedback(.commit)])
        #expect(navigator.screen.ring.hub == .glyph("play.fill"))
        #expect(navigator.screen.hint.contains("press to play"))
    }

    @Test func pressingWhileRecordingStopsAndComesBack() {
        var navigator = DialSample.whileRecording()

        let effects = navigator.receive(.press)

        #expect(effects == [.stopRecording, .feedback(.commit)])
        #expect(navigator.route == .recordings)
    }

    @Test func pressingOnTheEmptyStateStartsRecording() {
        var navigator = DialSample.navigator(recordingCount: 0)
        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)          // opens the recordings list, which is empty

        let effects = navigator.receive(.press)

        #expect(effects == [.startRecording, .feedback(.commit)])
        #expect(navigator.route == .recording)
    }

    @Test func pressingOnTheEditorCommitsTheTrimAndComesBack() {
        var navigator = DialSample.whileEditing()
        _ = navigator.receive(.tick(10))       // nudge the start handle a second in

        let effects = navigator.receive(.press)

        #expect(effects == [.commitTrim(itemID: "rec-0", start: 1, end: 600), .feedback(.commit)])
        #expect(navigator.route == .recordings)
    }

    @Test func pressingAnItemActionConfirmsItAndComesBack() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.action("more"))
        _ = navigator.receive(.tick(4))        // Delete, the last row

        let effects = navigator.receive(.press)

        #expect(effects == [.item(.delete, itemID: "rec-0"), .feedback(.commit)])
        #expect(navigator.route == .recordings)
    }

    // MARK: - The fork

    @Test func choosingListenOpensTheLibrary() {
        var navigator = DialSample.navigator(root: .chooseMode)

        let effects = navigator.receive(.press)

        #expect(effects == [.feedback(.commit)])
        #expect(navigator.route == .library)
    }

    @Test func choosingRecordStartsRecording() {
        var navigator = DialSample.navigator(root: .chooseMode)
        _ = navigator.receive(.tick(1))

        let effects = navigator.receive(.press)

        #expect(effects == [.startRecording, .feedback(.commit)])
        #expect(navigator.route == .recording)
    }

    // MARK: - The chips that are not modes

    @Test func theMarkerChipAddsAMarker() {
        var navigator = DialSample.whileRecording()

        let effects = navigator.receive(.action("marker"))

        #expect(effects == [.addMarker, .feedback(.commit)])
    }

    /// Pause is a **left nudge** now rather than a chip, and it still has to say which way it will
    /// go — a control that toggles without relabelling leaves you guessing what a press will do.
    @Test func thePauseNudgeTogglesAndRelabelsItself() {
        var navigator = DialSample.whileRecording()

        let effects = navigator.receive(.action("pause"))

        #expect(effects == [.toggleRecordingPause, .feedback(.commit)])
        #expect(navigator.screen.ring.directions?.left?.label == "Resume")
        #expect(navigator.screen.ring.directions?.left?.icon == .play)
    }

    @Test func thePreviewChipIsAnActionRatherThanAMode() {
        var navigator = DialSample.whileEditing()

        let effects = navigator.receive(.action("preview"))

        // Bounded on the way out, like `commitTrim` — the selection is the whole file until a
        // handle is nudged, and `DialSample.editable` is ten minutes long.
        #expect(effects == [.previewTrim(itemID: "rec-0", start: 0, end: 600), .feedback(.commit)])
        // Preview must not steal the selection from the handle the wheel is nudging.
        #expect(navigator.axis == .trimStart)
    }

    /// Now Playing used to be three mode chips and no Back, which made the command load-bearing:
    /// without it the screen was a trap. The modes are gone and Back is now the only chip — so this
    /// pins the *reachability*, which is what mattered, rather than the absence that caused it.
    @Test func backWorksOnAScreenThatShowsNoBackChip() {
        var navigator = DialSample.navigator()
        _ = navigator.receive(.hold)
        #expect(navigator.screen.actions.isEmpty)
        #expect(navigator.screen.chrome.canGoBack, "the way out is the top bar's chevron")

        _ = navigator.receive(.action("back"))

        #expect(navigator.route == .library)
    }
}
