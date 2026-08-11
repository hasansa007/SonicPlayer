import SwiftUI

/// Recording (#6).
///
/// The screen where the ring earns the whole idea: it becomes an input level meter, so the control
/// that does nothing during capture on every other player is the one telling you whether the take
/// is usable. That half lives in `DialRing`; this is the readout above it.
struct DialRecordingView: View {

    let recording: DialScreen.Recording

    @ScaledMetric(relativeTo: .largeTitle) private var timerSize = DialFont.timer
    @ScaledMetric(relativeTo: .title2) private var fractionSize = DialFont.fraction

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: 0)

            timer
            waveform

            if !recording.markers.isEmpty {
                markers
            }

            Spacer(minLength: 0)
        }
    }

    private var timer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(recording.elapsed)
                .font(.system(size: timerSize, weight: .light, design: .monospaced))
                .foregroundColor(.sonicTextPrimary)

            if let fraction = recording.fraction {
                Text(verbatim: ".")
                    .font(.system(size: fractionSize, weight: .light, design: .monospaced))
                    .foregroundColor(.sonicTextMuted)
                Text(fraction)
                    .font(.system(size: fractionSize, weight: .light, design: .monospaced))
                    .foregroundColor(.sonicTextMuted)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(Self.timeShrink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Recording time"))
        .accessibilityValue(Text(recording.elapsed))
    }

    /// The live scrolling waveform, newest last.
    ///
    /// Opacity ramps from oldest to newest rather than every bar being the same teal, which is what
    /// makes it read as scrolling in from the right instead of as a static barcode. The bars carry
    /// no interaction and duplicate nothing the timer says, so they are hidden from VoiceOver.
    /// **Drawn, not laid out — which is the whole fix.**
    ///
    /// This was fifty `Capsule`s in an `HStack`, and fifty bars at four points plus four of spacing
    /// is 400pt of *minimum* width against roughly 345 of usable screen. A `frame(maxWidth:
    /// .infinity)` and a `.clipped()` were added against exactly that and did not hold: they bound
    /// what is **painted**, and a stack of fixed-width children has a minimum it will overflow
    /// rather than compress. So at five seconds — the moment the window fills — the card grew past
    /// its own padding and went edge to edge, corners and border running off the screen. Four
    /// seconds looked right and six did not, which is what makes it a layout bug rather than a
    /// styling one.
    ///
    /// A `Canvas` has no intrinsic width. It takes the width it is offered and this decides how
    /// many bars fit in it, so the card cannot be widened by its own contents no matter how long
    /// the take runs. It also stops rebuilding fifty views ten times a second.
    private var waveform: some View {
        Canvas { context, size in
            let step = Sizing.dialWaveBar + Spacing.xs
            // How many bars the given width holds — the newest are kept, so it scrolls in from the
            // right exactly as the stack did.
            let fits = max(1, Int((size.width + Spacing.xs) / step))
            let shown = Array(recording.levels.suffix(fits))
            guard !shown.isEmpty else { return }

            let width = CGFloat(shown.count) * step - Spacing.xs
            let originX = size.width - width

            for (index, level) in shown.enumerated() {
                let height = max(Sizing.dialWaveBar, level.clampedFraction * Sizing.dialWave)
                let bar = CGRect(
                    x: originX + CGFloat(index) * step,
                    y: (size.height - height) / 2,
                    width: Sizing.dialWaveBar,
                    height: height
                )
                context.fill(
                    Path(roundedRect: bar, cornerRadius: Sizing.dialWaveBar / 2),
                    with: .color(.sonicPrimary.opacity(age(of: index, of: shown.count)))
                )
            }
        }
        .frame(height: Sizing.dialWave)
        .accessibilityHidden(true)
    }

    private func age(of index: Int, of count: Int) -> Double {
        guard count > 1 else { return 1 }
        let position = Double(index) / Double(count - 1)
        return Self.oldestBar + position * (1 - Self.oldestBar)
    }

    private var markers: some View {
        ViewThatFits(in: .horizontal) {
            markerChips
            ScrollView(.horizontal) { markerChips }
                .scrollIndicators(.hidden)
        }
    }

    private var markerChips: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(recording.markers) { marker in
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundColor(.sonicPrimary)
                    Text(marker.label)
                    Text(verbatim: "·")
                    Text(marker.time).monospacedDigit()
                }
                .font(.caption)
                .foregroundColor(.sonicTextSecondary)
                .padding(.horizontal, Sizing.chipInsetH)
                .padding(.vertical, Spacing.xs)
                .background(Color.sonicPrimary.opacity(ControlTint.off), in: Capsule())
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, Spacing.xxs)
    }

    private static let timeShrink: CGFloat = 0.6
    /// How faint the oldest bar is. Not zero — a bar that fades to nothing reads as a gap in the
    /// recording rather than as history.
    private static let oldestBar: Double = 0.25
}
