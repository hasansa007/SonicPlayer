import Foundation
import Testing

@testable import SonicPlayer

/// The pinned Import row and the sync control (#6).
@Suite
struct DialLibraryChromeTests {

    @Test func theLibraryPinsExactlyTheImportRow() {
        let navigator = DialSample.inRecordings()

        guard case .list(let list) = navigator.screen.content else {
            Issue.record("expected a list")
            return
        }
        #expect(list.pinnedRows == 1)
        #expect(list.rows.first?.id == "import", "the pinned one is the one at the top")
    }

    /// Inside a folder there is no Import row, so there is nothing to pin — and pinning the first
    /// *recording* instead would be worse than not pinning at all.
    @Test func aFolderPinsNothing() {
        var navigator = DialFolderTests.navigator()
        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)

        guard case .list(let list) = navigator.screen.content else {
            Issue.record("expected a list")
            return
        }
        #expect(list.pinnedRows == 0)
    }

    @Test func homePinsNothing() {
        let navigator = DialSample.navigator()

        guard case .list(let list) = navigator.screen.content else {
            Issue.record("expected a list")
            return
        }
        #expect(list.pinnedRows == 0, "home is cards, and none of them is always-available")
    }

    // MARK: - Sync

    @Test func theLibraryOffersSync() {
        #expect(DialSample.inRecordings().screen.chrome.showsSync)
    }

    @Test func aFolderOffersSyncToo() {
        var navigator = DialFolderTests.navigator()
        _ = navigator.receive(.tick(1))
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
