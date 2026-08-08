import CoreGraphics
import Foundation

/// Where a touch on the progress track lands in a track (#47).
///
/// Lifted out of `PlayerView`'s `DragGesture`, which computed
/// `min(max(0, value.location.x / geometry.size.width), 1)` inline. That expression is wrong twice:
/// it divides by a width `GeometryReader` reports as zero on its first pass, and it measures from
/// the left in a view whose fill is drawn from the **leading** edge — which is the right-hand side
/// under RTL, so the bar and the gesture disagreed in Arabic.
///
/// It lives in `Domain/` for the reason the rest of `Domain/` does: it is a decision statable
/// without a view. `CoreGraphics` is imported for `CGFloat` only — the caller measures in points
/// and converting at the boundary would just move the arithmetic back into the view.
enum ScrubGeometry {

    /// A touch at `x` in a track `width` points wide, as a fraction of the whole.
    ///
    /// Always in `0...1`. A non-positive width means the track has not been laid out yet, and the
    /// answer is the start rather than `NaN` — `progress * duration` feeds `seek(to:)` directly,
    /// and an `AVPlayer` seeked to `NaN` does not recover.
    ///
    /// **The `isRightToLeft` flip is correct, and was measured rather than argued (#63).** On a
    /// physical iPhone in Arabic, touching the far LEFT end of the scrubber reported `x=3` of
    /// `w=234` — so a `DragGesture`'s `location.x` is **not** mirrored: zero is the physical left
    /// edge in both directions. The fill, being layout, *is* mirrored and grows from the right, so
    /// the left end is the END of the track — which is exactly what `1 - fraction` returns, and the
    /// seek landed at `45:13` of `45:45` with the bar full.
    ///
    /// Do not remove the flip on the reasoning that SwiftUI already mirrors coordinates. It mirrors
    /// `.offset(x:)` — measured in #54, which is why `ScrollingText` must stay direction-agnostic —
    /// and it does **not** mirror gesture locations. The two look alike and behave oppositely, which
    /// is why #54 and #63 were both filed on plausible reasoning and both turned out to be wrong.
    static func progress(atX x: CGFloat, width: CGFloat, isRightToLeft: Bool) -> Double {
        guard width > 0 else { return 0 }

        let fraction = min(max(0, Double(x / width)), 1)
        return isRightToLeft ? 1 - fraction : fraction
    }

    /// The same touch as a playback position.
    ///
    /// A duration of zero is the temporal twin of a zero width: the asset's duration is not known
    /// until it loads, and multiplying by it before then produced a seek to nowhere.
    static func time(
        atX x: CGFloat,
        width: CGFloat,
        duration: TimeInterval,
        isRightToLeft: Bool
    ) -> TimeInterval {
        guard duration > 0 else { return 0 }

        return progress(atX: x, width: width, isRightToLeft: isRightToLeft) * duration
    }
}
