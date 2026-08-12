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


    @Test func pressingARecordingPlaysItAndOpensNowPlaying() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.tick(2))

        let effects = navigator.receive(.press)

        #expect(DialSample.playedID(effects) == "rec-2")
        #expect(
            DialSample.playedQueue(effects) == DialSample.recordings().map(\.id),
            "and the queue is the list on screen, in the order it is on screen"
        )
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

    /// **Stopping stays put.**
    ///
    /// It landed on the library for a while, on the reasoning that you stop a take in order to have
    /// it and the library is where it now is. True, and the wrong moment to say it: the instant a
    /// take ends is the instant you decide whether to keep it, and being thrown onto a list turns
    /// trimming or deleting it into a navigation problem instead of the next press.
    @Test func pressingWhileRecordingStopsWithoutGoingAnywhere() {
        var navigator = DialSample.whileRecording()

        let effects = navigator.receive(.press)

        #expect(effects == [.stopRecording, .feedback(.commit)])
        #expect(navigator.route == .recording)
    }

    /// **An empty library is no longer a dead end, it opens on a chip.**
    ///
    /// This asserted a refusal, from when the list was the whole ring and a library with nothing in
    /// it had nothing under the hub. The chips are stops, so a library with no rows still has five
    /// positions and the screen opens on the first of them — which, now that Back is not drawn at
    /// the root, is Record: the first thing there is to do about a library with nothing in it.
    @Test func pressingOnTheEmptyLibraryReachesAChipRatherThanRefusing() {
        var navigator = DialSample.navigator(recordingCount: 0)

        let effects = navigator.receive(.press)

        #expect(effects.last == .feedback(.commit))
        #expect(navigator.route == .recording, "the recorder, opened but not started")
    }

    /// **Arriving is not starting.** The bar's Record button opens the recorder; the hub starts the
    /// take. For an hour the card did both, which meant recording began before you had decided to.
    @Test func theRecordButtonOpensTheRecorderWithoutStartingATake() {
        let content = DialSample.content(recordingCount: 0, playback: nil)
        var navigator = DialNavigator(content: content, root: .recordings)

        let opening = navigator.receive(.action("record"))

        #expect(!opening.contains(.startRecording(intoItemID: nil)), "no microphone yet")
        #expect(navigator.route == .recording)

        let starting = navigator.receive(.press)

        #expect(starting == [.startRecording(intoItemID: nil), .feedback(.commit)])
    }

    /// **`DONE` is the only thing that writes**, and it applies whichever operation the nudges
    /// armed. Trim is armed by default, so a press with no nudge keeps the selection.
    @Test func pressingOnTheEditorAppliesTheArmedOperation() {
        var navigator = DialSample.whileEditing()
        _ = navigator.receive(.tick(10))       // nudge the start handle a second in

        let effects = navigator.receive(.press)

        #expect(effects == [.commitTrim(itemID: "rec-0", start: 1, end: 600), .feedback(.commit)])
        // **Still here.** Applying used to pop, which hid the result at the moment there was one.
        #expect(navigator.route == .edit(itemID: "rec-0"))
    }

    /// **A second press cannot re-cut the old region.** The file underneath has been rewritten, so
    /// the handles are cleared and re-seeded from whatever the next refresh reports.
    @Test func applyingClearsTheSelectionSoItCannotBeAppliedTwice() {
        var navigator = DialSample.whileEditing()
        _ = navigator.receive(.tick(10))
        _ = navigator.receive(.press)

        let again = navigator.receive(.press)

        #expect(again == [.commitTrim(itemID: "rec-0", start: 0, end: 600), .feedback(.commit)])
    }

    /// Applying a delete disarms it, for the same reason: a second press would aim the same cut at
    /// a region that is no longer there.
    @Test func applyingADeleteDisarmsIt() {
        var navigator = DialSample.whileEditing()
        _ = navigator.receive(.action("cut"))
        _ = navigator.receive(.press)

        let again = navigator.receive(.press)

        #expect(again == [.commitTrim(itemID: "rec-0", start: 0, end: 600), .feedback(.commit)])
    }

    /// The right nudge is the only way to hear the selection before committing to it.
    @Test func theRightNudgePreviewsTheSelection() {
        var navigator = DialSample.whileEditing()
        _ = navigator.receive(.tick(10))

        let effects = navigator.receive(.action("preview"))

        #expect(effects == [.previewTrim(itemID: "rec-0", start: 1, end: 600), .feedback(.commit)])
        #expect(navigator.route == .edit(itemID: "rec-0"), "previewing goes nowhere")
    }

    @Test func armingDeleteMakesDoneRemoveTheSelectionInstead() {
        var navigator = DialSample.whileEditing()
        _ = navigator.receive(.tick(10))

        #expect(navigator.receive(.action("cut")) == [.feedback(.commit)], "arming writes nothing")
        #expect(navigator.route == .edit(itemID: "rec-0"), "and goes nowhere")

        let effects = navigator.receive(.press)

        #expect(effects == [.commitCut(itemID: "rec-0", start: 1, end: 600), .feedback(.commit)])
        #expect(navigator.route == .edit(itemID: "rec-0"))
    }

    /// **Back leaves and asks nothing**, because nothing has been written to save or discard.
    ///
    /// It does stop the preview. That is not an edit being applied — it is audio being released, and
    /// leaving with it still playing was a real bug: the preview ran on over the library and over
    /// the next recording, because nothing in the leave path knew about it. `pop()` says so now.
    @Test func leavingTheEditorAppliesNothingButReleasesThePreview() {
        var navigator = DialSample.whileEditing()
        _ = navigator.receive(.tick(10))

        let effects = navigator.receive(.action("back"))

        #expect(effects == [.stopPreview, .feedback(.commit)])
        #expect(!effects.contains { if case .commitTrim = $0 { return true } else { return false } },
                "leaving must still write nothing")
        #expect(navigator.route == .recordings)
    }

    /// **The nudges act immediately.** They were rows on a pushed menu; each is one gesture now.
    @Test func theItemNudgesActWithoutLeavingTheLibrary() {
        var navigator = DialSample.inRecordings()

        #expect(navigator.receive(.action("share")) == [.item(.share, itemID: "rec-0"), .feedback(.commit)])
        #expect(navigator.receive(.action("add")) == [.item(.addToPlaylist, itemID: "rec-0"), .feedback(.commit)])
        #expect(navigator.route == .recordings)
    }


    /// **Delete is the exception, and the only one.** Every other row acts on the press; this one
    /// pushes a guard, because it is the single thing here that cannot be taken back.
    @Test func pressingDeleteOpensTheGuardInstead() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.action("delete"))

        #expect(effects == [.feedback(.commit)], "nothing has been asked of the host yet")
        #expect(navigator.route == .confirmDelete(itemID: "rec-0"))
    }

    @Test func confirmingTheGuardDeletes() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.action("delete"))
        _ = navigator.receive(.tick(1))        // Cancel → Delete

        let effects = navigator.receive(.press)

        #expect(effects == [.item(.delete, itemID: "rec-0"), .feedback(.commit)])
        #expect(navigator.route == .recordings)
    }

    /// Cancel is row 0, so a stray press on arrival is the harmless answer.
    @Test func theGuardOpensOnCancelAndPressingItAsksForNothing() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.action("delete"))

        let effects = navigator.receive(.press)

        #expect(effects == [.feedback(.commit)])
        #expect(navigator.route == .recordings, "and it leaves the guard")
    }

    // MARK: - The fork



    /// Nothing playing means nothing to pause, but the release still has to happen — the player can
    /// hold a paused track just as firmly as a playing one.
    @Test func editingReleasesEvenWithNothingPlaying() {
        var navigator = DialNavigator(
            content: DialSample.content(playback: nil), root: .recordings
        )

        let effects = navigator.receive(.action("edit"))

        #expect(effects.first == .releasePlayer)
        #expect(navigator.route == .edit(itemID: "rec-0"))
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

    /// **The editor offers Back and nothing else.** `Start handle` and `End handle` were replaced
    /// by tapping the handle itself, and `Preview` was removed outright — so the row holds only the
    /// one chip every screen below the root carries.
    @Test func theEditorOffersOnlyTheTwoFixedEnds() {
        let navigator = DialSample.whileEditing()

        #expect(navigator.screen.actions.map(\.id) == ["back", "settings"])
    }

    /// Now Playing used to be three mode chips and no Back, which made the command load-bearing:
    /// without it the screen was a trap. The modes are gone and Back leads every row now — so this
    /// pins the *reachability*, which is what mattered, rather than the absence that caused it.
    @Test func backIsBothAChipAndACommandOnNowPlaying() {
        var navigator = DialSample.navigator()
        _ = navigator.receive(.hold)
        #expect(navigator.screen.actions.first?.id == "back")
        #expect(navigator.screen.chrome.canGoBack, "the way out is the top bar's chevron")

        _ = navigator.receive(.action("back"))

        #expect(navigator.route == .recordings)
    }
}
