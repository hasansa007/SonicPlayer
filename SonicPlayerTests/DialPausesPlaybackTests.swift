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
        var content = DialSample.content(recordingCount: 0, playback: DialSample.playback)
        content.sections = [
            .init(id: "record", icon: .recording, title: "Record", destination: .recording)
        ]
        var navigator = DialNavigator(content: content, root: .library)

        _ = navigator.receive(.press)               // the Record card opens the recorder
        let effects = navigator.receive(.press)     // and the hub starts the take

        #expect(effects.contains(.pausePlayback))
        #expect(
            effects.firstIndex(of: .pausePlayback)! < effects.firstIndex(of: .startRecording)!,
            "silence first — the microphone opens on the next effect"
        )
    }

    @Test func openingTheEditorPausesPlayback() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.doublePress)

        #expect(effects.contains(.pausePlayback))
    }

    /// The stick's up nudge opens the editor, and takes the same path as a double-press.
    @Test func theEditNudgePausesPlaybackToo() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.action("edit"))

        #expect(effects.contains(.pausePlayback))
    }

    /// Nothing playing means nothing to silence — an effect asking the host to pause silence would
    /// be a lie about what happened, and `DialPressTests` reads these arrays exactly.
    @Test func nothingPlayingAsksForNoPause() {
        var content = DialSample.content(recordingCount: 0, playback: nil)
        content.sections = [
            .init(id: "record", icon: .recording, title: "Record", destination: .recording)
        ]
        var navigator = DialNavigator(content: content, root: .library)

        _ = navigator.receive(.press)
        let effects = navigator.receive(.press)

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
