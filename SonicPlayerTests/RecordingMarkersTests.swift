import Foundation
import Testing

@testable import SonicPlayer

/// Marking a lecture without looking at the screen (#75), and the cost of a target that large.
///
/// `#expect` captures its expression in a closure, so a `mutating` call written inside one fails to
/// compile against an immutable copy — every result below is bound to a local first, as in
/// `DialTrimRangeTests`.
@Suite
struct RecordingMarkersTests {

    @Test func aMarkerLandsAtTheTimeItWasDropped() {
        var markers = RecordingMarkers()

        let added = markers.add(at: 62)

        #expect(added)
        #expect(markers.times == [62])
    }

    /// The whole reason the type refuses anything: #75 makes the entire screen the tap target, so a
    /// fumble produces two events where the user meant one.
    @Test func aSecondTapInTheSamePlaceIsRefused() {
        var markers = RecordingMarkers()
        markers.add(at: 62)

        let added = markers.add(at: 62.2)

        #expect(!added)
        #expect(markers.times == [62])
    }

    @Test func aTapFarEnoughAwayIsAccepted() {
        var markers = RecordingMarkers()
        markers.add(at: 62)

        let added = markers.add(at: 62 + RecordingMarkers.minimumSeparation)

        #expect(added)
        #expect(markers.count == 2)
    }

    /// A capture only ever appends, but a set handed in from outside can arrive in any order and
    /// `MarkerSnap` reads the array directly.
    @Test func theTimesAreKeptSorted() {
        var markers = RecordingMarkers()
        markers.add(at: 90)
        markers.add(at: 30)
        markers.add(at: 60)

        #expect(markers.times == [30, 60, 90])
    }

    @Test func anUnsortedSetIsSortedAndThinnedOnTheWayIn() {
        let markers = RecordingMarkers(times: [90, 30, 30.1, 60])

        #expect(markers.times == [30, 60, 90])
    }

    /// Marking the very start of a capture is a real thing to want, and a clock that has not
    /// started is the only way a negative arrives.
    @Test func aNegativeTimeIsClampedRatherThanRefused() {
        var markers = RecordingMarkers()

        let added = markers.add(at: -3)

        #expect(added)
        #expect(markers.times == [0])
    }

    @Test func anEmptySetSaysSo() {
        let markers = RecordingMarkers()

        #expect(markers.isEmpty)
        #expect(markers.count == 0)
    }

    /// Pausing stops the clock, so every tap while paused reports the same elapsed time. Only the
    /// first can be a marker.
    @Test func repeatedTapsAtAFrozenClockProduceOneMarker() {
        var markers = RecordingMarkers()

        markers.add(at: 120)
        markers.add(at: 120)
        markers.add(at: 120)

        #expect(markers.times == [120])
    }
}
