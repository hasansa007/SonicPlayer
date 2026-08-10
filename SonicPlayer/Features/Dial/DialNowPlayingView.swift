import SwiftUI

/// Now playing (#6).
///
/// **The bar under the time is a readout, not a control.** The ring is what seeks here — its ticks
/// fill proportionally, so the dial and the bar say the same thing and the finger only has one
/// place to say it. That is why this draws a plain capsule rather than reaching for
/// `SonicScrubber`, which exists to be dragged.
struct DialNowPlayingView: View {

    let nowPlaying: DialScreen.NowPlaying

    /// A fixed point size is the same size at every accessibility setting unless it is read through
    /// `@ScaledMetric` — the bug #47 fixed on the player, and the reason `DialFont` exists.
    @ScaledMetric(relativeTo: .largeTitle) private var elapsedSize = DialFont.elapsed

    var body: some View {
        VStack(spacing: Spacing.md) {
            Spacer(minLength: 0)

            artwork

            VStack(spacing: Spacing.xs) {
                Text(nowPlaying.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.sonicTextPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let subtitle = nowPlaying.subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundColor(.sonicTextSecondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)

            Text(nowPlaying.elapsed)
                .font(.system(size: elapsedSize, weight: .light, design: .monospaced))
                .foregroundColor(.sonicPrimary)
                .lineLimit(1)
                .minimumScaleFactor(Self.timeShrink)
                .accessibilityHidden(true)

            progress

            volumeReadout

            Spacer(minLength: 0)
        }
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: Radius.stage)
            .fill(LinearGradient.sonicGradient)
            .frame(width: Sizing.artworkCollapsed, height: Sizing.artworkCollapsed)
            .overlay(
                Image(systemName: "waveform")
                    .font(.largeTitle)
                    .foregroundColor(.white)
            )
            .sonicShadow(Elevation.artwork)
            .accessibilityHidden(true)
    }

    private var progress: some View {
        VStack(spacing: Spacing.sm) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.sonicTextSecondary.opacity(ControlTint.on))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.sonicPrimaryDark, Color.sonicPrimaryLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * nowPlaying.progress.clampedFraction)
                }
            }
            .frame(height: Sizing.dialTrack)

            HStack {
                Text(nowPlaying.elapsed)
                Spacer()
                Text(nowPlaying.remaining)
            }
            .font(.sonicTimeLabel)
            .monospacedDigit()
            .foregroundColor(.sonicTextSecondary)
        }
        // One element, so VoiceOver hears "20:34, −25:11" rather than landing on a bar it cannot
        // drag. Seeking is the dial's adjustable action.
        .accessibilityElement(children: .combine)
    }

    /// The level the stick's vertical nudges change.
    ///
    /// Drawn always rather than as a flash on change: a transient needs timing to be right, and the
    /// question this answers — "did that do anything?" — is asked *after* the gesture, when a
    /// transient has gone. The percentage is there because a bar alone cannot distinguish a small
    /// step from none.
    private var volumeReadout: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: nowPlaying.volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.caption2)
                .foregroundColor(.sonicTextSecondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.sonicTextSecondary.opacity(ControlTint.on))

                    Capsule()
                        .fill(Color.sonicPrimary)
                        .frame(width: geometry.size.width * nowPlaying.volume.clampedFraction)
                }
            }
            .frame(height: Sizing.hairlineTrackHeight * 2)

            Text("\(Int((nowPlaying.volume * 100).rounded()))%")
                .font(.sonicTimeLabel)
                .monospacedDigit()
                .foregroundColor(.sonicTextSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Volume"))
        .accessibilityValue(Text("\(Int((nowPlaying.volume * 100).rounded())) percent"))
    }

    private static let timeShrink: CGFloat = 0.6
}
