import Synchronization
import SwiftUI
import Foundation
import Testing

@testable import SonicPlayer

/// #12's claim is that the five clients can be constructed and substituted without any TCA
/// machinery. These tests are the demonstration: no `TestStore`, no `withDependencies`, no
/// `@Dependency` — the clients are called directly as the plain structs of closures they are.
///
/// Deliberately no `import ComposableArchitecture` in this file. If a future change makes one
/// necessary here, the seam has regressed. (SwiftUI is imported only for `Color`, which the
/// artwork client's palette is expressed in — unrelated to the dependency machinery.)
@Suite(.serialized)
struct ClientSubstitutionTests {

    // MARK: - .test is a usable stand-in

    @Test func test_trimmerTestValue_isIdentity() async throws {
        let url = URL(fileURLWithPath: "/Docs/A.m4a")
        let trimmed = try await AudioTrimmerClient.test.trimAudio(url, 0, 10)
        let deleted = try await AudioTrimmerClient.test.deleteAudioRange(url, 0, 10)
        #expect(trimmed == url)
        #expect(deleted == url)
    }

    @Test func test_recorderTestValue_reportsNoPermissionSideEffects() async {
        // Hoisted from the XCTest original, where XCTAssert*'s autoclosure could not contain
        // `await`. #expect has no such limit, but the bindings read better than inlining.
        let hasPermission = await AudioRecorderClient.test.checkPermissions()
        let isRecording = await AudioRecorderClient.test.isRecording()
        let currentTime = await AudioRecorderClient.test.currentTime()

        #expect(hasPermission)
        #expect(!(isRecording))
        #expect(currentTime == 0)
    }

    /// `getColors` does not return "nothing" when stubbed — it honours the caller's fallback,
    /// and falls back to the sonic teal palette when none is given. Callers rely on getting a
    /// usable palette rather than an empty array, so a stub returning `[]` would be the wrong
    /// stand-in.
    @Test func test_artworkTestValue_yieldsTheCallersFallbackPalette() async {
        let url = URL(fileURLWithPath: "/Docs/A.mp3")
        let artwork = await ArtworkClient.test.getArtwork(url)
        let defaulted = await ArtworkClient.test.getColors(url, false, nil)
        let supplied = await ArtworkClient.test.getColors(url, false, [.red, .green])

        #expect(artwork == nil, "no image without touching disk")
        #expect(defaulted == Color.sonicTealColors)
        #expect(supplied == [.red, .green])
    }

    // MARK: - substitution needs no framework

    /// The point of the struct-of-closures shape: a caller takes the client as a value, and a
    /// test hands it a different one. This is what replaces `@Dependency` in slices 4 onward.
    @Test func test_aClientCanBeSubstitutedByPlainAssignment() async throws {
        // The client's `trimAudio` closure is `@Sendable`, so the spy it writes to must be
        // concurrency-safe — a plain captured `var` is a data race under Swift 6.
        let spyCalledWith = Mutex<URL?>(nil)
        var client = AudioTrimmerClient.test
        client.trimAudio = { url, _, _ in
            spyCalledWith.withLock { $0 = url }
            return URL(fileURLWithPath: "/Docs/trimmed.m4a")
        }

        let result = try await client.trimAudio(URL(fileURLWithPath: "/Docs/original.m4a"), 1, 2)

        #expect(spyCalledWith.withLock { $0?.lastPathComponent } == "original.m4a")
        #expect(result.lastPathComponent == "trimmed.m4a")
    }

    // MARK: - .live is constructible

    /// Not exercised — `live` wraps AVFoundation and the real filesystem. This only asserts it
    /// can be built, which is what proves the TCA bridge is not load-bearing for construction.
    @Test func test_liveClientsAreConstructibleWithoutTheDependencyMachinery() {
        #expect(AudioTrimmerClient.live.trimAudio != nil)
        #expect(AudioRecorderClient.live.startRecording != nil)
        #expect(ArtworkClient.live.getArtwork != nil)
        #expect(FileManagerClient.live.listItems != nil)
        #expect(AudioPlayerClient.live.play != nil)
    }

    /// The player client wraps a process-lifetime AudioPlayerManager that PlayerFeature and
    /// EditRecordingFeature deliberately share. Extracting `live` must not have turned that into
    /// two instances — #15 depends on the sharing being preserved, warts and all.
    @Test func test_thePlayerClientIsStillASingleSharedInstance() async {
        let a = AudioPlayerClient.live
        let b = AudioPlayerClient.live
        await a.seek(12)
        // Both handles reach the same manager; if `live` were recomputed per access this would
        // be observably different state rather than the same underlying player.
        let fromA = await a.currentTime()
        let fromB = await b.currentTime()

        #expect(fromA == fromB)
    }
}
