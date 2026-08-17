import Foundation
import Testing

@testable import SonicPlayer

/// The folder list the app publishes for the share picker (#112 slice 3).
///
/// The extension cannot see `Documents/` — that blindness is what keeps it unable to damage the
/// library — so the picker is fed this instead.
///
/// **Derived from the library tree, not from a filesystem walk**, and these tests take a tree for
/// that reason. The walking version cost four defects at once: a synchronous recursion of the whole
/// library on the main actor twice per app switch, a symlink cycle that hung the app, a
/// `.skipsPackageDescendants` flag that does nothing on `contentsOfDirectory`, and an alphabetical
/// order that disagreed with the app's own Move screen.
@Suite("The published folder list")
struct ShareFolderListTests {

    private let documents = URL(fileURLWithPath: "/tmp/docs")

    /// A folder as the dial tree carries it: its id **is** its URL string.
    private func folder(_ relativePath: String, children: [DialContent.Item] = []) -> DialContent.Item {
        DialContent.Item(
            id: documents.appendingPathComponent(relativePath).absoluteString,
            title: (relativePath as NSString).lastPathComponent,
            duration: 0,
            children: children
        )
    }

    private func file(_ name: String) -> DialContent.Item {
        DialContent.Item(
            id: documents.appendingPathComponent(name).absoluteString,
            title: name, duration: 0, children: nil     // nil children == a file
        )
    }

    @Test func theRootLeadsAndAlwaysExists() {
        let folders = ShareFolderList.folders(under: documents, items: [])
        #expect(folders.count == 1)
        #expect(folders.first?.relativePath == "", "the root's relative path is empty")
        #expect(folders.first?.path == MoveDestinations.rootTitle)
    }

    /// The display path is the whole path, not the leaf — two folders may share a name and the leaf
    /// alone would offer the same row twice.
    @Test func nestedFoldersShowTheirWholePath() {
        let tree = [folder("البدعة", children: [folder("البدعة/Lectures")])]
        let folders = ShareFolderList.folders(under: documents, items: tree)

        #expect(folders.map(\.path) == [
            MoveDestinations.rootTitle,
            "البدعة",
            "البدعة\(MoveDestinations.separator)Lectures",
        ])
    }

    /// The manifest carries a path relative to `Documents/`; the extension has no business knowing
    /// the app's container path, which is not stable across installs.
    @Test func theRelativePathIsWhatTheManifestWillCarry() {
        let tree = [folder("البدعة", children: [folder("البدعة/Lectures")])]
        let folders = ShareFolderList.folders(under: documents, items: tree)

        #expect(folders.map(\.relativePath) == ["", "البدعة", "البدعة/Lectures"])
    }

    /// **The picker and the Move screen must agree**, and the walking version did not: it sorted
    /// alphabetically while `LibraryTree` sorts folders newest-created-first. Taking the tree's own
    /// order is what makes "read as one idea" true rather than asserted.
    @Test func theOrderIsWhateverTheLibraryTreeSays() {
        let tree = [folder("Zulu"), folder("Alpha"), folder("Mike")]
        let folders = ShareFolderList.folders(under: documents, items: tree)

        #expect(
            folders.map(\.relativePath) == ["", "Zulu", "Alpha", "Mike"],
            "the tree's order is preserved, not re-sorted behind the app's back"
        )
    }

    /// Files are not destinations.
    @Test func onlyFoldersAreOffered() {
        let tree = [folder("Lectures"), file("Recording.m4a")]
        let folders = ShareFolderList.folders(under: documents, items: tree)

        #expect(folders.map(\.relativePath) == ["", "Lectures"])
    }

    /// Same guard as `ImportFilter.relativeDirectory`: anything that does not resolve under the
    /// library is dropped rather than turned into a path that climbs out of it.
    @Test func anItemOutsideDocumentsIsDropped() {
        let outside = DialContent.Item(
            id: URL(fileURLWithPath: "/etc/passwd").absoluteString,
            title: "elsewhere", duration: 0, children: []
        )
        let folders = ShareFolderList.folders(under: documents, items: [outside, folder("Lectures")])

        #expect(folders.map(\.relativePath) == ["", "Lectures"])
    }

    // MARK: - Reading it back
    //
    // There is deliberately no `decode` test, because there is no `decode`. The app writes this file
    // and never reads it; the only reader is the extension's own `loadFolders`, in a target this
    // suite cannot link. `ShareInboxLayoutAgreementTests` asserts its fallback policy by reading the
    // source, which is the only thing both targets demonstrably share.

    @Test func aListEncodesToTheShapeTheExtensionDecodes() throws {
        let folders = ShareFolderList.folders(under: documents, items: [folder("Lectures")])
        let objects = try JSONSerialization.jsonObject(with: ShareFolderList.encode(folders))

        let rows = objects as? [[String: Any]]
        #expect(rows?.count == 2)
        #expect(Set(rows?.first?.keys.map { $0 } ?? []) == ["path", "relativePath"])
    }
}
