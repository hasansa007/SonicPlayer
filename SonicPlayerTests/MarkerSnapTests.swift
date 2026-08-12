import Foundation
import Testing

@testable import SonicPlayer

/// The rule that keeps a trim handle from sticking to the first marker it touches (#74).
@Suite
struct MarkerSnapTests {

    private let detent = WheelMetrics.secondsPerDetent
    private let markers: [TimeInterval] = [30, 60, 90]

    @Test func arrivingInsideAMarkersZoneSnapsToIt() {
        let target = MarkerSnap.target(for: 60.05, from: 60.15, markers: markers, tolerance: detent)

        #expect(target == 60)
    }

    /// The failure this type exists to prevent: parked on a marker, one detent out, and dragged
    /// straight back. Without it the wheel is unusable at exactly the point it is meant to be best.
    @Test func aHandleAlreadyOnAMarkerCanLeaveIt() {
        let target = MarkerSnap.target(for: 60.1, from: 60, markers: markers, tolerance: detent)

        #expect(target == nil)
    }

    @Test func aHandleFarFromEveryMarkerIsLeftAlone() {
        let target = MarkerSnap.target(for: 45, from: 44.9, markers: markers, tolerance: detent)

        #expect(target == nil)
    }

    /// Acceleration reaches ×40, so one tick can cover four seconds. A marker in the middle of that
    /// travel is scenery, not a hand brake.
    @Test func aFastSpinVaultsCleanOverAMarker() {
        let target = MarkerSnap.target(for: 74, from: 30, markers: markers, tolerance: detent)

        #expect(target == nil)
    }

    @Test func theNearestMarkerWins() {
        let target = MarkerSnap.target(
            for: 60.4, from: 62, markers: [60, 60.5, 61], tolerance: 1
        )

        #expect(target == 60.5)
    }

    /// Deterministic rather than whichever the filter happened to reach first.
    @Test func aTieBreaksTowardTheEarlierMarker() {
        let target = MarkerSnap.target(for: 60, from: 65, markers: [59, 61], tolerance: 2)

        #expect(target == 59)
    }

    /// The finger's tolerance is wider than the wheel's — same markers, different answer, which is
    /// why this is a parameter rather than a constant.
    @Test func aWiderToleranceCatchesAMarkerTheWheelWouldMiss() {
        let wheel = MarkerSnap.target(for: 60.4, from: 61.5, markers: markers, tolerance: detent)
        let finger = MarkerSnap.target(for: 60.4, from: 61.5, markers: markers, tolerance: 0.5)

        #expect(wheel == nil)
        #expect(finger == 60)
    }

    @Test func snappingIsOffWhenThereIsNoTolerance() {
        let target = MarkerSnap.target(for: 60, from: 65, markers: markers, tolerance: 0)

        #expect(target == nil)
    }

    @Test func aRecordingWithNoMarkersNeverSnaps() {
        let target = MarkerSnap.target(for: 60, from: 60.1, markers: [], tolerance: detent)

        #expect(target == nil)
    }
}
