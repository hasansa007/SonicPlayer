import Foundation
import Testing

@testable import SonicPlayer

/// Press, double-press and hold, resolved without waiting for any of them (#6).
///
/// Every timestamp below is a parameter, so a 0.5-second hold is tested in microseconds. That is
/// the same trick `RotaryTracker` uses for acceleration and it is the reason this is testable at
/// all — a detector that read a clock could only be tested by sleeping.
@Suite
struct DialPressDetectorTests {

    private let window = DialCommand.doublePressWindow
    private let hold = DialCommand.holdDuration

    // `#expect` captures its expression in a closure, so a `mutating` call written inside one fails
    // to compile against an immutable copy. Every result below is bound to a local first.

    @Test func aSinglePressResolvesOnceTheWindowPasses() {
        var detector = DialPressDetector()
        detector.down(at: 0)
        let onRelease = detector.up(at: 0.05)

        let settled = detector.settle(at: 0.05 + window + 0.01)

        #expect(onRelease == nil)
        #expect(settled == .press)
    }

    /// The cost of double-press: a single press cannot be emitted until a second one is ruled out.
    @Test func aSinglePressIsNotEmittedEarly() {
        var detector = DialPressDetector()
        detector.down(at: 0)
        _ = detector.up(at: 0.05)

        let tooSoon = detector.settle(at: 0.05 + window - 0.01)

        #expect(tooSoon == nil)
    }

    @Test func twoPressesInsideTheWindowAreOneDoublePress() {
        var detector = DialPressDetector()
        detector.down(at: 0)
        _ = detector.up(at: 0.05)
        detector.down(at: 0.05 + window - 0.01)

        let second = detector.up(at: 0.05 + window)

        #expect(second == .doublePress)
    }

    /// And the single press it was going to be must not arrive afterwards as well.
    @Test func aDoublePressDoesNotAlsoEmitASinglePress() {
        var detector = DialPressDetector()
        detector.down(at: 0)
        _ = detector.up(at: 0.05)
        detector.down(at: 0.1)
        _ = detector.up(at: 0.15)

        let settled = detector.settle(at: 10)

        #expect(settled == nil)
    }

    @Test func twoPressesOutsideTheWindowAreTwoPresses() {
        var detector = DialPressDetector()
        detector.down(at: 0)
        _ = detector.up(at: 0.05)
        let first = detector.settle(at: 1)

        detector.down(at: 2)
        _ = detector.up(at: 2.05)
        let second = detector.settle(at: 3)

        #expect(first == .press)
        #expect(second == .press)
    }

    // MARK: - Hold

    @Test func holdingEmitsOnceTheThresholdPasses() {
        var detector = DialPressDetector()
        detector.down(at: 0)

        let beforehand = detector.elapsed(at: hold - 0.01)
        let after = detector.elapsed(at: hold)

        #expect(beforehand == nil)
        #expect(after == .hold)
    }

    @Test func holdingLongerDoesNotEmitTwice() {
        var detector = DialPressDetector()
        detector.down(at: 0)
        _ = detector.elapsed(at: hold)

        let again = detector.elapsed(at: hold + 1)

        #expect(again == nil)
    }

    /// The contract makes `holdDuration` longer than `doublePressWindow` precisely so a slow press
    /// cannot resolve as both. This is that promise, kept.
    @Test func aHoldIsNotAlsoAPress() {
        var detector = DialPressDetector()
        detector.down(at: 0)
        _ = detector.elapsed(at: hold)

        let onRelease = detector.up(at: hold + 0.2)
        let settled = detector.settle(at: 10)

        #expect(onRelease == nil)
        #expect(settled == nil)
    }

    /// A press released just before the threshold is an ordinary press, not a swallowed hold.
    @Test func releasingJustBeforeTheThresholdIsStillAPress() {
        var detector = DialPressDetector()
        detector.down(at: 0)
        _ = detector.elapsed(at: hold - 0.01)
        _ = detector.up(at: hold - 0.005)

        let settled = detector.settle(at: 10)

        #expect(settled == .press)
    }

    /// A hold must not leave the detector primed, or the next press resolves as a double.
    @Test func aHoldDoesNotPrimeTheNextPress() {
        var detector = DialPressDetector()
        detector.down(at: 0)
        _ = detector.elapsed(at: hold)
        _ = detector.up(at: hold + 0.1)

        detector.down(at: hold + 0.15)
        let next = detector.up(at: hold + 0.2)

        #expect(next == nil)
    }

    // MARK: - Deadlines

    /// The caller has to schedule the two waits, and asking the detector when beats each caller
    /// re-deriving it from the two constants.
    @Test func theDetectorSaysWhenItNeedsToBeAskedAgain() {
        var detector = DialPressDetector()
        detector.down(at: 4)

        #expect(detector.holdDeadline == 4 + hold)
        #expect(detector.settleDeadline == nil)

        _ = detector.up(at: 4.1)

        #expect(detector.holdDeadline == nil)
        #expect(detector.settleDeadline == 4.1 + window)
    }

    @Test func anIdleDetectorNeedsNothing() {
        let detector = DialPressDetector()

        #expect(detector.holdDeadline == nil)
        #expect(detector.settleDeadline == nil)
    }
}
