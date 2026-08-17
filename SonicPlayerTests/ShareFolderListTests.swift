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

    /// **A sibling must not come between a parent and its own child**, which sorting the raw path
    /// string does: every character below `/` (0x2F) sorts before it, so `Lectures 2024` landed
    /// between `Lectures` and `Lectures/Week 1` and the flat list stopped reading as a tree exactly
    /// where it matters.
    @Test func aSiblingNeverSplitsAParentFromItsChild() {
        let folders = ShareFolderList.folders(
            under: documents,
            directories: [folder("Lectures"), folder("Lectures 2024"), folder("Lectures/Week 1")]
        )
        #expect(folders.map(\.relativePath) == ["", "Lectures", "Lectures/Week 1", "Lectures 2024"])
    }

    /// Nine locales and a library filed in Arabic — ordering by unicode scalar is the kind of thing
    /// that looks fine to whoever wrote it and wrong to whoever uses it. `localizedStandardCompare`
    /// is what Finder uses, and it also gets 2 before 10.
    @Test func orderingIsHowAReaderWouldOrderIt() {
        let folders = ShareFolderList.folders(
            under: documents,
            directories: [folder("Lecture 10"), folder("Lecture 2")]
        )
        #expect(
            folders.map(\.relativePath) == ["", "Lecture 2", "Lecture 10"],
            "2 before 10 — scalar ordering puts '10' first because '1' < '2'"
        )
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
    //
    // There is deliberately no `decode` test here, because there is no `decode`. The app writes this
    // file and never reads it; the only reader is the extension's own `loadFolders`, in a target
    // this suite cannot link. Testing an app-side copy would have proved nothing about the behaviour
    // a user meets — and the two copies had already drifted on the root title before anyone noticed.
    // `ShareInboxLayoutAgreementTests` asserts the extension's fallback policy by reading its source.

    @Test func aListEncodesToTheShapeTheExtensionDecodes() throws {
        let folders = ShareFolderList.folders(under: documents, directories: [folder("Lectures")])
        let objects = try JSONSerialization.jsonObject(with: ShareFolderList.encode(folders))

        let rows = objects as? [[String: Any]]
        #expect(rows?.count == 2)
        #expect(Set(rows?.first?.keys.map { $0 } ?? []) == ["path", "relativePath"])
    }
}
