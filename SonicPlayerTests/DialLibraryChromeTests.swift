import Foundation
import Testing

@testable import SonicPlayer

/// The chip row: what is in it, where it sits, and the fact that the wheel reaches all of it (#6).
///
/// **Record and Import spent six homes above the list before landing here.** A home card, a chip, a
/// list row, a pinned bottom row, a bar button, a pinned top row — and the last of those was the
/// mode fork's leftover, since pinning one verb per screen only worked while there was a mode to
/// decide which. With both in the row the card holds a list and nothing else.
@Suite
struct DialLibraryChromeTests {

    private func chips(_ navigator: DialNavigator) -> [String] {
        navigator.screen.actions.map(\.id)
    }

    // MARK: - What is in the row

    /// **Back leads, Settings trails, and the screen's own verbs sit between.** One layout on every
    /// screen, so the two that mean the same thing everywhere never move.
    @Test func theLibraryCarriesBothVerbsBetweenBackAndSettings() {
        #expect(chips(DialSample.inRecordings()) == ["record", "import", "newFolder", "sort", "settings"])
    }

    @Test func aFolderCarriesTheSameRow() {
        var navigator = DialFolderTests.navigator()
        _ = navigator.receive(.press)

        #expect(chips(navigator) == ["back", "record", "import", "newFolder", "sort", "settings"])
    }

    /// **Back is absent at the root, not reserved and greyed.**
    ///
    /// It held a disabled slot for a while, on the argument that a chip arriving one level down
    /// shifts the row under a thumb that had learned it. Seen on the phone that trade is the wrong
    /// way round: the shift is a one-off on a screen you have just changed, and the greyed chip is
    /// permanent on the screen you spend the most time on, offering the one thing it cannot do.
    @Test func backIsNotDrawnWhereThereIsNowhereToGo() {
        #expect(!chips(DialSample.inRecordings()).contains("back"))

        var deeper = DialFolderTests.navigator()
        _ = deeper.receive(.press)
        #expect(deeper.screen.actions.first?.id == "back", "and it leads the row once it leads somewhere")
        #expect(deeper.screen.actions.first?.emphasis != .disabled)
    }

    /// **Settings is on every screen except its own** — a door into the room you are standing in is
    /// the same defect as a Back that cannot go back.
    @Test func settingsIsOnEveryScreenButItsOwn() {
        #expect(chips(DialSample.inRecordings()).last == "settings")
        #expect(chips(DialSample.whileEditing()).last == "settings")
        #expect(chips(DialSample.whileRecording()).last == "settings")

        var settings = DialSample.inRecordings()
        _ = settings.receive(.action("settings"))
        #expect(chips(settings) == ["back"], "the way out, and nothing else")
    }

