import Foundation
import Testing

@testable import SonicPlayer

/// Folders in the dial's library (#6).
///
/// **The stack is the path**, so most of what needs proving is that descending and popping agree
/// with each other — there is no stored folder URL that could disagree with where you actually are.
@Suite
struct DialFolderTests {

    // A library with one folder of two, then two loose files. Folders sort first, which is what
    // `LibraryTree` guarantees and what these row indices assume.
    //
    // Built on `DialSample.content` rather than a bare `DialContent`, because home is a list of
    // sections and pressing through it is how the library is reached — a content with no sections
    // leaves every one of these tests standing on home, pressing at nothing.
    static func navigator() -> DialNavigator {
        var content = DialSample.content(recordingCount: 0)
        content.recordings = [
            DialContent.Item(
                id: "folder-lectures",
                title: "Lectures",
                duration: 0,
                subtitle: "2 recordings",
                children: [
                    DialContent.Item(id: "rec-a", title: "Lecture 1", duration: 60),
                    DialContent.Item(id: "rec-b", title: "Lecture 2", duration: 120),
                ]
            ),
            DialContent.Item(id: "rec-0", title: "Recording 1", duration: 600),
            DialContent.Item(id: "rec-1", title: "Recording 2", duration: 30),
        ]

        return DialNavigator(content: content, root: .recordings)
    }

    /// Folders sort first, so the highlight opens on one — the library is the root now, so there
    /// is nothing to press through to reach it.
    private static func atFolderRow() -> DialNavigator { navigator() }

    @Test func theLibraryListsFoldersBeforeFiles() {
        let navigator = Self.navigator()

        guard case .list(let list) = navigator.screen.content else {
            Issue.record("expected a list")
            return
        }
        #expect(list.rows.map(\.title) == ["Lectures", "Recording 1", "Recording 2"])
        #expect(list.rows[0].icon == .playlist, "a folder is not a silent recording")
        #expect(list.rows[0].trailing == "2", "what is inside, not how long it is")
    }

    @Test func pressingAFolderOpensItRatherThanPlayingIt() {
        var navigator = Self.atFolderRow()

        let effects = navigator.receive(.press)

        #expect(effects == [.feedback(.commit)], "nothing plays")
        #expect(navigator.route == .folder(itemID: "folder-lectures"))
    }

    @Test func theFolderShowsItsOwnContentsAndNoImportRow() {
        var navigator = Self.atFolderRow()
        _ = navigator.receive(.press)

        guard case .list(let list) = navigator.screen.content else {
            Issue.record("expected a list")
            return
        }
        #expect(list.rows.map(\.title) == ["Lecture 1", "Lecture 2"])
    }

    @Test func theBreadcrumbNamesTheFolder() {
        var navigator = Self.atFolderRow()
        _ = navigator.receive(.press)

        #expect(navigator.screen.chrome.breadcrumb == ["LIBRARY", "LECTURES"])
    }

    @Test func backLeavesTheFolder() {
        var navigator = Self.atFolderRow()
        _ = navigator.receive(.press)

        _ = navigator.receive(.action("back"))

        #expect(navigator.route == .recordings)
    }

    /// Inside a folder there is no Import row, so row 0 is the first recording rather than the
    /// second — the offset every reader goes through `RecordingsRow` for.
    @Test func pressingInsideAFolderPlaysTheRightFile() {
        var navigator = Self.atFolderRow()
        _ = navigator.receive(.press)

        let effects = navigator.receive(.press)

        #expect(DialSample.playedID(effects) == "rec-a")
    }

    @Test func theSecondRowInsideAFolderIsTheSecondFile() {
        var navigator = Self.atFolderRow()
        _ = navigator.receive(.press)
        _ = navigator.receive(.tick(1))

        let effects = navigator.receive(.press)

        #expect(DialSample.playedID(effects) == "rec-b")
    }

    /// **A folder answers two of the four.** Share takes a file URL and adding a folder to a
    /// playlist is a move this slice does not do; renaming and deleting one were never the problem,
    /// and the stick sat blank over folders long enough that a library could grow them and never
    /// touch them again.
    @Test func theStickOffersAFolderTheTwoVerbsItCanAnswer() {
        let directions = Self.atFolderRow().screen.ring.directions

        #expect(directions?.up?.id == "rename")
        #expect(directions?.down?.id == "delete")
        #expect(directions?.left == nil)
        #expect(directions?.right == nil)
    }

    @Test func theVerbsAFolderCannotAnswerAreRefused() {
        var navigator = Self.atFolderRow()

        #expect(navigator.receive(.action("share")) == [.feedback(.limit)])
        #expect(navigator.receive(.action("add")) == [.feedback(.limit)])
        #expect(navigator.route == .recordings, "and nothing was opened")
    }

    @Test func doublePressingAFolderDoesNotOpenTheEditor() {
        var navigator = Self.atFolderRow()

        #expect(navigator.receive(.doublePress).isEmpty)
        #expect(navigator.route == .recordings)
    }

    /// The nudges still work at depth — they act on the highlighted file wherever it is.
    @Test func theNudgesActInsideAFolderToo() {
        var navigator = Self.atFolderRow()
        _ = navigator.receive(.press)

        let effects = navigator.receive(.action("share"))

        #expect(effects == [.item(.share, itemID: "rec-a"), .feedback(.commit)])
    }

    /// A folder that disappears under a screen you are standing in shows nothing, rather than
    /// quietly showing its parent's contents under the folder's own heading.
    @Test func aFolderThatVanishesUnderneathShowsNothing() {
        var navigator = Self.atFolderRow()
        _ = navigator.receive(.press)

        var content = DialContent()
        content.recordings = [DialContent.Item(id: "rec-0", title: "Recording 1", duration: 600)]
        navigator.update(content)

        guard case .message = navigator.screen.content else {
            Issue.record("expected the empty message, got \(navigator.screen.content)")
            return
        }
    }

    /// The wheel wraps inside a folder the same way it does everywhere, and against its own count
    /// rather than the root's — **plus the folder's six chips**, which are stops here exactly as
    /// they are at the root. Two files is eight positions.
    @Test func theWheelWrapsWithinTheFolder() {
        var navigator = Self.atFolderRow()
        _ = navigator.receive(.press)

        _ = navigator.receive(.tick(8))

        let effects = navigator.receive(.press)
        #expect(DialSample.playedID(effects) == "rec-a")
    }

    /// And the chip it gains is that folder's, not the library's — the reason Import carries a
    /// destination id at all.
    @Test func theFoldersImportChipTargetsTheFolder() {
        var navigator = Self.atFolderRow()
        _ = navigator.receive(.press)

        _ = navigator.receive(.tick(-4))            // back past settings, sort, new folder, import

        #expect(navigator.highlightedChipID == "import")
        #expect(
            navigator.receive(.press)
                == [.importFiles(intoItemID: "folder-lectures"), .feedback(.commit)]
        )
    }
}
