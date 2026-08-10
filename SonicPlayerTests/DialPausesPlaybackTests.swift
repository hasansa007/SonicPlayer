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

    /// **The release moved twice, and the guarantee never did.**
    ///
    /// It was here originally, then went to mode-entry when the fork arrived — entering Record let
    /// go of the player, so the editor could rewrite a file nothing was holding. The fork is gone
    /// and the release comes back to the edit nudge, which is the moment it was always about.
    @Test func openingTheEditorPausesPlaybackAndLetsGoOfIt() {
        let content = DialSample.content(playback: DialSample.playback)
        var navigator = DialNavigator(content: content, root: .recordings)

        let effects = navigator.receive(.action("edit"))

        #expect(effects.contains(.pausePlayback))
        #expect(effects.contains(.releasePlayer))
        #expect(
            effects.firstIndex(of: .pausePlayback) ?? .max < effects.firstIndex(of: .releasePlayer) ?? .min,
            "silence first, then let go of the file"
        )
    }

    /// **Opening the recorder releases too**, so the microphone starts onto a session nothing else
    /// is holding — and the take itself has nothing left to pause.
    @Test func openingTheRecorderReleasesAndTheTakeThenHasNothingToPause() {
        let content = DialSample.content(recordingCount: 0, playback: DialSample.playback)
        var navigator = DialNavigator(content: content, root: .recordings)

        let opening = navigator.receive(.action("record"))
        #expect(opening.contains(.pausePlayback))
        #expect(opening.contains(.releasePlayer))

        let starting = navigator.receive(.press)
        #expect(starting == [.startRecording, .feedback(.commit)])
    }

    /// **The hub plays and the nudge edits**, so the press that used to open the editor cannot.
    @Test func theHubPlaysRatherThanEditing() {
        var navigator = DialSample.inRecordings()

        _ = navigator.receive(.press)

        #expect(navigator.route == .nowPlaying)
    }

    /// A double press has no second meaning left anywhere — it was the editor's way in twice over,
    /// and both are gone.
    @Test func aDoublePressMeansNothing() {
        var navigator = DialSample.inRecordings()

        #expect(navigator.receive(.doublePress).isEmpty)
    }

    /// Nothing playing means nothing to silence — an effect asking the host to pause silence would
    /// be a lie about what happened, and `DialPressTests` reads these arrays exactly.
    @Test func nothingPlayingAsksForNoPause() {
        let content = DialSample.content(recordingCount: 0, playback: nil)
        var navigator = DialNavigator(content: content, root: .recordings)

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

        _ = navigator.receive(.action("edit"))  // which silences playback and lets go

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
