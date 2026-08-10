import Foundation
import Testing

@testable import SonicPlayer

/// The verb pinned above the library, and the fact that the wheel can reach it (#6).
///
/// **It has been a home card, a chip, a list row, a pinned bottom row, a bar button and now a
/// pinned top row** — and in every one of those homes it was a *touch* target. Pinned above the
/// list it was finally where it belonged and still the one thing on the screen the dial could not
/// operate: turning never landed on it, so the single control this app is built around could not
/// do the single thing each mode exists for. Found on the phone, where you notice immediately that
/// Record only answers a finger.
///
/// So it is a stop on the ring now, sitting at `pinnedIndex` — before the first row rather than on
/// it, which is what keeps the items indexing from zero and keeps `RecordingsRow`'s old offset
/// buried.
@Suite
struct DialLibraryChromeTests {

    // MARK: - Which verb, and where

    @Test func listenPinsImport() {
        let action = DialSample.inRecordings().screen.chrome.primaryAction
        #expect(action?.id == "import")
        #expect(action?.isLive == false, "a picker opens; nothing starts")
    }

    @Test func recordPinsRecord() {
        let action = DialSample.inRecordMode().screen.chrome.primaryAction
        #expect(action?.id == "record")
        #expect(action?.isLive == true, "it starts something, and is drawn as such")
    }

    /// **A folder gets one too.** It was root-only once, on the reasoning that Import puts files in
    /// the library — a fact about the implementation, not about the place. A folder is somewhere
    /// you can put things.
    @Test func aFolderPinsItToo() {
        var navigator = DialFolderTests.navigator()
        _ = navigator.receive(.press)

        #expect(navigator.screen.chrome.primaryAction?.id == "import")
    }

    @Test func screensWithoutFilesPinNothing() {
        #expect(DialSample.navigator().screen.chrome.primaryAction == nil, "home")
        #expect(DialSample.whileEditing().screen.chrome.primaryAction == nil, "the editor")
        #expect(DialSample.whileRecording().screen.chrome.primaryAction == nil, "recording")
    }

    /// The list is only its contents — no verb competes with the files for the highlight, which is
    /// the whole reason the stop lives outside the list rather than at row 0.
    @Test func theListHoldsNothingButFilesAndFolders() {
        let navigator = DialSample.inRecordings()

        guard case .list(let list) = navigator.screen.content else {
            Issue.record("expected a list")
            return
        }
        #expect(list.rows.count == 12, "twelve files, and nothing else")
        #expect(list.highlighted == 0, "which is the first file")
        #expect(navigator.screen.ring.hub == .label("PLAY"))
    }

    // MARK: - The wheel reaches it

