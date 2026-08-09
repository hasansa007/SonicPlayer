import Foundation
import Testing

@testable import SonicPlayer

/// Opening the recorder or the trim editor silences what is playing (#6).
///
/// Both take the audio session: a capture with a lecture playing records the lecture through the
/// microphone, and the editor previews the region under the handles over the top of it. Both are
/// one press away from a list of things you were listening to.
///
/// **These lived in `DialImportRowTests.swift` and were deleted with it** when the Import row came
/// back out — two suites in one file, and only one of them was about Import. They are here now,
/// under their own name, where the next deletion cannot take them by accident.
@Suite
struct DialPausesPlaybackTests {

    @Test func startingARecordingPausesPlayback() {
        var navigator = DialSample.navigator(recordingCount: 0)
        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)           // the empty library

        let effects = navigator.receive(.action("record"))

        #expect(effects.contains(.pausePlayback))
        #expect(
            effects.firstIndex(of: .pausePlayback)! < effects.firstIndex(of: .startRecording)!,
            "silence first — the microphone opens on the next effect"
        )
    }

    /// The chip on the empty library takes the same path as the hub.
    @Test func theRecordChipPausesPlaybackToo() {
        var navigator = DialSample.navigator(recordingCount: 0)
        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)

        let effects = navigator.receive(.action("record"))

        #expect(effects.contains(.pausePlayback))
        #expect(effects.contains(.startRecording))
    }

    @Test func openingTheEditorPausesPlayback() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.doublePress)

        #expect(effects.contains(.pausePlayback))
    }

    @Test func theEditRowInTheActionsMenuPausesPlaybackToo() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.action("more"))
        _ = navigator.receive(.tick(1))         // Rename leads; Edit is second

        let effects = navigator.receive(.press)

        #expect(effects.contains(.pausePlayback))
    }

    /// Nothing playing means nothing to silence — an effect asking the host to pause silence would
    /// be a lie about what happened, and `DialPressTests` reads these arrays exactly.
    @Test func nothingPlayingAsksForNoPause() {
        var navigator = DialSample.navigator(recordingCount: 0, playback: nil)
        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)

        let effects = navigator.receive(.action("record"))

        #expect(!effects.contains(.pausePlayback))
        #expect(effects == [.startRecording, .feedback(.commit)])
    }

    /// The navigator marks its own copy paused in the same breath, rather than waiting for the host
    /// to answer — otherwise Now Playing still draws a pause glyph over audio that has stopped.
    @Test func theNavigatorStopsClaimingToPlayImmediately() {
        var navigator = DialSample.inRecordings()
        guard case .nowPlaying(let before) = nowPlayingContent(of: navigator) else {
            Issue.record("expected Now Playing")
            return
        }
        #expect(before.isPlaying)

        _ = navigator.receive(.doublePress)     // into the editor, which silences playback

        guard case .nowPlaying(let after) = nowPlayingContent(of: navigator) else {
            Issue.record("expected Now Playing")
            return
        }
        #expect(!after.isPlaying)
    }

    /// Now Playing's content without disturbing where the navigator is. `hold` would reach it too,
    /// but it pushes — and a test asserting what playback looks like should not also be asserting
    /// that it can navigate.
    private func nowPlayingContent(of navigator: DialNavigator) -> DialScreen.Content {
        var copy = navigator
        _ = copy.receive(.action("nowPlaying"))
        return copy.screen.content
    }
}
