import CoreGraphics
import Foundation

/// Touch points on a ring, turned into discrete detents (#6).
///
/// **This type is the feel of the wheel, and it is the only place the feel lives.** Tuning it is
/// changing a constant here and the test beside it — never a number in a view. `CoreGraphics` is
/// imported for `CGPoint` only, the same concession `ScrubGeometry` makes.
///
/// Time arrives as a parameter rather than being read, which is what keeps acceleration pure: a
/// test drives twenty detents through a 200ms window without waiting 200ms.
///
/// **No RTL handling, deliberately.** `ScrubGeometry` records a measurement taken on a physical
/// iPhone in Arabic: a `DragGesture`'s `location.x` is *not* mirrored. So the points arriving here
/// are physical, `atan2` yields a physical angle, and clockwise means clockwise in every language.
/// Adding a flip would be the third instance of the bug #54 and #63 were both filed on.
struct RotaryTracker {

    /// 12 detents per revolution.
    ///
    /// Third value: 12° (30 per revolution) was too fine on a phone, 20° went untested for a day,
    /// and this is the deliberate step past it. Everything derived from it follows — the ring draws
    /// one tick per detent, and `RotaryTrackerTests` reads this constant rather than repeating the
    /// number, so retuning again is this line alone.
    ///
    /// Tuned against the browser prototype committed beside the design spec, and **not yet
    /// re-tuned on a device** — a mouse is not a thumb, and there is no haptic in a browser, which
    /// is most of what a detent feels like.
    static let detentDegrees: Double = 30

    /// How many detents a full turn holds. Derived rather than stated, because `DialRing` draws one
    /// tick per detent and the two must not be able to disagree — 36 ticks over 30 detents looked
    /// right and meant every other click landed between marks.
    static var detentsPerRevolution: Int { Int(360 / detentDegrees) }

    /// Below this, `atan2` is numerically unstable: a one-point wobble near the centre is tens of
    /// degrees, and the wheel sprays detents while the thumb is effectively still.
    static let deadZoneRadius: CGFloat = 34

    /// How long a detent keeps counting toward the spin rate.
    static let accelerationWindow: TimeInterval = 0.22

    /// Detents per window → multiplier, richest first. Read the last row as: fewer than 5 detents
    /// in a window is not a spin, and is not accelerated.
    static let accelerationSteps: [(detents: Int, multiplier: Int)] = [
        (18, 40), (12, 15), (7, 5), (5, 2)
    ]

    /// Slack on the detent threshold, and it is load-bearing rather than defensive.
    ///
    /// The angle is recovered with `atan2` from coordinates that have already been through a
    /// translation, so a sweep of exactly one detent arrives as `11.999999999999998`. Compared
    /// with a bare `>=` that is *not* a detent, and the wheel silently swallows the click — which
    /// is what the first version of this type did, and what `oneDetentIsTwelveDegrees` caught.
    private static let epsilon: Double = 1e-9

    struct Step: Equatable {
        /// Signed, and **not** already multiplied — the caller applies `multiplier` to its own
        /// unit, so a list moves by rows and a scrub moves by seconds from the same number.
        var detents: Int
        var multiplier: Int
    }

    private var lastAngle: Double?
    private var residual: Double = 0
    private var recentDetents: [TimeInterval] = []

    init() {}

    /// Starts a turn. Returns `false` when the touch begins inside the dead zone, which the caller
    /// should read as "this drag is not a turn".
    mutating func began(at point: CGPoint, centre: CGPoint) -> Bool {
        residual = 0
        recentDetents = []
        guard Self.radius(point, centre) >= Self.deadZoneRadius else {
            lastAngle = nil
            return false
        }
        lastAngle = Self.angle(point, centre)
        return true
    }

    mutating func moved(to point: CGPoint, centre: CGPoint, at timestamp: TimeInterval) -> Step {
        guard Self.radius(point, centre) >= Self.deadZoneRadius else {
            // Drop the anchor rather than banking the sweep. Re-entering the ring somewhere else
            // must not pay out the angle crossed while inside the dead zone.
            lastAngle = nil
            return Step(detents: 0, multiplier: multiplier(at: timestamp))
        }

        let angle = Self.angle(point, centre)
        defer { lastAngle = angle }

        guard let previous = lastAngle else {
            return Step(detents: 0, multiplier: multiplier(at: timestamp))
        }

        residual += Self.shortestArc(from: previous, to: angle)

        var detents = 0
        while abs(residual) + Self.epsilon >= Self.detentDegrees {
            let direction = residual > 0 ? 1 : -1
            detents += direction
            residual -= Double(direction) * Self.detentDegrees
            recentDetents.append(timestamp)
        }

        return Step(detents: detents, multiplier: multiplier(at: timestamp))
    }

    mutating func ended() {
        lastAngle = nil
        residual = 0
        recentDetents = []
    }

    private mutating func multiplier(at timestamp: TimeInterval) -> Int {
        recentDetents.removeAll { timestamp - $0 > Self.accelerationWindow }
        let rate = recentDetents.count
        for step in Self.accelerationSteps where rate >= step.detents {
            return step.multiplier
        }
        return 1
    }

    // MARK: - Geometry

    private static func radius(_ point: CGPoint, _ centre: CGPoint) -> CGFloat {
        hypot(point.x - centre.x, point.y - centre.y)
    }

    /// Degrees, 0° due east, growing clockwise on screen — a view's y grows downward.
    private static func angle(_ point: CGPoint, _ centre: CGPoint) -> Double {
        atan2(Double(point.y - centre.y), Double(point.x - centre.x)) * 180 / .pi
    }

    /// The short way round. Without this, 174° → −174° reads as −348°, and the wheel jumps 29
    /// detents backwards at the seam instead of one forwards.
    static func shortestArc(from: Double, to: Double) -> Double {
        var delta = to - from
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return delta
    }
}
