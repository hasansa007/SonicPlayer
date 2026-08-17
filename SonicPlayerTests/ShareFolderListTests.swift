import Foundation
import Testing

@testable import SonicPlayer

/// The folder list the app publishes for the share picker (#112 slice 3).
///
/// The extension cannot see `Documents/` — that blindness is what keeps it unable to damage the
/// library — so the picker is fed this instead. Every rule that decides what it contains is here,
/// testable without a filesystem; the walk that finds the URLs is `ShareFolderListWriter`.
@Suite("The published folder list")
struct ShareFolderListTests {

    private let documents = URL(fileURLWithPath: "/tmp/docs")

    private func folder(_ name: String) -> URL {
        documents.appendingPathComponent(name)
    }

    @Test func theRootLeadsAndAlwaysExists() {
        let folders = ShareFolderList.folders(under: documents, directories: [])
        #expect(folders.count == 1)
        #expect(folders.first?.relativePath == "", "the root's relative path is empty")
        #expect(folders.first?.path == MoveDestinations.rootTitle)
    }

    /// The display path is the whole path, not the leaf — `MoveDestinations`' rule, because two
    /// folders may share a name and the leaf alone would offer the same row twice.
    @Test func nestedFoldersShowTheirWholePath() {
        let folders = ShareFolderList.folders(
            under: documents, directories: [folder("البدعة"), folder("البدعة/Lectures")]
        )
        #expect(folders.map(\.path) == [
            MoveDestinations.rootTitle,
            "البدعة",
            "البدعة\(MoveDestinations.separator)Lectures",
        ])
    }

    /// The manifest carries a path relative to `Documents/`, because the extension has no business
    /// knowing the app's container path — it is not stable across installs.
    @Test func theRelativePathIsWhatTheManifestWillCarry() {
        let folders = ShareFolderList.folders(
            under: documents, directories: [folder("البدعة/Lectures")]
        )
        #expect(folders.last?.relativePath == "البدعة/Lectures")
    }

    /// A parent must precede its children, and the order must not move between writes — a picker
    /// whose rows shuffle between shares is its own bug.
    @Test func theOrderIsStableAndParentsComeFirst() {
        let shuffled = [folder("b/deep"), folder("a"), folder("b"), folder("a/inner")]
        let folders = ShareFolderList.folders(under: documents, directories: shuffled)
        #expect(folders.map(\.relativePath) == ["", "a", "a/inner", "b", "b/deep"])
    }

    /// Same guard as `ImportFilter.relativeDirectory`: a URL outside the library produces nothing
    /// rather than a path that climbs out of it.
    @Test func aDirectoryOutsideDocumentsIsDropped() {
        let folders = ShareFolderList.folders(
            under: documents, directories: [URL(fileURLWithPath: "/etc"), folder("Lectures")]
        )
        #expect(folders.map(\.relativePath) == ["", "Lectures"])
    }

    // MARK: - Reading it back

    @Test func aListSurvivesARoundTrip() throws {
        let folders = ShareFolderList.folders(under: documents, directories: [folder("Lectures")])
        let decoded = ShareFolderList.decode(try ShareFolderList.encode(folders))
        #expect(decoded == folders)
    }

    /// **The fresh-install case, and it is the common one rather than an edge.** The app may never
    /// have run, so nothing has published a list — and the very first share still has to work.
    /// Missing, truncated and corrupt all land here: refusing to show a picker because a cache is
    /// unreadable would block a share over a stale JSON file.
    @Test func anUnreadableListStillOffersTheRoot() {
        for data in [nil, Data(), Data("not json".utf8), Data("[]".utf8)] {
            let folders = ShareFolderList.decode(data)
            #expect(folders.count == 1, "always somewhere to file to")
            #expect(folders.first?.relativePath == "")
        }
    }
}
