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

    /// **Now Playing has no modes at all any more**, and that is the point of the redesign.
    ///
    /// Volume moved to a vertical spring-return segment and track-stepping to a horizontal one, so
    /// the wheel does exactly one thing — seek. "What does the wheel do right now" stopped being a
    /// question rather than becoming a faster one to answer.
    @Test func nowPlayingHasNoModeChips() {
        let navigator = nowPlaying()

        #expect(navigator.route.modes.isEmpty)
        #expect(navigator.screen.actions.map(\.id) == ["back"])
        #expect(navigator.axis == .seek)
    }

    /// Modes survive where a screen genuinely has two things one wheel must do. The trim editor is
    /// the last of them: one wheel, two handles, and no room for a second control.
    @Test func theChipsAreGeneratedFromTheModes() {
        let navigator = DialSample.whileEditing()

        #expect(navigator.screen.actions.map(\.id).prefix(2) == navigator.route.modes.map(\.id).prefix(2))
        #expect(navigator.screen.actions.map(\.label).prefix(2) == ["Start handle", "End handle"])
    }

    @Test func exactlyOneChipIsSelected() {
        var navigator = DialSample.whileEditing()
        _ = navigator.receive(.action("trimEnd"))

        let selected = navigator.screen.actions.filter { $0.emphasis == .selected }

        #expect(selected.count == 1)
        #expect(selected.first?.id == "trimEnd")
    }

    @Test func theSelectedModeDecidesWhatATickDoes() {
        var navigator = DialSample.whileEditing()
        #expect(navigator.axis == .trimStart)

        _ = navigator.receive(.action("trimEnd"))

        #expect(navigator.axis == .trimEnd)
    }

    /// The mode belongs to the level, not to the navigator. Leaving Now Playing on `Browse` and
    /// coming back to a *new* Now Playing must not inherit it — a wheel that silently changes track
    /// because of a choice made two screens ago is the worst kind of surprise.
    @Test func aNewLevelStartsOnItsFirstMode() {
        var navigator = DialSample.whileEditing()
        _ = navigator.receive(.action("trimEnd"))

        _ = navigator.receive(.action("back"))

        #expect(navigator.axis != .trimEnd)
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

    /// Volume arrives on its own command now, from its own control. The big wheel never touches it.
    @Test func volumeMovesByItsOwnStep() {
        var navigator = nowPlaying()

        let effects = navigator.receive(.volumeTick(2))

        #expect(effects == [.setVolume(0.64), .feedback(.detent)])
        // The ring keeps showing *position* — volume moved to its own segment, and the whole point
        // is that turning the wheel no longer changes what the wheel means.
        #expect(navigator.screen.ring.volume == 0.64)
        guard case .position = navigator.screen.ring.ticks else {
            Issue.record("the ring must still show position, got \(navigator.screen.ring.ticks)")
            return
        }
    }

    @Test func volumeStopsAtBothEnds() {
        var navigator = nowPlaying()
        _ = navigator.receive(.volumeTick(1000))

        let atTheTop = navigator.receive(.volumeTick(1))
        _ = navigator.receive(.volumeTick(-1000))
        let atTheBottom = navigator.receive(.volumeTick(-1))

        #expect(atTheTop == [.feedback(.limit)])
        #expect(atTheBottom == [.feedback(.limit)])
    }

    // MARK: - Browse

    /// The track segment's two ends. It reuses `.action` because previous and next were already
    /// sayable — a spring-return switch is a new affordance for them, not a new thing to say.
    @Test func browsingStepsTheQueue() {
        var navigator = nowPlaying()

        let effects = navigator.receive(.action("next"))

        #expect(effects == [.selectTrack(index: 3), .feedback(.detent)])
    }

    @Test func browsingStopsAtTheEndsOfTheQueue() {
        var navigator = nowPlaying()
        for _ in 0..<100 { _ = navigator.receive(.action("next")) }

        let effects = navigator.receive(.action("next"))

        #expect(effects == [.feedback(.limit)])
    }

    /// The ring shows position and nothing else here, because seeking is all the wheel does.
    @Test func theRingAlwaysShowsPositionOnNowPlaying() {
        var navigator = nowPlaying()

        guard case .position = navigator.screen.ring.ticks else {
            Issue.record("expected position ticks, got \(navigator.screen.ring.ticks)")
            return
        }

        _ = navigator.receive(.volumeTick(2))
        _ = navigator.receive(.action("next"))

        guard case .position = navigator.screen.ring.ticks else {
            Issue.record("the auxiliary controls must not change what the ring shows")
            return
        }
    }

    /// One sentence, not one per mode — there is only one thing the wheel does.
    @Test func theHintDoesNotChange() {
        var navigator = nowPlaying()
        let before = navigator.screen.hint

        _ = navigator.receive(.volumeTick(2))

        #expect(navigator.screen.hint == before)
        #expect(before == "rotate to seek · press to pause · slide to change track")
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
