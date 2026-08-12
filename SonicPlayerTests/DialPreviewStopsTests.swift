import Foundation
import Testing

@testable import SonicPlayer

/// Leaving the trim editor stops its preview (#6).
///
/// **The preview used to be stopped only where an edit was WRITTEN** — `commitTrim` and `cutRange`.
/// Every other way out left it playing: over the library, over Now Playing, over the next recording.
/// Reported from device, and invisible to every test here because nothing asserted on the leave
/// path at all.
///
/// These are value-level, which is the point of the fix's shape: `pop()` returns what leaving costs,
/// so the assertion is on an effect rather than on whether some audio object happened to be silent.
@Suite
struct DialPreviewStopsTests {

    private func inTheEditor() -> DialNavigator {
        var navigator = DialNavigator(
            content: DialSample.content(recordingCount: 0, capture: DialSample.capture),
            root: .recordings
        )
        _ = navigator.receive(.action("record"))
        _ = navigator.receive(.press)
        navigator.update(DialSample.content(recordingCount: 0, capture: nil))
        _ = navigator.openEditorForFinishedTake(itemID: "rec-new")
        return navigator
    }

    @Test func backOutOfTheEditorStopsThePreview() {
        var navigator = inTheEditor()
        #expect(navigator.route == .edit(itemID: "rec-new"))

        let effects = navigator.receive(.action("back"))

        #expect(effects.contains(.stopPreview), "leaving the editor has to release the preview")
    }

    /// The complement, and the one that says this is not simply "back always stops a preview".
    @Test func backFromSomewhereElseDoesNotStopIt() {
        var navigator = DialSample.navigator()
        _ = navigator.receive(.action("settings"))

        let effects = navigator.receive(.action("back"))

        #expect(!effects.contains(.stopPreview))
    }

    // A third test tried "cancel a delete from the editor" and was wrong about the app: in the
    // editor the trash nudge CUTS the selection, it opens no guard. The move and delete guards are
    // reached from a list, never from the editor, so `back` is the only way out that does not write.
    //
    // The other exits are covered by construction rather than by a case each: `pop()` is the single
    // place a level is removed, and it is what returns `.stopPreview`.
}
