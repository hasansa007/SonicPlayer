import Foundation
import Testing

@testable import SonicPlayer

/// **Where audio lands (#6).**
///
/// Two questions the library could not answer once it grew folders: where a new take goes, and how
/// something gets into a folder that does not exist yet. Both had the same shape of wrong answer —
/// the app did something reasonable somewhere else and left the filing to you.
@Suite
struct DialFilingTests {

    // MARK: - A take lands where you are standing

    /// **The folder is read off the stack, not off the route.** The recorder is pushed *on top* of
    /// the folder you opened it from, so by the time the hub starts the take the current route is
    /// `.recording` — which is exactly why every take used to land in one fixed folder however deep
    /// in the library you were when you pressed Record.
    @Test func aTakeStartedInsideAFolderLandsInThatFolder() {
        var navigator = DialFolderTests.navigator()
        _ = navigator.receive(.press)                       // into Lectures
        _ = navigator.receive(.action("record"))            // the recorder, opened not started

        let effects = navigator.receive(.press)

        #expect(effects.contains(.startRecording(intoItemID: "folder-lectures")))
    }

    @Test func aTakeStartedAtTheRootLandsAtTheRoot() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.action("record"))

        #expect(navigator.receive(.press).contains(.startRecording(intoItemID: nil)))
    }

    /// **The quick action resets the stack**, so it correctly answers "the root" — it means "start
    /// here", and there is no folder you were standing in.
    @Test func theQuickActionsRecorderLandsAtTheRoot() {
        var navigator = DialFolderTests.navigator()
        _ = navigator.receive(.press)                       // somewhere deep

        _ = navigator.openRecorder()

        #expect(navigator.receive(.press).contains(.startRecording(intoItemID: nil)))
    }

    /// Two levels down still answers the *nearest* folder — the take belongs where you are, not
    /// where you came in.
    @Test func theNearestFolderWinsRatherThanTheFirstOne() {
        var content = DialSample.content(recordingCount: 0)
        content.recordings = [
            DialContent.Item(
                id: "outer", title: "Outer", duration: 0,
                children: [
                    DialContent.Item(
                        id: "inner", title: "Inner", duration: 0,
                        children: [DialContent.Item(id: "rec-x", title: "A take", duration: 30)]
                    )
                ]
            )
        ]
        var navigator = DialNavigator(content: content, root: .recordings)
        _ = navigator.receive(.press)                       // Outer
        _ = navigator.receive(.press)                       // Inner
        _ = navigator.receive(.action("record"))

        #expect(navigator.receive(.press).contains(.startRecording(intoItemID: "inner")))
    }

    // MARK: - Filing into somewhere that does not exist yet

    /// **A flat list of every folder answers the question only while the right answer is in it.**
    /// Without this row, filing into somewhere new meant leaving the screen, making the folder, and
    /// starting the move again against a list that had changed underneath.
    @Test func theMoveScreenOffersANewFolderFirst() {
        var navigator = Self.atTheMoveScreen()

        guard case .list(let list) = navigator.screen.content else {
            Issue.record("expected a list, got \(navigator.screen.content)")
            return
        }
        #expect(list.rows.first?.id == "newFolder")
        #expect(list.rows.first?.title == "New folder")
        #expect(list.rows.dropFirst().first?.title == MoveDestinations.rootTitle)
        // The highlight opens on it, so the hub has to say what it does rather than `FILE HERE` —
        // which would be the hub lying about a press that files nowhere yet.
        #expect(navigator.screen.ring.hub == .label("NAME IT"))

        _ = navigator.receive(.tick(1))
        #expect(navigator.screen.ring.hub == .label("FILE HERE"))
    }

    /// **One effect, not two.** Naming is the host's — the dial has no keyboard — and the file
    /// follows the folder it just named, which is what stops "file it somewhere new" being three
    /// separate jobs.
    @Test func pressingNewFolderAsksForOneAndTakesTheRecordingWithIt() {
        var navigator = Self.atTheMoveScreen()

        let effects = navigator.receive(.press)

        #expect(effects == [.createFolderForMove(itemID: "rec-0"), .feedback(.commit)])
        #expect(navigator.route == .recordings, "and the Move screen is done with")
    }

    /// The existing destinations still work, and are still where they were — which is the whole
    /// risk of adding a row to a list something else indexes. **One list, read by the projection
    /// that draws it and the press that acts on it**, so there is no offset to keep in step.
    @Test func theExistingDestinationsAreUnmovedByTheNewRow() {
        var navigator = Self.atTheMoveScreen()
        _ = navigator.receive(.tick(2))     // New folder, Library, then the first real folder

        let effects = navigator.receive(.press)

        #expect(effects == [.moveItem(itemID: "rec-0", toFolderID: "folder-lectures"), .feedback(.commit)])
    }

    @Test func theRowCountIncludesTheNewFolderRow() {
        let navigator = Self.atTheMoveScreen()
        let destinations = MoveDestinations.all(in: navigator.content.recordings, excluding: "rec-0")

        #expect(navigator.currentRowCount == destinations.count + 1)
    }

    // MARK: - Fixtures

    /// The Move screen, filing `rec-0` from the library root of `DialFolderTests`' fixture: one
    /// folder, then two loose files.
    private static func atTheMoveScreen() -> DialNavigator {
        var navigator = DialFolderTests.navigator()
        _ = navigator.receive(.tick(1))                 // past the folder, onto Recording 1
        _ = navigator.receive(.action("move"))
        return navigator
    }
}