    /// The bug, stated as the fix: one detent back off the first file is the verb, not the last
    /// file. The ring is one longer than the list, and this is the stop that makes it so.
    @Test func turningBackOffTheFirstFileLandsOnTheVerb() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.tick(-1))

        #expect(effects == [.feedback(.detent)])
        #expect(navigator.isPinnedActionHighlighted)
        #expect(navigator.screen.chrome.primaryAction?.isHighlighted == true, "and it lights up")
    }

    /// Past it the ring still wraps — the stop is one more position on a continuous ring, not a
    /// wall in front of one. **The chip row is what is on the other side of it**, because the ring
    /// runs in the order the card is drawn and the chips are the last thing on it.
    @Test func turningBackPastTheVerbWrapsToTheChips() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.tick(-2))

        #expect(!navigator.isPinnedActionHighlighted)
        #expect(navigator.highlightedChipID == "sort", "the last chip, drawn rightmost")

        _ = navigator.receive(.tick(-3))            // back past New folder and Back
        #expect(navigator.level.highlighted == 11, "and then the twelfth file")
    }

    /// **The press runs the function the tap runs.** Not an equivalent one — `press` calls
    /// `perform` with the same id the row was drawn from, because two implementations that agree
    /// today are the thing rule 3 in `DialNavigator` exists to forbid.
    @Test func pressingItImportsExactlyAsTappingDoes() {
        var byWheel = DialSample.inRecordings()
        _ = byWheel.receive(.tick(-1))
        var byTap = DialSample.inRecordings()

        #expect(byWheel.receive(.press) == byTap.receive(.action("import")))
    }

    @Test func pressingItInRecordModeOpensTheRecorder() {
        var navigator = DialSample.inRecordMode()
        _ = navigator.receive(.tick(-1))

        _ = navigator.receive(.press)

        #expect(navigator.route == .recording)
    }

    /// The hub says what the row under it does, everywhere — so on this row it cannot say PLAY.
    /// A hub naming the wrong verb was the visible half of the bug.
    @Test func theHubNamesTheVerbItIsRestingOn() {
        var listening = DialSample.inRecordings()
        _ = listening.receive(.tick(-1))
        #expect(listening.screen.ring.hub == .label("IMPORT"))

        var recording = DialSample.inRecordMode()
        _ = recording.receive(.tick(-1))
        #expect(recording.screen.ring.hub == .label("RECORD"))
    }

    /// **An empty list opens on its verb**, because clamping has nothing else to put the highlight
    /// on — which is exactly the screen where the one thing you can do should already be selected.
    @Test func anEmptyLibraryOpensOnTheVerb() {
        let navigator = DialSample.inRecordings(recordingCount: 0)

        #expect(navigator.isPinnedActionHighlighted)
        #expect(navigator.screen.hint == "nothing here yet · press to import")
    }

    /// An empty library has no rows at all, so the reason it is bare has to be said somewhere.
    @Test func anEmptyLibrarySaysWhyItIsEmpty() {
        let navigator = DialSample.inRecordings(recordingCount: 0)

        guard case .message(let message) = navigator.screen.content else {
            Issue.record("expected a message, got \(navigator.screen.content)")
            return
        }
        #expect(message.title == "Nothing here yet")
    }

    /// **Home's leading stop is the gear, not a verb.** It pins nothing above its list — the
    /// corner button is the thing the wheel could not otherwise reach there, so it takes the
    /// position instead. Home has no Back, being the root, so its ring is three.
    @Test func homesLeadingStopIsSettings() {
        var home = DialSample.navigator()

        _ = home.receive(.tick(-1))

        #expect(!home.isPinnedActionHighlighted, "there is no verb to pin on the fork")
        #expect(home.isSettingsHighlighted)
        #expect(home.screen.chrome.isSettingsHighlighted, "and the gear lights up")
        #expect(home.screen.ring.hub == .label("SETTINGS"))
    }

    @Test func pressingItOpensSettings() {
        var home = DialSample.navigator()
        _ = home.receive(.tick(-1))

        _ = home.receive(.press)

        #expect(home.route == .settings)
    }

    /// Home is the root, so there is nowhere back to — its ring is the gear plus two rows.
    @Test func homeHasNoBackStop() {
        var home = DialSample.navigator()

        _ = home.receive(.tick(1))
        #expect(home.level.highlighted == 1, "Record")
        _ = home.receive(.tick(1))
        #expect(home.isSettingsHighlighted, "and round to the gear, not to a Back that is not there")
    }

    // MARK: - Back

    /// The other control that was tap-only. It is the stop **after** the last row, matching where
    /// it is drawn — so turning down off the end of the list reaches it.
    @Test func backIsTheStopAfterTheLastRow() {
        var navigator = DialSample.inRecordings(recordingCount: 3)
        _ = navigator.receive(.tick(3))

        #expect(navigator.isBackHighlighted)
        #expect(navigator.screen.chrome.isBackHighlighted)
        #expect(navigator.screen.ring.hub == .label("BACK"))
    }

    @Test func pressingItPopsExactlyAsTheBarButtonDoes() {
        var byWheel = DialSample.inRecordings(recordingCount: 3)
        _ = byWheel.receive(.tick(3))
        var byTap = DialSample.inRecordings(recordingCount: 3)

        #expect(byWheel.receive(.press) == byTap.receive(.action("back")))
        #expect(byWheel.route == .library)
    }

    /// **Only where the wheel scrolls.** Now Playing, the recorder and the editor bind it to seek,
    /// gain and trim — there is no highlight to park on a bar button, and taking a detent away from
    /// scrubbing to reach Back would be the worse trade.
    @Test func theScreensThatTurnSomethingElseKeepBackOnTouchAlone() {
        #expect(DialSample.whileEditing().isBackHighlighted == false)
        #expect(DialSample.whileRecording().isBackHighlighted == false)
    }

    // MARK: - Where the verb acts

    @Test func importAsksTheHostAndStaysPut() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.action("import"))

        #expect(effects == [.importFiles(intoItemID: nil), .feedback(.commit)])
        #expect(navigator.route == .recordings, "the files land in this list")
    }

    /// **The destination is where you are standing.** This is the whole reason Import carries an
    /// id: at the root it means the library, and inside a folder it means that folder.
    @Test func insideAFolderImportTargetsThatFolder() {
        var navigator = DialFolderTests.navigator()
        _ = navigator.receive(.press)

        #expect(
            navigator.receive(.action("import"))
                == [.importFiles(intoItemID: "folder-lectures"), .feedback(.commit)]
        )
    }

    /// **Each mode's verb is refused in the other**, wherever it arrives from. Listen is the mode
    /// where nothing can be lost and Record is the one that makes things; a verb that fired in both
    /// would make the fork decorative.
    @Test func eachModeRefusesTheOthersVerb() {
        var listening = DialSample.inRecordings()
        #expect(listening.receive(.action("record")) == [.feedback(.limit)])

        var recording = DialSample.inRecordMode()
        #expect(recording.receive(.action("import")) == [.feedback(.limit)])
    }
}
