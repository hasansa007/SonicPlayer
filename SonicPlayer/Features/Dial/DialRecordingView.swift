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
    private var waveform: some View {
        HStack(alignment: .center, spacing: Spacing.xs) {
            ForEach(Array(recording.levels.enumerated()), id: \.offset) { index, level in
                Capsule()
                    .fill(Color.sonicPrimary.opacity(age(of: index)))
                    .frame(
                        width: Sizing.dialWaveBar,
                        height: max(Sizing.dialWaveBar, level.clampedFraction * Sizing.dialWave)
                    )
            }
        }
        // **Bounded and clipped, newest kept.** Fifty bars at four points plus four of spacing is
        // 400pt of intrinsic width against roughly 345 of usable screen — so once the window filled,
        // at five seconds of recording, the stack demanded more room than it had and widened
        // everything around it, the dial included. `maxWidth: .infinity` makes it accept the width
        // it is given instead of asking for its ideal, and trailing alignment keeps the newest bars
        // on screen when there are more than fit.
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: Sizing.dialWave)
        .clipped()
        .accessibilityHidden(true)
    }

    private func age(of index: Int) -> Double {
        guard recording.levels.count > 1 else { return 1 }
        let position = Double(index) / Double(recording.levels.count - 1)
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