    /// **The guard screen is the one exception**, and deliberately: `Cancel` is already the way
    /// back, so a Back chip beside it would be a second one differently worded.
    @Test func theDeleteGuardCarriesNoChipsAtAll() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.action("delete"))

        #expect(navigator.screen.actions.isEmpty)
    }

    /// Nothing is drawn above the list any more — the contract has no pinned slot left.
    @Test func theCardHoldsAListAndNothingElse() {
        let navigator = DialSample.inRecordings()

        guard case .list(let list) = navigator.screen.content else {
            Issue.record("expected a list")
            return
        }
        #expect(list.rows.count == 12, "twelve files, and nothing above them")
        #expect(list.highlighted == 0, "which is the first file")
        #expect(navigator.screen.ring.hub == .label("PLAY"))
    }

    // MARK: - The wheel reaches all of it

    /// The bug this whole arrangement exists to make impossible: a control drawn on the card that
    /// the one input surface cannot operate. The chips are stops, in the order they are drawn.
    @Test func theChipsAreTheStopsAfterTheLastRow() {
        var navigator = DialSample.inRecordings(recordingCount: 2)
        _ = navigator.receive(.tick(1))                     // the last file

        for expected in ["record", "import", "newFolder", "sort", "settings"] {
            _ = navigator.receive(.tick(1))
            #expect(navigator.highlightedChipID == expected)
        }

        _ = navigator.receive(.tick(1))
        #expect(navigator.level.highlighted == 0, "and round to the first row")
    }

    /// **The press runs the function the tap runs** — `perform` with the id the chip was drawn
    /// from, because two implementations that agree today are what rule 3 forbids.
    @Test func pressingAChipDoesExactlyWhatTappingItDoes() {
        var byWheel = DialSample.inRecordings()
        _ = byWheel.receive(.tick(12))                      // twelve files, then Record
        #expect(byWheel.highlightedChipID == "record")
        var byTap = DialSample.inRecordings()

        #expect(byWheel.receive(.press) == byTap.receive(.action("record")))
    }

    /// The hub names what it is resting on, so on a chip it cannot say PLAY.
    @Test func theHubNamesTheChipItIsRestingOn() {
        var navigator = DialSample.inRecordings(recordingCount: 1)

        _ = navigator.receive(.tick(1))
        #expect(navigator.screen.ring.hub == .label("RECORD"))
        _ = navigator.receive(.tick(1))
        #expect(navigator.screen.ring.hub == .label("IMPORT"))
        _ = navigator.receive(.tick(1))
        #expect(navigator.screen.ring.hub == .label("NEW FOLDER"))
    }

    /// **Only where the wheel scrolls.** Now Playing, the recorder and the editor bind it to seek,
    /// gain and trim — there is no highlight to park on a chip, so theirs stay touch-only.
    @Test func theScreensThatTurnSomethingElseKeepTheirChipsOnTouchAlone() {
        #expect(DialSample.whileEditing().highlightedChipID == nil)
        #expect(DialSample.whileRecording().highlightedChipID == nil)
    }

    // MARK: - What the verbs do

    @Test func importAsksTheHostAndStaysPut() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.action("import"))

        #expect(effects == [.importFiles(intoItemID: nil), .feedback(.commit)])
        #expect(navigator.route == .recordings, "the files land in this list")
    }

    /// **The destination is where you are standing** — the reason Import carries an id at all.
    @Test func insideAFolderImportTargetsThatFolder() {
        var navigator = DialFolderTests.navigator()
        _ = navigator.receive(.press)

        #expect(
            navigator.receive(.action("import"))
                == [.importFiles(intoItemID: "folder-lectures"), .feedback(.commit)]
        )
    }

    /// **Arriving is not starting**, and opening the recorder lets go of the player first — the
    /// microphone takes the audio session, so a held track would be recorded through it.
    @Test func recordOpensTheRecorderWithoutStartingATake() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.action("record"))

        #expect(effects.contains(.releasePlayer))
        #expect(effects.last == .feedback(.commit))
        #expect(!effects.contains(.startRecording(intoItemID: nil)), "arrived, not started")
        #expect(navigator.route == .recording)
    }

    /// **Both verbs work from every browsing screen**, which is the whole of what the fork cost:
    /// each was refused on one side of it.
    @Test func neitherVerbIsRefusedAnywhereYouCanBrowse() {
        var folder = DialFolderTests.navigator()
        _ = folder.receive(.press)

        #expect(folder.receive(.action("record")).contains(.releasePlayer))
        #expect(folder.route == .recording)
    }

    /// An empty library still says why it is bare, and now the message carries the instruction —
    /// the two verbs were the only controls with a subtitle, and chips do not have one.
    @Test func anEmptyLibrarySaysWhatToDoAboutIt() {
        let navigator = DialSample.inRecordings(recordingCount: 0)

        guard case .message(let message) = navigator.screen.content else {
            Issue.record("expected a message, got \(navigator.screen.content)")
            return
        }
        #expect(message.title == "Nothing here yet")
        #expect(message.body.contains("Record"))
        #expect(message.body.contains("import"))
    }
}
