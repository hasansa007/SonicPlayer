import SwiftUI

/// A dim, transient volume readout that fades out a second or two after the last nudge.
///
/// **There is no API to show the system volume HUD.** An app can only *suppress* it, which is what
/// an `MPVolumeView` in the window does — and that was the whole problem with driving the system
/// level: it worked, and it cost the hardware buttons their own indicator. So the dial reports the
/// level it actually controls, and the system keeps reporting the one it controls. Two indicators
/// for two different things, each shown by whoever owns it.
///
/// **Dim on purpose.** This is a confirmation, not a control: it answers "did that do anything?" in
/// the second after a nudge and then gets out of the way. Drawn at full strength it would read as
/// something to reach for, and the one thing you reach for on this screen is the dial.
///
/// It replaced a vertical capsule on the left edge, which in turn replaced an always-visible bar
/// under the scrubber. The capsule borrowed the system HUD's shape, and borrowing that shape to
/// report a *different* number is the kind of near-miss that reads as a bug — you press the
/// hardware buttons expecting the same thing to move.
struct VolumeSlider: View {

    /// `0...1`.
    let volume: Double

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.caption)
                .foregroundColor(.sonicTextSecondary)
                // Fixed width so the track does not shift sideways when the glyph changes — the
                // slash and the waves are different widths, and a track that jumps while you are
                // watching it move is reporting two things at once.
                .frame(width: Sizing.volumeGlyphWidth, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.sonicTextMuted.opacity(Self.trackTint))

                    Capsule()
                        .fill(Color.sonicPrimary.opacity(Self.fillTint))
                        .frame(width: geometry.size.width * volume.clampedFraction)
                }
            }
            .frame(height: Sizing.volumeTrackHeight)
        }
        .frame(height: Sizing.volumeGlyphWidth)
        .accessibilityElement()
        .accessibilityLabel(Text("Volume"))
        .accessibilityValue(Text("\(Int((volume * 100).rounded())) percent"))
    }

    /// The unfilled part: present enough to show how far there is left to go, faint enough not to
    /// draw a line across the screen.
    private static let trackTint: Double = 0.25

    /// The filled part. Below full strength for the same reason the whole control is — it reports
    /// rather than invites.
    private static let fillTint: Double = 0.7
}
