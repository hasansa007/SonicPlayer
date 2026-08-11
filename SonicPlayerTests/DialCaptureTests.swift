import Foundation
import Testing

@testable import SonicPlayer

/// The three navigator decisions that made recording and trimming inert from the inside (#74, #75).
///
/// Wiring the effects up would not have been enough: two of these could never be *emitted*, so the
/// host would have had nothing to receive.
@Suite
struct DialCaptureTests {

    private let tolerance: TimeInterval = 1e-9

    // MARK: - Gain

    /// `DialSample.capture` sets `isGainSettable` so the axis can be exercised. This is the other
    /// hardware, which is to say almost all of it.
    @Test func turningAgainstHardwareWithNoInputGainIsALimit() {
        let content = DialSample.content(
            recordingCount: 0,
            capture: DialContent.Capture(elapsed: 12, levels: [0.3], gain: 0.5, markers: [])
        )
        var navigator = DialNavigator(content: content, root: .recordings)
        _ = navigator.receive(.action("record"))    // the Record chip

        let effects = navigator.receive(.tick(2))

        #expect(navigator.axis == .gain)
        #expect(effects == [.feedback(.limit)], "No gain to give, so the wheel is a wall.")
    }

    // The settable case is `DialModeTests.turningWhileRecordingSetsGain`, which is where the axis
    // itself is covered — repeating it here would be two places to update when the step changes.

    // MARK: - The trim range the editor never had

    /// **The bug that made the wheel dead on the edit screen.** `push` can only build a range when
    /// `content.editing` is already loaded, and it never is — the host learns which item to load
    /// *from* the route the push creates. Before #74 the level's trim stayed nil for the life of
    /// the screen, so every tick was a limit while the rendered waveform showed handles, because
    /// `DialNavigatorScreen` had a fallback and the state machine did not.
    @Test func theWheelWorksWhenTheMaterialArrivesAfterThePush() {
        var navigator = Self.editorOpenedBeforeTheMaterialLoads()

        let effects = navigator.receive(.tick(1))

        #expect(effects == [.setTrim(start: 0.1, end: 600), .feedback(.detent)])
    }

    @Test func withNoMaterialAtAllTheWheelIsStillALimit() {
        var navigator = Self.editorOpenedBeforeTheMaterialLoads(thenLoad: false)

        let effects = navigator.receive(.tick(1))

        #expect(effects == [.feedback(.limit)])
    }

    /// The old fallback was `DialTrimRange(start: 0, end: 0, duration: 0)`, so a hub press before
    /// the material loaded asked the host to keep **nothing** — and the host rewrites a real file.
    @Test func pressingTheHubBeforeTheMaterialLoadsRefusesRatherThanCommittingAnEmptyRange() {
        var navigator = Self.editorOpenedBeforeTheMaterialLoads(thenLoad: false)

        let effects = navigator.receive(.press)

        #expect(effects == [.feedback(.limit)])
        #expect(navigator.route == .edit(itemID: "rec-0"), "Refusing is not the same as leaving.")
    }

    // MARK: - Snapping

    @Test func aHandleSnapsOntoANearbyMarker() {
        var navigator = Self.inEditor(markers: [1])

        let effects = navigator.receive(.tick(9))

        #expect(effects == [.setTrim(start: 1, end: 600), .feedback(.snap)])
    }

    /// Its own pulse rather than `.detent`, and rather than borrowing `.limit`: a marker and the
    /// end of the file are the two things a thumb has to be able to tell apart.
    @Test func snappingFiresItsOwnPulse() {
        var navigator = Self.inEditor(markers: [1])

        let effects = navigator.receive(.tick(9))

        #expect(effects.last == .feedback(.snap))
        #expect(DetentFeedback.pulse(for: .snap).intensity == DetentFeedback.pulse(for: .limit).intensity)
        #expect(DetentFeedback.pulse(for: .snap).sharpness != DetentFeedback.pulse(for: .limit).sharpness)
    }

    /// The whole reason `MarkerSnap` compares against where the handle *was*. Without it the first
    /// marker a handle touches is the last place it ever goes.
    @Test func aHandleParkedOnAMarkerCanBeTurnedAwayFromIt() {
        var navigator = Self.inEditor(markers: [1])
        _ = navigator.receive(.tick(9))     // snaps onto the marker at 1s

        let effects = navigator.receive(.tick(1))

        #expect(effects == [.setTrim(start: 1.1, end: 600), .feedback(.detent)])
    }

    @Test func aRecordingWithNoMarkersNeverSnaps() {
        var navigator = Self.inEditor()

        let effects = navigator.receive(.tick(9))

        #expect(effects == [.setTrim(start: 0.9, end: 600), .feedback(.detent)])
    }

    /// A marker inside the minimum-length gap is the one place the snap has to lose: crossing the
    /// handles is the invariant `DialTrimRange` exists to hold, and it outranks a convenience.
    /// A marker inside the minimum-length gap is the one place snapping has to lose: not crossing
    /// the handles is the invariant `DialTrimRange` exists to hold, and it outranks a convenience.
    ///
    /// The start handle's ceiling here is `600 − 0.5 = 599.5`, and the marker sits `0.05` beyond it
    /// — inside the snap tolerance, outside what the range will allow. It stays at the ceiling, and
    /// the pulse is an ordinary detent rather than a snap that did not happen.
    @Test func aMarkerTheHandlesCannotReachDoesNotDragThemThroughEachOther() {
        var navigator = Self.inEditor(markers: [599.55])

        let effects = navigator.receive(.tick(9999))

        #expect(effects == [.setTrim(start: 599.5, end: 600), .feedback(.detent)])
    }

    // MARK: -

    private static func editable(markers: [TimeInterval]) -> DialContent.Editable {
        DialContent.Editable(
            id: "rec-0", title: "Recording 1", waveform: [0.1, 0.9, 0.4], duration: 600,
            markers: markers
        )
    }

    private static func content(editing: DialContent.Editable?) -> DialContent {
        DialContent(
            recordings: DialSample.recordings(),
            playback: DialSample.playback,
            capture: nil,
            editing: editing
        )
    }

    /// The library → the first recording's editor, by the stick's up nudge.
    ///
    /// **It has been a double press and then the hub in Record mode.** Both are gone: the hub
    /// plays, and editing asks for its own gesture because it is the one verb that rewrites a file.
    private static func inEditor(markers: [TimeInterval] = []) -> DialNavigator {
        var navigator = DialNavigator(content: content(editing: editable(markers: markers)), root: .recordings)
        _ = navigator.receive(.action("edit"))      // the stick's up nudge, on the first recording
        return navigator
    }

    /// The real ordering: the editor is pushed, and only then does the host discover which item it
    /// has to load and hand the material over.
    private static func editorOpenedBeforeTheMaterialLoads(thenLoad: Bool = true) -> DialNavigator {
        var navigator = DialNavigator(content: content(editing: nil), root: .recordings)
        _ = navigator.receive(.action("edit"))      // → the editor, on the first recording
        if thenLoad {
            navigator.update(content(editing: editable(markers: [])))
        }
        return navigator
    }
}
