import XCTest

@testable import SonicPlayer

/// Characterization tests for the dedupe algorithm that was inlined at seven call sites
/// before #11. These import no TCA and touch no filesystem, so they must survive the whole
/// TCA -> MVVM migration unchanged — that is the point of extracting `Domain/` at all.
final class UniqueNameResolverTests: XCTestCase {

    private let dir = URL(fileURLWithPath: "/Library")

    /// `exists` returns true for exactly the given names.
    private func taken(_ names: String...) -> (URL) -> Bool {
        let set = Set(names)
        return { set.contains($0.lastPathComponent) }
    }

    // MARK: - Folders (no extension)

    func test_folder_noCollision_keepsName() {
        let url = UniqueNameResolver.resolve(baseName: "Podcasts", in: dir, exists: taken())
        XCTAssertEqual(url.lastPathComponent, "Podcasts")
    }

    func test_folder_firstCollision_suffixesWithTwo() {
        let url = UniqueNameResolver.resolve(baseName: "Podcasts", in: dir, exists: taken("Podcasts"))
        XCTAssertEqual(url.lastPathComponent, "Podcasts 2")
    }

    func test_folder_runOfCollisions_walksUpward() {
        let url = UniqueNameResolver.resolve(
            baseName: "Podcasts", in: dir,
            exists: taken("Podcasts", "Podcasts 2", "Podcasts 3")
        )
        XCTAssertEqual(url.lastPathComponent, "Podcasts 4")
    }

    // MARK: - Files (extension-aware)

    func test_file_collision_suffixesBeforeTheExtension() {
        let url = UniqueNameResolver.resolve(
            baseName: "Lecture", ext: "m4a", in: dir,
            exists: taken("Lecture.m4a")
        )
        XCTAssertEqual(url.lastPathComponent, "Lecture 2.m4a")
    }

    func test_file_emptyExtension_behavesLikeAFolder() {
        let url = UniqueNameResolver.resolve(
            baseName: "README", ext: "", in: dir,
            exists: taken("README")
        )
        XCTAssertEqual(url.lastPathComponent, "README 2")
    }

    func test_file_dottedBaseName_onlyTheRealExtensionIsPreserved() {
        let url = UniqueNameResolver.resolve(
            baseName: "Ep.42 - Intro", ext: "mp3", in: dir,
            exists: taken("Ep.42 - Intro.mp3")
        )
        XCTAssertEqual(url.lastPathComponent, "Ep.42 - Intro 2.mp3")
    }

    // MARK: - Self-exclusion (RecordingFeature.saveRecording)

    func test_excludedURL_isNotTreatedAsACollision() {
        let original = dir.appendingPathComponent("Recording.m4a")
        let url = UniqueNameResolver.resolve(
            baseName: "Recording", ext: "m4a", in: dir,
            excluding: original,
            exists: taken("Recording.m4a")
        )
        XCTAssertEqual(
            url, original,
            "Saving a recording under its own name must keep the name, not produce 'Recording 2.m4a'."
        )
    }

    func test_excludedURL_stillDedupesAgainstOtherFiles() {
        let elsewhere = dir.appendingPathComponent("Something Else.m4a")
        let url = UniqueNameResolver.resolve(
            baseName: "Recording", ext: "m4a", in: dir,
            excluding: elsewhere,
            exists: taken("Recording.m4a")
        )
        XCTAssertEqual(url.lastPathComponent, "Recording 2.m4a")
    }

    // MARK: - Iteration cap (CollectionsFeature.moveToDestination)

    func test_limit_bailsOutAndReturnsACollidingURL() {
        // Everything collides. This pins the pre-existing bail-out: on reaching the cap the
        // caller receives a URL that DOES collide, and its moveItem then throws. Preserved
        // deliberately rather than fixed, so the extraction stays behaviour-preserving.
        let url = UniqueNameResolver.resolve(
            baseName: "Track", ext: "m4a", in: dir,
            limit: 3,
            exists: { _ in true }
        )
        XCTAssertEqual(url.lastPathComponent, "Track 3.m4a")
    }

    func test_noLimit_keepsWalkingPastTheOldHardCodedCap() {
        let existing = Set((2...150).map { "Track \($0).m4a" } + ["Track.m4a"])
        let url = UniqueNameResolver.resolve(
            baseName: "Track", ext: "m4a", in: dir,
            exists: { existing.contains($0.lastPathComponent) }
        )
        XCTAssertEqual(url.lastPathComponent, "Track 151.m4a")
    }
}
