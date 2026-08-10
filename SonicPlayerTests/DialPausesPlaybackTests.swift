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

    /// **The silence now happens at the fork, one screen earlier than it used to.**
    ///
    /// This asserted that starting a take pauses playback, and force-unwrapped the index of
    /// `.pausePlayback` to prove it came first. After the mode split that array no longer contains
    /// it — entering Record releases the player, so by the time the recorder opens there is nothing
    /// playing left to pause — and the force unwrap **crashed the whole test process**, which is
    /// why suites with no connection to any of this were reported as failing.
    ///
    /// The guarantee has not weakened; it has moved earlier. Both halves are asserted below.
    @Test func enteringRecordModePausesPlaybackAndLetsGoOfIt() {
        let content = DialSample.content(recordingCount: 0, playback: DialSample.playback)
        var navigator = DialNavigator(content: content, root: .library)
        _ = navigator.receive(.tick(1))             // home → Record

        let effects = navigator.receive(.press)     // → the library, Record's verbs

        #expect(effects.contains(.pausePlayback))
        #expect(effects.contains(.releasePlayer))
        #expect(
            effects.firstIndex(of: .pausePlayback) ?? .max < effects.firstIndex(of: .releasePlayer) ?? .min,
            "silence first, then let go of the file"
        )
    }

    /// And the microphone opens onto a session nothing else is holding.
    @Test func byTheTimeTheTakeStartsThereIsNothingLeftToPause() {
        let content = DialSample.content(recordingCount: 0, playback: DialSample.playback)
        var navigator = DialNavigator(content: content, root: .library)
        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)
        _ = navigator.receive(.action("record"))    // the pinned Record opens the recorder

        let effects = navigator.receive(.press)     // and the hub starts the take

        #expect(effects == [.startRecording, .feedback(.commit)])
    }

    /// The editor is the other screen that takes the session, and it is reached the same way — so
    /// the same release covers it. Opening it from Record mode asks for no second pause.
    @Test func theEditorIsReachedThroughTheSameRelease() {
        var navigator = DialSample.inRecordMode()

        let effects = navigator.receive(.press)     // a file, in Record mode → the editor

        #expect(!effects.contains(.pausePlayback), "the fork already did it")
        #expect(navigator.route == .edit(itemID: "rec-0"))
    }

    /// **Listen never opens either of them**, which is the point of having modes: the mode that can
    /// take the audio session away from you is the one you have to choose.
    @Test func listenModeCannotReachTheEditorAtAll() {
        var navigator = DialSample.inRecordings()

        #expect(navigator.receive(.doublePress).isEmpty)
        #expect(navigator.receive(.action("edit")) == [.feedback(.limit)])
    }

    /// Nothing playing means nothing to silence — an effect asking the host to pause silence would
    /// be a lie about what happened, and `DialPressTests` reads these arrays exactly.
    @Test func nothingPlayingAsksForNoPause() {
        let content = DialSample.content(recordingCount: 0, playback: nil)
        var navigator = DialNavigator(content: content, root: .library)

        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)
        _ = navigator.receive(.action("record"))
        let effects = navigator.receive(.press)

        #expect(!effects.contains(.pausePlayback))
        #expect(effects == [.startRecording, .feedback(.commit)])
    }

    /// The navigator marks its own copy paused in the same breath, rather than waiting for the host
    /// to answer — otherwise Now Playing still draws a pause glyph over audio that has stopped.
    @Test func theNavigatorStopsClaimingToPlayImmediately() {
        var navigator = DialSample.navigator()
        guard case .nowPlaying(let before) = nowPlayingContent(of: navigator) else {
            Issue.record("expected Now Playing")
            return
        }
        #expect(before.isPlaying)

        _ = navigator.receive(.tick(1))         // home → Record
        _ = navigator.receive(.press)           // which silences playback

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
