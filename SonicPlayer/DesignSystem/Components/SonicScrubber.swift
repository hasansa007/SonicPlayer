import SwiftUI

/// The progress track, with the seek gesture optional (#47).
///
/// Consumers today: the full player's 8pt scrub track, which seeks; and the mini-player's 2pt
/// progress hairline, which does not. Two, in two files.
///
/// **Where the seek arithmetic went.** The full player used to compute the touch position
/// inline, and that expression carried two defects (#52, #53):
///
/// ```swift
/// let progress = min(max(0, value.location.x / geometry.size.width), 1)
/// ```
///
/// It measured from the physical left while the fill was drawn from the **leading** edge — which
/// is the right-hand side under RTL, so the bar and the gesture were mirrored in Arabic. And it
/// divided by a width `GeometryReader` reports as `0` on its first pass, sending `NaN` into
/// `seek(to:)`, which an `AVPlayer` does not recover from.
///
/// Both now live in `Domain/ScrubGeometry`, which is tested. That is a *different* concern from
/// `Domain/ScrubClamp`, which bounds the editor's 15-second skip steps — this maps a touch to a
/// position; that one bounds a jump. Neither re-derives the other.
struct SonicScrubber: View {

    let progress: Double
    /// Track thickness. `Sizing.trackHeight` for the player, `hairlineTrackHeight` for the bar.
    var height: CGFloat = Sizing.trackHeight
    var cornerRadius: CGFloat = Radius.xs
    /// Whether the untouched remainder is painted. The mini-player's hairline draws only the
    /// filled part, over the material behind it.
    var showsTrack: Bool = true
    var animation: Animation = Motion.scrub
    /// The track's full length in seconds. Only read when `onSeek` is set.
    var duration: TimeInterval = 0
    /// `nil` makes the scrubber display-only — no gesture, no hit testing.
    var onSeek: ((TimeInterval) -> Void)?

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if showsTrack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.sonicBorder)
                        .frame(height: height)
                }

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.sonicPrimary)
                    .frame(width: geometry.size.width * progress, height: height)
                    .animation(animation, value: progress)
            }
            .modifier(SeekGesture(width: geometry.size.width, scrubber: self))
        }
        .frame(height: height)
    }

    fileprivate var isRightToLeft: Bool { layoutDirection == .rightToLeft }
}

/// Attached only when the scrubber is interactive, so the mini-player's hairline stays inert and
/// does not swallow taps meant for the row behind it.
private struct SeekGesture: ViewModifier {
    let width: CGFloat
    let scrubber: SonicScrubber

    func body(content: Content) -> some View {
        if let onSeek = scrubber.onSeek {
            content
                .contentShape(Rectangle())
                // `minimumDistance: 0` makes a tap seek as well as a drag, which is why an
                // out-of-range x is routine rather than exceptional — the finger keeps
                // reporting once it leaves the track.
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        onSeek(
                            ScrubGeometry.time(
                                atX: value.location.x,
                                width: width,
                                duration: scrubber.duration,
                                isRightToLeft: scrubber.isRightToLeft
                            )
                        )
                    }
                )
                .accessibilityElement()
                .accessibilityLabel(Text("Playback position"))
                .accessibilityValue(Text("\(Int(scrubber.progress * 100)) percent"))
        } else {
            content.accessibilityHidden(true)
        }
    }
}

#Preview("Interactive and display-only") {
    VStack(spacing: Spacing.xxl) {
        SonicScrubber(progress: 0.38, duration: 240, onSeek: { _ in })
        SonicScrubber(progress: 0.38, duration: 240, onSeek: { _ in })
            .environment(\.layoutDirection, .rightToLeft)
        SonicScrubber(
            progress: 0.38,
            height: Sizing.hairlineTrackHeight,
            cornerRadius: 0,
            showsTrack: false,
            animation: Motion.miniProgress
        )
    }
    .padding(Spacing.xxl)
}
