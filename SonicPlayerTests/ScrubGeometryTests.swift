import Foundation
import Testing

@testable import SonicPlayer

/// Turning a touch on the progress track into a playback position (#47).
///
/// This is the arithmetic `PlayerView` used to inline in its `DragGesture`:
///
/// ```swift
/// let progress = min(max(0, value.location.x / geometry.size.width), 1)
/// ```
///
/// It has two defects, and both are the kind epic #6 exists to close — the screen *looks* right
/// and does not *act* right, so neither is visible in a screenshot.
@Suite
struct ScrubGeometryTests {

    // MARK: - Layout direction

    @Test func test_leftToRight_measuresFromTheLeftEdge() {
        #expect(ScrubGeometry.progress(atX: 0, width: 200, isRightToLeft: false) == 0)
        #expect(ScrubGeometry.progress(atX: 100, width: 200, isRightToLeft: false) == 0.5)
        #expect(ScrubGeometry.progress(atX: 200, width: 200, isRightToLeft: false) == 1)
    }

    /// The defect. The fill is drawn in a `ZStack(alignment: .leading)`, and `leading` flips under
    /// RTL — so in Arabic the bar fills from the right while the untouched arithmetic still reads
    /// x=0 as the start. Tapping the visually-full end used to seek to zero.
    @Test func test_rightToLeft_measuresFromTheRightEdge() {
        #expect(ScrubGeometry.progress(atX: 0, width: 200, isRightToLeft: true) == 1)
        #expect(ScrubGeometry.progress(atX: 100, width: 200, isRightToLeft: true) == 0.5)
        #expect(ScrubGeometry.progress(atX: 200, width: 200, isRightToLeft: true) == 0)
    }

    // MARK: - Bounds

    /// A `DragGesture` with `minimumDistance: 0` keeps reporting once the finger leaves the track,
    /// so out-of-range x is the normal case, not the exceptional one.
    @Test func test_aDragPastEitherEdge_clampsRatherThanOvershooting() {
        #expect(ScrubGeometry.progress(atX: -80, width: 200, isRightToLeft: false) == 0)
        #expect(ScrubGeometry.progress(atX: 999, width: 200, isRightToLeft: false) == 1)
        #expect(ScrubGeometry.progress(atX: -80, width: 200, isRightToLeft: true) == 1)
        #expect(ScrubGeometry.progress(atX: 999, width: 200, isRightToLeft: true) == 0)
    }

    /// The second defect. `GeometryReader` reports zero width on its first layout pass, and the
    /// inline version divided by it — sending `NaN` into `seek(to:)` by way of
    /// `progress * duration`. A player asked to seek to NaN does not come back.
    @Test func test_aZeroWidthTrack_reportsTheStartRatherThanNaN() {
        let progress = ScrubGeometry.progress(atX: 42, width: 0, isRightToLeft: false)

        #expect(!progress.isNaN, "A zero-width track must not divide by zero (#47).")
        #expect(progress == 0)
    }

    @Test func test_aNegativeWidth_isTreatedAsNoTrackAtAll() {
        #expect(ScrubGeometry.progress(atX: 42, width: -10, isRightToLeft: false) == 0)
    }

    // MARK: - Seeking

    /// The other half of what the view inlined: progress became a time by multiplying by duration.
    /// Folded in here so the view is left holding no arithmetic at all.
    @Test func test_time_scalesProgressByDuration() {
        #expect(ScrubGeometry.time(atX: 50, width: 200, duration: 120, isRightToLeft: false) == 30)
        #expect(ScrubGeometry.time(atX: 50, width: 200, duration: 120, isRightToLeft: true) == 90)
    }

    /// A track whose duration has not loaded yet is the same shape of bug as the zero-width one.
    @Test func test_time_isZeroWhenTheDurationIsNotKnownYet() {
        #expect(ScrubGeometry.time(atX: 50, width: 200, duration: 0, isRightToLeft: false) == 0)
    }
}
