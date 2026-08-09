import Foundation
import Testing

@testable import SonicPlayer

/// Modes: the same wheel, doing different things (#6).
///
/// The property worth protecting is that a mode is **data**. Now Playing does not have three
/// variants; it has one screen and a list of three modes, and the chips, the selection and what a
/// tick does are all read from that list. A fourth mode is a fourth element.
@Suite
struct DialModeTests {

    private let tolerance = 1e-9

    // `#expect` captures its expression in a closure, so a `mutating` call written inside one fails
    // to compile against an immutable copy. Every result below is bound to a local first.

    private func nowPlaying() -> DialNavigator {
        var navigator = DialSample.navigator()
        _ = navigator.receive(.hold)
        return navigator
    }

    // MARK: - The chips are the mode list

    @Test func theChipsAreGeneratedFromTheModes() {
        let navigator = nowPlaying()

        #expect(navigator.screen.actions.map(\.id) == navigator.route.modes.map(\.id))
        #expect(navigator.screen.actions.map(\.label) == ["Seek", "Volume", "Browse"])
    }

    @Test func exactlyOneChipIsSelected() {
        var navigator = nowPlaying()
        _ = navigator.receive(.action("volume"))

        let selected = navigator.screen.actions.filter { $0.emphasis == .selected }

        #expect(selected.count == 1)
        #expect(selected.first?.id == "volume")
    }

    @Test func theSelectedModeDecidesWhatATickDoes() {
        var navigator = nowPlaying()
        #expect(navigator.axis == .seek)

        _ = navigator.receive(.action("volume"))

        #expect(navigator.axis == .volume)
    }

    /// The mode belongs to the level, not to the navigator. Leaving Now Playing on `Browse` and
    /// coming back to a *new* Now Playing must not inherit it — a wheel that silently changes track
    /// because of a choice made two screens ago is the worst kind of surprise.
    @Test func aNewLevelStartsOnItsFirstMode() {
        var navigator = nowPlaying()
        _ = navigator.receive(.action("browse"))

        _ = navigator.receive(.action("back"))
        _ = navigator.receive(.hold)

        #expect(navigator.axis == .seek)
    }

    // MARK: - Seek

    @Test func seekingMovesByTheDetentStep() {
        var navigator = nowPlaying()

        let effects = navigator.receive(.tick(3))

        guard case .seek(let target)? = effects.first else {
            Issue.record("expected a seek, got \(effects)")
            return
        }
        #expect(abs(target - (1234 + 0.3)) < tolerance)
        #expect(effects.last == .feedback(.detent))
    }

    @Test func seekingStopsAtTheStartAndSaysSo() {
        var navigator = nowPlaying()
        _ = navigator.receive(.tick(-100_000))     // well past zero

        let effects = navigator.receive(.tick(-1))

        #expect(effects == [.feedback(.limit)])
    }

    @Test func seekingStopsAtTheEndAndSaysSo() {
        var navigator = nowPlaying()
        _ = navigator.receive(.tick(100_000))

        let effects = navigator.receive(.tick(1))

        #expect(effects == [.feedback(.limit)])
    }

    /// The ring doubles as the progress readout while seeking.
    @Test func seekingRedrawsTheRingImmediately() {
        var navigator = nowPlaying()

        _ = navigator.receive(.tick(-100_000))

        #expect(navigator.screen.ring.ticks == .position(0))
    }

    // MARK: - Volume

    @Test func volumeMovesByItsOwnStep() {
        var navigator = nowPlaying()
        _ = navigator.receive(.action("volume"))

        let effects = navigator.receive(.tick(2))

        #expect(effects == [.setVolume(0.64), .feedback(.detent)])
        #expect(navigator.screen.ring.ticks == .position(0.64))
    }

    @Test func volumeStopsAtBothEnds() {
        var navigator = nowPlaying()
        _ = navigator.receive(.action("volume"))
        _ = navigator.receive(.tick(1000))

        let atTheTop = navigator.receive(.tick(1))
        _ = navigator.receive(.tick(-1000))
        let atTheBottom = navigator.receive(.tick(-1))

        #expect(atTheTop == [.feedback(.limit)])
        #expect(atTheBottom == [.feedback(.limit)])
    }

