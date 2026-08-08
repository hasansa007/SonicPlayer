import Foundation
import Testing

@testable import SonicPlayer

/// The folder name shown beside a file on Home (#48).
///
/// Extracted from `MediaFileRowView.collectionName(for:)`, a `private static func` on a view that
/// reached `FileManager.default` to find the documents directory. Same shape of problem as the
/// one #44 took out of `restoreSession`: a decision the app makes on every row, wrapped in an
/// I/O call no test could reach.
@Suite
struct CollectionLabelTests {

    private let documents = URL(fileURLWithPath: "/Docs")

    @Test func test_aFileInTheRoot_hasNoCollectionLabel() {
        let file = documents.appendingPathComponent("Lecture 3.mp3")

        #expect(CollectionLabel.name(for: file, documentsURL: documents) == nil)
    }

    @Test func test_aFileInAFolder_isLabelledWithThatFolder() {
        let file = documents.appendingPathComponent("Term 1/Lecture 3.mp3")

        #expect(CollectionLabel.name(for: file, documentsURL: documents) == "Term 1")
    }

    /// Only the immediate parent is the label — a nested file is not announced by its grandparent.
    @Test func test_aNestedFile_isLabelledWithItsImmediateParent() {
        let file = documents.appendingPathComponent("Term 1/Week 2/Lecture 3.mp3")

        #expect(CollectionLabel.name(for: file, documentsURL: documents) == "Week 2")
    }

    /// The reason this is worth extracting rather than inlining. On device the documents URL is
    /// `/var/mobile/.../Documents` while a file URL that has been through a security-scoped
    /// bookmark can arrive as `/private/var/mobile/.../Documents/x.mp3` — the same directory by
    /// two names. Comparing them unresolved makes the root look like a collection, and every
    /// file in it gets labelled with the name of the root folder.
    ///
    /// The symlink is **created by the test** rather than borrowed from the platform.
    /// `resolvingSymlinksInPath()` only resolves components that actually exist, and the
    /// simulator's temporary directory lives inside its own data container with no `/var` link
    /// in the path — so relying on the ambient filesystem makes this pass or fail for reasons
    /// that have nothing to do with the rule under test.
    @Test func test_aRootReachedThroughASymlink_isStillRecognisedAsTheRoot() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("CollectionLabel-\(UUID().uuidString)")
        let real = base.appendingPathComponent("Documents")
        let link = base.appendingPathComponent("DocumentsLink")
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? fm.removeItem(at: base) }

        // The app knows the root by one name; the file arrives under the other.
        #expect(
            CollectionLabel.name(for: link.appendingPathComponent("Lecture 3.mp3"), documentsURL: real) == nil,
            "A root file must not be labelled with the documents folder itself (#48)."
        )
        #expect(
            CollectionLabel.name(for: real.appendingPathComponent("Lecture 3.mp3"), documentsURL: link) == nil
        )

        // And a genuine collection under the aliased root is still labelled.
        try fm.createDirectory(at: real.appendingPathComponent("Term 1"), withIntermediateDirectories: true)
        #expect(
            CollectionLabel.name(for: link.appendingPathComponent("Term 1/Lecture 3.mp3"), documentsURL: real) == "Term 1"
        )
    }

    @Test func test_aFolderNameWithSpacesAndPunctuation_isReturnedVerbatim() {
        let file = documents.appendingPathComponent("Prof. Ahmed — Term 1/Lecture 3.mp3")

        #expect(CollectionLabel.name(for: file, documentsURL: documents) == "Prof. Ahmed — Term 1")
    }
}
