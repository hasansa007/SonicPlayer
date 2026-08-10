import Foundation
import Testing

@testable import SonicPlayer

/// The library's verbs, which live in the bottom bar rather than in the list (#6).
@Suite
struct DialLibraryChromeTests {

    @Test func theLibraryOffersBothActionsInTheBar() {
        #expect(DialSample.inRecordings().screen.chrome.showsLibraryActions)
    }

    /// **A folder gets them too.** They were root-only on the reasoning that Import puts files in
    /// the library — a fact about the implementation, not about the place. A folder is somewhere
    /// you can put things.
    @Test func aFolderOffersThemToo() {
        var navigator = DialFolderTests.navigator()
        _ = navigator.receive(.press)

        #expect(navigator.screen.chrome.showsLibraryActions)
    }

    @Test func screensWithoutFilesOfferNeither() {
        #expect(!DialSample.navigator().screen.chrome.showsLibraryActions, "home")
        #expect(!DialSample.whileEditing().screen.chrome.showsLibraryActions, "the editor")
    }

    /// The list is only its contents now — no verb competes with the files for the highlight.
    @Test func theListHoldsNothingButFilesAndFolders() {
        let navigator = DialSample.inRecordings()

        guard case .list(let list) = navigator.screen.content else {
            Issue.record("expected a list")
            return
        }
        #expect(list.rows.count == 12, "twelve files, and nothing else")
        #expect(list.highlighted == 0, "which is the first file")
        #expect(navigator.screen.ring.hub == .label("OPEN"))
    }

    /// An empty library has no rows at all, so the reason it is bare has to be said somewhere.
    @Test func anEmptyLibrarySaysWhyItIsEmpty() {
        var navigator = DialSample.navigator(recordingCount: 0)
        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)

        guard case .message(let message) = navigator.screen.content else {
            Issue.record("expected a message, got \(navigator.screen.content)")
            return
        }
        #expect(message.title == "Nothing here yet")
    }

    // MARK: - The bar's actions

    @Test func importAsksTheHostAndStaysPut() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.action("import"))

        #expect(effects == [.importFiles(intoItemID: nil), .feedback(.commit)])
        #expect(navigator.route == .recordings, "the files land in this list")
    }

    @Test func newFolderAsksTheHostAndStaysPut() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.action("newFolder"))

        #expect(effects == [.createFolder(inItemID: nil), .feedback(.commit)])
        #expect(navigator.route == .recordings)
    }

    /// **The destination is where you are standing.** This is the whole reason the actions carry an
    /// id: at the root they mean the library, and inside a folder they mean that folder.
    @Test func insideAFolderBothActionsTargetThatFolder() {
        var navigator = DialFolderTests.navigator()
        _ = navigator.receive(.press)

        #expect(
            navigator.receive(.action("import"))
                == [.importFiles(intoItemID: "folder-lectures"), .feedback(.commit)]
        )
        #expect(
            navigator.receive(.action("newFolder"))
                == [.createFolder(inItemID: "folder-lectures"), .feedback(.commit)]
        )
    }

    // MARK: - Sync

    @Test func theLibraryOffersSync() {
        #expect(DialSample.inRecordings().screen.chrome.showsSync)
    }

    @Test func aFolderOffersSyncToo() {
        var navigator = DialFolderTests.navigator()
        _ = navigator.receive(.press)

        #expect(navigator.screen.chrome.showsSync)
    }

    /// It reloads files, so it belongs only where files are listed.
    @Test func screensWithoutFilesDoNot() {
        #expect(!DialSample.navigator().screen.chrome.showsSync, "home")
        #expect(!DialSample.whileEditing().screen.chrome.showsSync, "the editor")
        #expect(!DialSample.whileRecording().screen.chrome.showsSync, "recording")
    }

    @Test func syncAsksForAReloadAndStaysPut() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.action("sync"))

        #expect(effects == [.reloadLibrary, .feedback(.commit)])
        #expect(navigator.route == .recordings, "you are reloading the list you are looking at")
    }
}