    // MARK: - Browse

    @Test func browsingStepsTheQueue() {
        var navigator = nowPlaying()
        _ = navigator.receive(.action("browse"))

        let effects = navigator.receive(.tick(1))

        #expect(effects == [.selectTrack(index: 3), .feedback(.detent)])
    }

    @Test func browsingStopsAtTheEndsOfTheQueue() {
        var navigator = nowPlaying()
        _ = navigator.receive(.action("browse"))
        _ = navigator.receive(.tick(100))

        let effects = navigator.receive(.tick(1))

        #expect(effects == [.feedback(.limit)])
    }

    /// Browse is the one mode whose ring is a browse ring rather than a filled position.
    @Test func browsingShowsAThumbRatherThanAFill() {
        var navigator = nowPlaying()
        _ = navigator.receive(.action("browse"))

        guard case .browse(let thumb) = navigator.screen.ring.ticks else {
            Issue.record("expected browse ticks, got \(navigator.screen.ring.ticks)")
            return
        }
        #expect(abs((thumb ?? .nan) - 0.25) < tolerance)
    }

    @Test func theHintFollowsTheMode() {
        var navigator = nowPlaying()
        #expect(navigator.screen.hint == "rotate to seek · press to pause · ticks show position")

        _ = navigator.receive(.action("volume"))

        #expect(navigator.screen.hint == "rotate to set volume · press to pause · ticks show volume")
    }

    // MARK: - Gain, which is a mode-less axis

    @Test func turningWhileRecordingSetsGain() {
        var navigator = DialSample.whileRecording()

        let effects = navigator.receive(.tick(2))

        #expect(navigator.axis == .gain)
        #expect(effects == [.setGain(0.54), .feedback(.detent)])
    }

    @Test func gainStopsAtBothEnds() {
        var navigator = DialSample.whileRecording()
        _ = navigator.receive(.tick(1000))

        let effects = navigator.receive(.tick(1))

        #expect(effects == [.feedback(.limit)])
    }

    /// The ring is the level meter while recording, not the gain — the gain is what you are
    /// setting, the level is what you are watching.
    @Test func theRingMetersTheInputRatherThanTheGain() {
        var navigator = DialSample.whileRecording()

        _ = navigator.receive(.tick(2))

        #expect(navigator.screen.ring.ticks == .level(0.42))
    }

    // MARK: - The trim handles

    @Test func theSelectedHandleIsTheOneThatMoves() {
        var navigator = DialSample.whileEditing()

        _ = navigator.receive(.tick(10))

        guard case .edit(let edit) = navigator.screen.content else {
            Issue.record("expected the editor")
            return
        }
        #expect(abs(edit.inFraction - (1.0 / 600)) < tolerance)
        #expect(edit.outFraction == 1)
    }

    @Test func switchingHandlesSwitchesWhatMoves() {
        var navigator = DialSample.whileEditing()
        _ = navigator.receive(.action("trimEnd"))

        _ = navigator.receive(.tick(-10))

        guard case .edit(let edit) = navigator.screen.content else {
            Issue.record("expected the editor")
            return
        }
        #expect(edit.inFraction == 0)
        #expect(abs(edit.outFraction - (599.0 / 600)) < tolerance)
    }

    /// The handles cannot cross, and the wall is felt rather than silently absorbed.
    @Test func aHandleAgainstTheOtherOneIsALimit() {
        var navigator = DialSample.whileEditing()
        _ = navigator.receive(.tick(100_000))      // start handle all the way up to the end

        let effects = navigator.receive(.tick(1))

        #expect(effects == [.feedback(.limit)])
    }

    @Test func theKeepingDurationFollowsTheHandles() {
        var navigator = DialSample.whileEditing()
        _ = navigator.receive(.action("trimEnd"))

        _ = navigator.receive(.tick(-1080))        // 108 seconds off the end

        guard case .edit(let edit) = navigator.screen.content else {
            Issue.record("expected the editor")
            return
        }
        #expect(edit.keeping == "08:12")
        #expect(edit.scale == ["00:00", "00:00", "08:12", "10:00"])
    }
}
