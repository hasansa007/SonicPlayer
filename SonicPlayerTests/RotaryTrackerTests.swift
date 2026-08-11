import Foundation
import Testing

@testable import SonicPlayer

/// The four things that are each a bug if wrong (#6).
///
/// Angles below are measured the way `atan2(dy, dx)` reports them: 0° is due east, and y grows
/// downward in a view's coordinate space, so positive degrees run clockwise on screen.
@Suite
struct RotaryTrackerTests {

    private let centre = CGPoint(x: 100, y: 100)

    /// **Read from the type under test, never written down here.**
    ///
    /// These angles were literal 12s, so raising the detent size to 20 broke four tests that were
    /// not describing anything wrong — they were describing the old number. The feel is meant to be
    /// tunable by changing one constant; a test that hardcodes it makes that false.
    private var detent: Double { RotaryTracker.detentDegrees }

    /// A point on the ring at `degrees`, far enough out to clear the dead zone.
    private func point(_ degrees: Double, radius: CGFloat = 80) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: centre.x + radius * cos(r), y: centre.y + radius * sin(r))
    }

    // `#expect` captures its expression in a closure, so a `mutating` call written inside one
    // fails to compile against an immutable copy. Every result below is bound to a local first.

    @Test func oneDetentIsOneDetentAngle() {
        var tracker = RotaryTracker()
        let started = tracker.began(at: point(0), centre: centre)
        #expect(started)

        let step = tracker.moved(to: point(detent), centre: centre, at: 1.0)

        #expect(step.detents == 1)
    }

    @Test func belowOneDetentEmitsNothingButIsNotLost() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(0), centre: centre)

        // Three nudges of 0.4 of a detent: the first two bank, the third crosses.
        let first = tracker.moved(to: point(detent * 0.4), centre: centre, at: 1.0)
        let second = tracker.moved(to: point(detent * 0.8), centre: centre, at: 2.0)
        let third = tracker.moved(to: point(detent * 1.2), centre: centre, at: 3.0)

        #expect(first.detents == 0)
        #expect(second.detents == 0)
        #expect(third.detents == 1)
    }

    /// The seam. Reasoning about this produces ∓29 instead of ±1 and the wheel jumps a screen.
    @Test func crossingTheSeamIsOneDetentNotAWholeTurn() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(180 - detent / 2), centre: centre)

        let step = tracker.moved(to: point(-(180 - detent / 2)), centre: centre, at: 1.0)

        #expect(step.detents == 1)
    }

    @Test func crossingTheSeamBackwardsIsMinusOne() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(-(180 - detent / 2)), centre: centre)

        let step = tracker.moved(to: point(180 - detent / 2), centre: centre, at: 1.0)

        #expect(step.detents == -1)
    }

    /// Near the centre the angle is numerically unstable — a one-point wobble is tens of degrees.
    @Test func touchesInsideTheDeadZoneAreRefused() {
        var tracker = RotaryTracker()

        let started = tracker.began(at: point(0, radius: 20), centre: centre)

        #expect(!started)
    }

    @Test func draggingThroughTheDeadZoneEmitsNothing() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(0), centre: centre)

        let step = tracker.moved(to: point(90, radius: 12), centre: centre, at: 1.0)

        #expect(step.detents == 0)
    }

    /// Leaving and re-entering must not bank the angle swept while inside.
    @Test func leavingTheDeadZoneResumesWithoutABankedJump() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(0), centre: centre)
        _ = tracker.moved(to: point(90, radius: 12), centre: centre, at: 1.0)

        let step = tracker.moved(to: point(180), centre: centre, at: 2.0)

        #expect(step.detents == 0)
    }

    @Test func aSlowTurnIsNotAccelerated() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(0), centre: centre)

        let step = tracker.moved(to: point(detent), centre: centre, at: 1.0)

        #expect(step.multiplier == 1)
    }

    @Test func aFastSpinAccelerates() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(0), centre: centre)

        // 20 detents inside one 220ms window.
        var last = RotaryTracker.Step(detents: 0, multiplier: 1)
        for i in 1...20 {
            last = tracker.moved(to: point(Double(i) * detent), centre: centre, at: 1.0 + Double(i) * 0.01)
        }

        #expect(last.multiplier > 1)
    }

    @Test func accelerationDecaysOnceTheWindowPasses() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(0), centre: centre)
        for i in 1...20 {
            _ = tracker.moved(to: point(Double(i) * detent), centre: centre, at: 1.0 + Double(i) * 0.01)
        }

        // One more detent, a full second later.
        let step = tracker.moved(to: point(21 * detent), centre: centre, at: 5.0)

        #expect(step.multiplier == 1)
    }

    @Test func endingClearsTheResidual() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(0), centre: centre)
        _ = tracker.moved(to: point(detent * 0.5), centre: centre, at: 1.0)
        tracker.ended()

        _ = tracker.began(at: point(0), centre: centre)
        let step = tracker.moved(to: point(detent * 0.25), centre: centre, at: 2.0)

        #expect(step.detents == 0)
    }
}
