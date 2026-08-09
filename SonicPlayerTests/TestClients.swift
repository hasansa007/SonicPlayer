import Foundation
import SwiftUI
import Testing

@testable import SonicPlayer

// The `.test` clients, which lived in the app target until #20.
//
// They were there because TCA's `DependencyKey` required a `testValue` alongside `liveValue`, so
// the test double had to be visible to the app. Removing the bridge removed that constraint, and
// test-only code has no business in the shipping binary.
//
// Moving them here also *restores* something the removal would otherwise have cost. Under
// `@DependencyClient`, a closure with no explicit default was **unimplemented**: calling one
// reported a test failure. That is not a nicety — three tests in `OpenFromFilesTests` failed with
// "Unimplemented: AudioPlayerClient.setRemoteHandlers / .duration / .timeUpdates", closures the
// path reached that the author had not realised. Hand-written no-ops would have let those tests
// pass while exercising less than they appeared to.
//
// The app target cannot report a test failure — it cannot import `Testing`. This target can, so
// the behaviour is reproduced here with `Issue.record`, which is what the macro did.

extension AudioPlayerClient {

    /// Every closure reports rather than silently succeeding. Stub the ones the path under test
    /// actually reaches; a stub you did not need is dead weight, and a call you did not stub is a
    /// path you did not know you were on.
    static var test: Self {
        Self(
            prepare: { _ in Issue.record("AudioPlayerClient.prepare is unimplemented") },
            play: { _ in Issue.record("AudioPlayerClient.play is unimplemented") },
            pause: { Issue.record("AudioPlayerClient.pause is unimplemented") },
            resume: { Issue.record("AudioPlayerClient.resume is unimplemented") },
            stop: { Issue.record("AudioPlayerClient.stop is unimplemented") },
            seek: { _ in Issue.record("AudioPlayerClient.seek is unimplemented") },
            setRate: { _ in Issue.record("AudioPlayerClient.setRate is unimplemented") },
            skipForward: { _ in Issue.record("AudioPlayerClient.skipForward is unimplemented") },
            skipBackward: { _ in Issue.record("AudioPlayerClient.skipBackward is unimplemented") },
            updateNowPlaying: { Issue.record("AudioPlayerClient.updateNowPlaying is unimplemented") },
            setRemoteHandlers: { _, _ in Issue.record("AudioPlayerClient.setRemoteHandlers is unimplemented") },
            currentTime: { Issue.record("AudioPlayerClient.currentTime is unimplemented"); return 0 },
            duration: { Issue.record("AudioPlayerClient.duration is unimplemented"); return 0 },
            isPlaying: { Issue.record("AudioPlayerClient.isPlaying is unimplemented"); return false },
            timeUpdates: {
                Issue.record("AudioPlayerClient.timeUpdates is unimplemented")
                return AsyncStream { $0.finish() }
            }
        )
    }
}

// The remaining four already stubbed every closure explicitly, so they move verbatim — the macro
// was never producing unimplemented behaviour for them.

extension AudioRecorderClient {
    static let test = Self(
        checkPermissions: { true },
        requestPermissions: { true },
        startRecording: { _ in },
        stopRecording: { nil },
        currentTime: { 0 },
        peakPower: { 0 },
        isRecording: { false }
    )
}

extension AudioTrimmerClient {
    static let test = Self(
        trimAudio: { url, _, _ in url },
        deleteAudioRange: { url, _, _ in url }
    )
}

extension ArtworkClient {
    static let test = Self(
        getArtwork: { _ in nil },
        getFolderArtwork: { _ in nil },
        getColors: { _, _, fallbackColors in fallbackColors ?? Color.sonicTealColors },
        clearCache: {},
        getCacheStats: { (0, 0) }
    )
}

extension FileManagerClient {
    static let test = Self(
        listItems: { _ in [] },
        createCollection: { _, _ in },
        createCollectionForImport: { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] },
        deleteItem: { _ in },
        moveItem: { _, _ in },
        renameItem: { _, _ in },
        importFile: { _, _ in },
        getMetadata: { url in
            AudioFile(
                url: url,
                title: "Test",
                duration: 0,
                fileSize: 0,
                format: .mp3,
                creationDate: Date()
            )
        },
        drainStagingDirectory: {},
        documentsDirectory: { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    )
}

extension HapticsClient {
    /// `fire` reports, so a test that reaches the wheel's feedback path without meaning to says so.
    /// `prepare` and `stop` are lifecycle no-ops that every path calls — reporting those would only
    /// ever produce noise, which is the failure mode the comment at the top of this file describes
    /// from the other direction.
    static var test: Self {
        Self(
            prepare: {},
            fire: { _ in Issue.record("HapticsClient.fire is unimplemented") },
            stop: {}
        )
    }
}
