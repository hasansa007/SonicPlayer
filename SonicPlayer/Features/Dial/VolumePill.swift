import SwiftUI

/// A transient volume indicator on the left edge, in the shape iOS uses for its own.
///
/// **Ours, not the system's, and deliberately.** The obvious ask is to show the real iOS HUD — but
/// there is no public API to set system volume (`AVAudioSession.outputVolume` is read-only), and the
/// known workaround reaches into a hidden `MPVolumeView`'s slider: undocumented, historically
/// tolerated, and a poor bet in a project carrying an App Store compliance section. It would also
/// change the *wrong thing*. The dial moves this app's own gain, which is why it composes with the
/// hardware buttons instead of fighting them.
///
/// So: the same affordance, in the same place, reporting the level we actually control.
///
/// It replaced an always-visible bar under the scrubber. That bar answered "did that do anything?"
/// at the cost of putting a control you rarely touch permanently on the screen — and the question is
/// only ever asked in the second after a nudge.
struct VolumePill: View {

    /// `0...1`.
    let volume: Double

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(Color.sonicSurface)

            Capsule()
                .fill(Color.sonicPrimary)
                .frame(height: Sizing.volumePillHeight * volume.clampedFraction)
        }
        .frame(width: Sizing.volumePillWidth, height: Sizing.volumePillHeight)
        .overlay(alignment: .bottom) {
            Image(systemName: volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.footnote)
                // Sits on the filled part when there is one, so it needs the contrasting colour
                // there and the ordinary one when the fill has dropped below it.
                .foregroundColor(volume > Self.glyphThreshold ? .white : .sonicTextSecondary)
                .padding(.bottom, Spacing.sm)
        }
        .clipShape(Capsule())
        .sonicShadow(Elevation.control)
        .accessibilityElement()
        .accessibilityLabel(Text("Volume"))
        .accessibilityValue(Text("\(Int((volume * 100).rounded())) percent"))
    }

    /// Above this the fill has reached the glyph, so the glyph has to invert to stay legible.
    private static let glyphThreshold: Double = 0.22
}
