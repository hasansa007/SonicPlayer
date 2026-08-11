import Foundation
import Testing

@testable import SonicPlayer

/// What stopping a take opens (#6).
///
/// **Nothing, for a while, and that was the whole of the gap.** The dial drives the recorder
/// directly and never presents `RecordingView` — which is the only thing that renders the naming
/// sheet and the inline editor it raises. So a take was written, and every route to naming or
/// trimming it went through a screen that was never on screen. Every recording kept its generated
/// filename, and the trim step existed only by finding the file again in the library.
///
/// The editor is the answer rather than a new screen: rename is already a nudge there and the trim
/// is the whole of it.
@Suite
struct DialTakeEditorTests {

    private func whileRecording() -> DialNavigator {
        var navigator = DialNavigator(
            content: DialSample.content(recordingCount: 0, capture: DialSample.capture),
            root: .recordings
        )
        _ = navigator.receive(.action("record"))    // → the recorder
        return navigator
    }

    /// The take ends, the host learns the URL, and the editor opens on it.
    @Test func aFinishedTakeOpensTheEditor() {
        var navigator = whileRecording()
        _ = navigator.receive(.press)               // stop; the capture goes with it
        navigator.update(DialSample.content(recordingCount: 0, capture: nil))

        _ = navigator.openEditorForFinishedTake(itemID: "rec-new")

        #expect(navigator.route == .edit(itemID: "rec-new"))
    }

    /// **Pushed, not swapped.** Back from the editor is the recorder again, which is where you were
    /// and where the next take starts — landing on the library instead is the jump this whole
    /// sequence was changed to stop making.
    @Test func backFromItReturnsToTheRecorder() {
        var navigator = whileRecording()
        _ = navigator.receive(.press)
        navigator.update(DialSample.content(recordingCount: 0, capture: nil))
        _ = navigator.openEditorForFinishedTake(itemID: "rec-new")

        _ = navigator.receive(.action("back"))

        #expect(navigator.route == .recording)
    }

    /// **A take can finish after you have walked away**, and a screen arriving under a thumb that
    /// went somewhere else is worse than a take you have to open yourself.
    @Test func itDoesNothingIfYouHaveAlreadyLeftTheRecorder() {
        var navigator = whileRecording()
        _ = navigator.receive(.press)
        _ = navigator.receive(.action("back"))      // back to the library

        let effects = navigator.openEditorForFinishedTake(itemID: "rec-new")

        #expect(effects.isEmpty)
        #expect(navigator.route == .recordings)
    }

    /// And it does nothing while a take is still running — the file does not exist yet, so there is
    /// nothing for the editor to be about.
    @Test func itDoesNothingWhileATakeIsStillRunning() {
        var navigator = whileRecording()

        let effects = navigator.openEditorForFinishedTake(itemID: "rec-new")

        #expect(effects.isEmpty)
        #expect(navigator.route == .recording)
    }

    /// Naming is why this matters: the editor is where a take stops being `Recording 2026-08-10`.
    @Test func theEditorIsWhereANewTakeGetsItsName() {
        var navigator = whileRecording()
        _ = navigator.receive(.press)
        navigator.update(DialSample.content(recordingCount: 0, capture: nil))
        _ = navigator.openEditorForFinishedTake(itemID: "rec-new")

        #expect(
            navigator.receive(.action("rename")) == [.renameItem(itemID: "rec-new"), .feedback(.commit)]
        )
    }
}
