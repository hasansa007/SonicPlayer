import Foundation
import Testing

@testable import SonicPlayer

/// The recursive import was ~130 lines inside a single effect and had **no test**, because every
/// line of it was tangled with security-scoped URLs and `FileManager`. These are the two decisions
/// inside it that need no I/O — and they are the two that silently lose a user's files when wrong.
@Suite
struct ImportFilterTests {

    // MARK: - What counts as audio

    @Test func test_theAcceptedExtensions_areUnchanged() {
        #expect(ImportFilter.audioExtensions == [
            "mp3", "m4a", "wav", "aac", "flac", "aiff", "m4b", "mp4", "opus", "ogg"
        ])
    }

    @Test func test_matchingIsCaseInsensitive() {
        #expect(ImportFilter.isAudio(URL(fileURLWithPath: "/x/Track.MP3")))
        #expect(ImportFilter.isAudio(URL(fileURLWithPath: "/x/Track.mp3")))
        #expect(ImportFilter.isAudio(URL(fileURLWithPath: "/x/Track.M4a")))
    }

    @Test func test_nonAudioIsRejected() {
        #expect(!ImportFilter.isAudio(URL(fileURLWithPath: "/x/cover.jpg")))
        #expect(!ImportFilter.isAudio(URL(fileURLWithPath: "/x/notes.txt")))
        #expect(!ImportFilter.isAudio(URL(fileURLWithPath: "/x/no-extension")))
    }

    // MARK: - iOS's staging directory (#41)

    private let documents = URL(fileURLWithPath: "/Container/Documents")

    @Test func test_theStagingDirectoryIsRecognised() {
        #expect(ImportFilter.isStagingDirectory(documents.appendingPathComponent("Inbox"), under: documents))
    }

    /// The browser must hide iOS's queue and nothing else. A user is entitled to a collection
    /// called `Inbox` one level down, and it is theirs.
    @Test func test_onlyTheRootInboxIsTheStagingDirectory() {
        #expect(!ImportFilter.isStagingDirectory(documents.appendingPathComponent("Lectures"), under: documents))
        #expect(!ImportFilter.isStagingDirectory(documents.appendingPathComponent("Lectures/Inbox"), under: documents))
        #expect(!ImportFilter.isStagingDirectory(documents.appendingPathComponent("Inbox Recordings"), under: documents))
    }

    @Test func test_aFileInsideTheStagingDirectoryIsStaged() {
        #expect(ImportFilter.isStaged(documents.appendingPathComponent("Inbox/Track.mp3"), under: documents))
        #expect(ImportFilter.isStaged(documents.appendingPathComponent("Inbox/Track-1.mp3"), under: documents))
    }

    /// The data-loss guard. `LSSupportsOpeningDocumentsInPlace` means the handed-over URL is often
    /// the user's own file in iCloud Drive — treating it as staged would MOVE it out of their
    /// storage, so every one of these must be false.
    @Test func test_aFileOutsideTheStagingDirectoryIsNotStaged() {
        #expect(!ImportFilter.isStaged(documents.appendingPathComponent("Track.mp3"), under: documents))
        #expect(!ImportFilter.isStaged(documents.appendingPathComponent("Lectures/Track.mp3"), under: documents))
        #expect(!ImportFilter.isStaged(URL(fileURLWithPath: "/Elsewhere/iCloud/Track.mp3"), under: documents))
    }

    /// The prefix trap `PathMatching` exists to avoid, reached through this door: a sibling
    /// directory whose name merely *starts* with `Inbox` is not the staging area, and a file in it
    /// is the user's.
    @Test func test_aSiblingWhoseNameStartsWithInboxIsNotStaged() {
        #expect(!ImportFilter.isStaged(documents.appendingPathComponent("Inbox Recordings/Track.mp3"), under: documents))
    }

    /// The extension is matched whole. A file called `song.mp3.bak` is not audio, and one called
    /// `.mp3` — an extensionless dotfile — is not either.
    @Test func test_theExtensionIsMatchedWhole() {
        #expect(!ImportFilter.isAudio(URL(fileURLWithPath: "/x/song.mp3.bak")))
        #expect(!ImportFilter.isAudio(URL(fileURLWithPath: "/x/notmp3")))
    }

    // MARK: - Where a nested file lands

    @Test func test_aFileAtTheRootHasNoSubdirectory() {
        let root = URL(fileURLWithPath: "/Import/Album")
        let file = URL(fileURLWithPath: "/Import/Album/01.mp3")
        #expect(ImportFilter.relativeDirectory(of: file, under: root) == nil)
    }

    @Test func test_aNestedFileKeepsItsSubdirectory() {
        let root = URL(fileURLWithPath: "/Import/Album")
        let file = URL(fileURLWithPath: "/Import/Album/Disc 1/01.mp3")
        #expect(ImportFilter.relativeDirectory(of: file, under: root) == "Disc 1")
    }

    @Test func test_deeplyNestedKeepsTheWholePath() {
        let root = URL(fileURLWithPath: "/Import/Album")
        let file = URL(fileURLWithPath: "/Import/Album/Disc 1/Bonus/03.mp3")
        #expect(ImportFilter.relativeDirectory(of: file, under: root) == "Disc 1/Bonus")
    }

    /// A file outside the import root has no answer. Returning a path here would let an import
    /// write outside its destination — the reason this returns optional rather than a String.
    @Test func test_aFileOutsideTheRootHasNoAnswer() {
        let root = URL(fileURLWithPath: "/Import/Album")
        #expect(ImportFilter.relativeDirectory(of: URL(fileURLWithPath: "/Elsewhere/01.mp3"), under: root) == nil)
    }

    /// A sibling sharing a name prefix is outside the root — `/Import/Album2` is not in
    /// `/Import/Album`. Same class of bug `PathMatching` exists to avoid.
    @Test func test_aSiblingSharingANamePrefixIsOutside() {
        let root = URL(fileURLWithPath: "/Import/Album")
        let file = URL(fileURLWithPath: "/Import/Album2/01.mp3")
        #expect(ImportFilter.relativeDirectory(of: file, under: root) == nil)
    }
}
