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
