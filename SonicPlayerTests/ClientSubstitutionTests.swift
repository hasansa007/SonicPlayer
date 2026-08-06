import SwiftUI
import XCTest

@testable import SonicPlayer

/// #12's claim is that the five clients can be constructed and substituted without any TCA
/// machinery. These tests are the demonstration: no `TestStore`, no `withDependencies`, no
/// `@Dependency` — the clients are called directly as the plain structs of closures they are.
///
/// Deliberately no `import ComposableArchitecture` in this file. If a future change makes one
/// necessary here, the seam has regressed. (SwiftUI is imported only for `Color`, which the
/// artwork client's palette is expressed in — unrelated to the dependency machinery.)
final class ClientSubstitutionTests: XCTestCase {

    // MARK: - .test is a usable stand-in

    func test_trimmerTestValue_isIdentity() async throws {
        let url = URL(fileURLWithPath: "/Docs/A.m4a")
        let trimmed = try await AudioTrimmerClient.test.trimAudio(url, 0, 10)
        let deleted = try await AudioTrimmerClient.test.deleteAudioRange(url, 0, 10)
        XCTAssertEqual(trimmed, url)
        XCTAssertEqual(deleted, url)
    }

    func test_recorderTestValue_reportsNoPermissionSideEffects() async {
        // XCTAssert* take autoclosures, which cannot contain `await` — hoist first.
        let hasPermission = await AudioRecorderClient.test.checkPermissions()
        let isRecording = await AudioRecorderClient.test.isRecording()
        let currentTime = await AudioRecorderClient.test.currentTime()

        XCTAssertTrue(hasPermission)
        XCTAssertFalse(isRecording)
        XCTAssertEqual(currentTime, 0)
    }

    /// `getColors` does not return "nothing" when stubbed — it honours the caller's fallback,
    /// and falls back to the sonic teal palette when none is given. Callers rely on getting a
    /// usable palette rather than an empty array, so a stub returning `[]` would be the wrong
    /// stand-in.
    func test_artworkTestValue_yieldsTheCallersFallbackPalette() async {
        let url = URL(fileURLWithPath: "/Docs/A.mp3")
        let artwork = await ArtworkClient.test.getArtwork(url)
        let defaulted = await ArtworkClient.test.getColors(url, false, nil)
        let supplied = await ArtworkClient.test.getColors(url, false, [.red, .green])

        XCTAssertNil(artwork, "no image without touching disk")
        XCTAssertEqual(defaulted, Color.sonicTealColors)
        XCTAssertEqual(supplied, [.red, .green])
    }

    // MARK: - substitution needs no framework

    /// The point of the struct-of-closures shape: a caller takes the client as a value, and a
    /// test hands it a different one. This is what replaces `@Dependency` in slices 4 onward.
    func test_aClientCanBeSubstitutedByPlainAssignment() async throws {
        var spyCalledWith: URL?
        var client = AudioTrimmerClient.test
        client.trimAudio = { url, _, _ in
            spyCalledWith = url
            return URL(fileURLWithPath: "/Docs/trimmed.m4a")
        }

        let result = try await client.trimAudio(URL(fileURLWithPath: "/Docs/original.m4a"), 1, 2)

        XCTAssertEqual(spyCalledWith?.lastPathComponent, "original.m4a")
        XCTAssertEqual(result.lastPathComponent, "trimmed.m4a")
    }

    // MARK: - .live is constructible

    /// Not exercised — `live` wraps AVFoundation and the real filesystem. This only asserts it
    /// can be built, which is what proves the TCA bridge is not load-bearing for construction.
    func test_liveClientsAreConstructibleWithoutTheDependencyMachinery() {
        XCTAssertNotNil(AudioTrimmerClient.live.trimAudio)
        XCTAssertNotNil(AudioRecorderClient.live.startRecording)
        XCTAssertNotNil(ArtworkClient.live.getArtwork)
        XCTAssertNotNil(FileManagerClient.live.listItems)
        XCTAssertNotNil(AudioPlayerClient.live.play)
    }

    /// The player client wraps a process-lifetime AudioPlayerManager that PlayerFeature and
    /// EditRecordingFeature deliberately share. Extracting `live` must not have turned that into
    /// two instances — #15 depends on the sharing being preserved, warts and all.
    func test_thePlayerClientIsStillASingleSharedInstance() async {
        let a = AudioPlayerClient.live
        let b = AudioPlayerClient.live
        await a.seek(12)
        // Both handles reach the same manager; if `live` were recomputed per access this would
        // be observably different state rather than the same underlying player.
        let fromA = await a.currentTime()
        let fromB = await b.currentTime()

        XCTAssertEqual(fromA, fromB)
    }
}
