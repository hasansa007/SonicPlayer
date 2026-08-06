import XCTest

@testable import SonicPlayer

/// Characterization tests for the "is the playing track affected?" predicate, previously
/// duplicated byte-for-byte at three sites in AppFeature. No TCA, no filesystem — these must
/// survive the whole migration unchanged.
final class PathMatchingTests: XCTestCase {

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    func test_theTrackItself_isAffected() {
        XCTAssertTrue(
            PathMatching.isAffected(
                trackURL: url("/Docs/Podcasts/Ep1.mp3"),
                byItemAt: url("/Docs/Podcasts/Ep1.mp3")
            )
        )
    }

    func test_aTrackInsideTheFolder_isAffected() {
        XCTAssertTrue(
            PathMatching.isAffected(
                trackURL: url("/Docs/Podcasts/Ep1.mp3"),
                byItemAt: url("/Docs/Podcasts")
            )
        )
    }

    func test_aTrackDeeplyNested_isAffected() {
        XCTAssertTrue(
            PathMatching.isAffected(
                trackURL: url("/Docs/Podcasts/2026/Q1/Ep1.mp3"),
                byItemAt: url("/Docs/Podcasts")
            )
        )
    }

    func test_anUnrelatedTrack_isNotAffected() {
        XCTAssertFalse(
            PathMatching.isAffected(
                trackURL: url("/Docs/Music/Song.mp3"),
                byItemAt: url("/Docs/Podcasts")
            )
        )
    }

    /// The reason the implementation appends a separator before comparing. Without it,
    /// deleting "Rock" would clear the session for a track playing inside "Rocks".
    func test_aSiblingFolderSharingAPrefix_isNotAffected() {
        XCTAssertFalse(
            PathMatching.isAffected(
                trackURL: url("/Docs/Rocks/Song.mp3"),
                byItemAt: url("/Docs/Rock")
            )
        )
    }

    func test_theParentOfTheItem_isNotAffected() {
        XCTAssertFalse(
            PathMatching.isAffected(
                trackURL: url("/Docs/Song.mp3"),
                byItemAt: url("/Docs/Podcasts")
            )
        )
    }

    // MARK: - Sets

    func test_anyOf_matchesWhenOneItemAffects() {
        XCTAssertTrue(
            PathMatching.isAffected(
                trackURL: url("/Docs/Podcasts/Ep1.mp3"),
                byAnyOf: [url("/Docs/Music"), url("/Docs/Podcasts"), url("/Docs/Notes")]
            )
        )
    }

    func test_anyOf_isFalseWhenNothingAffects() {
        XCTAssertFalse(
            PathMatching.isAffected(
                trackURL: url("/Docs/Podcasts/Ep1.mp3"),
                byAnyOf: [url("/Docs/Music"), url("/Docs/Notes")]
            )
        )
    }

    func test_anyOf_isFalseForAnEmptySelection() {
        XCTAssertFalse(
            PathMatching.isAffected(trackURL: url("/Docs/Podcasts/Ep1.mp3"), byAnyOf: [URL]())
        )
    }
}
