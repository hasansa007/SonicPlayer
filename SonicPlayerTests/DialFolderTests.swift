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

        // Home is the fork: row 0 is Listen, row 1 is Record. A tick here would choose the other
        // mode, and these tests are about browsing.
        var navigator = DialNavigator(content: content, root: .library)
        _ = navigator.receive(.press)       // home → Listen
        return navigator
    }

    /// Folders sort first, so the highlight opens on one — no tick needed since Import and New
    /// folder became buttons rather than rows.
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

        #expect(navigator.screen.chrome.breadcrumb == ["HOME", "LIBRARY", "LECTURES"])
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

    /// The four nudges all act on a file. A folder answers none of them, so the stick draws nothing
    /// rather than offering four controls that would refuse.
    @Test func theStickIsBlankOverAFolder() {
        let navigator = Self.atFolderRow()

        #expect(navigator.screen.ring.directions == nil)
    }

    @Test func nudgingOverAFolderIsRefused() {
        var navigator = Self.atFolderRow()

        #expect(navigator.receive(.action("share")) == [.feedback(.limit)])
        #expect(navigator.receive(.action("delete")) == [.feedback(.limit)])
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
    /// rather than the root's — **plus the folder's own controls**, Import above and the chip row
    /// below, which are stops here exactly as they are at the root. Two files is six positions.
    @Test func theWheelWrapsWithinTheFolder() {
        var navigator = Self.atFolderRow()
        _ = navigator.receive(.press)

        _ = navigator.receive(.tick(6))

        let effects = navigator.receive(.press)
        #expect(DialSample.playedID(effects) == "rec-a")
    }

    /// And the stop it gains is that folder's, not the library's — the reason Import carries a
    /// destination id at all.
    @Test func theFoldersVerbImportsIntoTheFolder() {
        var navigator = Self.atFolderRow()
        _ = navigator.receive(.press)

        _ = navigator.receive(.tick(-1))

        #expect(navigator.isPinnedActionHighlighted)
        #expect(
            navigator.receive(.press)
                == [.importFiles(intoItemID: "folder-lectures"), .feedback(.commit)]
        )
    }
}
