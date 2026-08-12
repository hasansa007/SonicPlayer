import Foundation
import Testing

@testable import SonicPlayer

/// The demo library the screenshot path browses (#64).
///
/// **It had no folders at all.** `seedViewModels` wrote the four demo collections into `filesRoot`,
/// while `refreshDial` hands the dial `home.allFiles` and `home.libraryTree` — and `libraryTree` was
/// never seeded. So the demo library was a flat list of seven recordings, and no App Store
/// screenshot could show a folder, the Move screen, or a folder-scoped Record or Import.
///
/// The originally reported symptom — a collection that opens onto an error — was unreachable,
/// because nothing rendered a collection to open.
@Suite
struct DemoLibraryTests {

    @Test func theDemoLibraryHasFolders() {
        let folders = ScreenshotDemoData.libraryTree.filter(\.isFolder)
        #expect(!folders.isEmpty, "a demo library with no folder cannot screenshot one")
    }

    @Test func itAlsoHasLooseFilesBesideThem() {
        #expect(ScreenshotDemoData.libraryTree.contains { !$0.isFolder })
    }

    /// **A folder that claims a count must hold it.** The subtitle is on screen in a store
    /// screenshot; a folder saying "12 recordings" over five children states something false.
    @Test func everyFolderSubtitleMatchesItsContents() {
        for folder in ScreenshotDemoData.libraryTree.filter(\.isFolder) {
            let count = folder.children?.count ?? 0
            #expect(folder.subtitle?.contains("\(count) recordings") == true,
                    "\(folder.title) says \(folder.subtitle ?? "nothing") but holds \(count)")
        }
    }

    /// **No directory has to exist for this to work**, which is what the original bug got wrong: a
    /// folder carries its children, so the navigator descends inside the snapshot.
    @Test func pressingAFolderDescendsIntoIt() {
        var navigator = DialNavigator(
            content: DialContent(recordings: ScreenshotDemoData.libraryTree),
            root: .recordings
        )
        guard let index = ScreenshotDemoData.libraryTree.firstIndex(where: \.isFolder) else {
            Issue.record("no folder to descend into"); return
        }
        let folder = ScreenshotDemoData.libraryTree[index]

        _ = navigator.receive(.tick(index))
        _ = navigator.receive(.press)

        #expect(navigator.route == .folder(itemID: folder.id))
        guard case .list(let list) = navigator.screen.content else {
            Issue.record("expected the folder's contents"); return
        }
        #expect(list.rows.count == folder.children?.count)
    }

    /// Ids match `LibraryTree`'s, so a route holding one resolves the same way in demo and in life.
    @Test func idsAreURLsLikeTheRealTree() {
        for item in ScreenshotDemoData.libraryTree {
            #expect(URL(string: item.id) != nil, "\(item.title) has an id that is not a URL")
        }
    }
}
