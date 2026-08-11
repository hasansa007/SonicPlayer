import Foundation
import Testing

@testable import SonicPlayer

/// Characterization tests for the "is the playing track affected?" predicate, previously
/// duplicated byte-for-byte at three sites in AppFeature. No TCA, no filesystem — these must
/// survive the whole migration unchanged.
@Suite
struct PathMatchingTests {

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test func test_theTrackItself_isAffected() {
        #expect(PathMatching.isAffected(trackURL: url("/Docs/Podcasts/Ep1.mp3"), byItemAt: url("/Docs/Podcasts/Ep1.mp3")))
    }

    @Test func test_aTrackInsideTheFolder_isAffected() {
        #expect(PathMatching.isAffected(trackURL: url("/Docs/Podcasts/Ep1.mp3"), byItemAt: url("/Docs/Podcasts")))
    }

    @Test func test_aTrackDeeplyNested_isAffected() {
        #expect(PathMatching.isAffected(trackURL: url("/Docs/Podcasts/2026/Q1/Ep1.mp3"), byItemAt: url("/Docs/Podcasts")))
    }

    @Test func test_anUnrelatedTrack_isNotAffected() {
        #expect(!(PathMatching.isAffected(trackURL: url("/Docs/Music/Song.mp3"), byItemAt: url("/Docs/Podcasts"))))
    }

    /// The reason the implementation appends a separator before comparing. Without it,
    /// deleting "Rock" would clear the session for a track playing inside "Rocks".
    @Test func test_aSiblingFolderSharingAPrefix_isNotAffected() {
        #expect(!(PathMatching.isAffected(trackURL: url("/Docs/Rocks/Song.mp3"), byItemAt: url("/Docs/Rock"))))
    }

    @Test func test_theParentOfTheItem_isNotAffected() {
        #expect(!(PathMatching.isAffected(trackURL: url("/Docs/Song.mp3"), byItemAt: url("/Docs/Podcasts"))))
    }

    // MARK: - Sets

    @Test func test_anyOf_matchesWhenOneItemAffects() {
        #expect(PathMatching.isAffected(trackURL: url("/Docs/Podcasts/Ep1.mp3"), byAnyOf: [url("/Docs/Music"), url("/Docs/Podcasts"), url("/Docs/Notes")]))
    }

    @Test func test_anyOf_isFalseWhenNothingAffects() {
        #expect(!(PathMatching.isAffected(trackURL: url("/Docs/Podcasts/Ep1.mp3"), byAnyOf: [url("/Docs/Music"), url("/Docs/Notes")])))
    }

    @Test func test_anyOf_isFalseForAnEmptySelection() {
        #expect(!(PathMatching.isAffected(trackURL: url("/Docs/Podcasts/Ep1.mp3"), byAnyOf: [URL]())))
    }
}
