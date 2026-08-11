import SwiftUI
import UIKit

/// Album art, or the gradient tile that stands in for it (#47).
///
/// Consumers today: the full player's 280/120/80pt artwork, and the mini-player's 40pt
/// thumbnail. Two, in two files, which is what earns it a place in slice 1.
///
/// The two used to build this separately and disagree about the details — different corner
/// radii for the same state, a `waveform` glyph in one and a `music.note` in the other, and a
/// shadow on one but not the other. One component, one set of answers.
struct ArtworkView: View {

    let image: UIImage?
    let side: CGFloat
    var cornerRadius: CGFloat = Radius.lg
    /// Whether the placeholder animates. A tile with real artwork never does.
    var isPlaying: Bool = false
    /// The queue-open player wants its small tile calm even while playing.
    var showsWaveform: Bool = true
    var shadow: Shadow? = Elevation.artwork

    var body: some View {
        content
            .modifier(OptionalShadow(shadow: shadow))
            // Decorative: the track title beside it is the label. Without this, VoiceOver
            // announces an unnamed image between the title and the transport controls.
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(LinearGradient.sonicGradient)
                .frame(width: side, height: side)
                .overlay { placeholder }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if isPlaying && showsWaveform {
            SonicWaveform(isPlaying: isPlaying, size: side <= Sizing.thumbnail ? .mini : .full)
                .foregroundColor(.white.opacity(0.85))
        } else {
            Image(systemName: "waveform")
                .font(side <= Sizing.artworkCollapsed ? .sonicControlGlyph : .largeTitle)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

/// `.sonicShadow(_:)` where the shadow is optional. An `if let` around the modifier would change
/// the view's identity and re-create the tile whenever it toggled.
private struct OptionalShadow: ViewModifier {
    let shadow: Shadow?

    func body(content: Content) -> some View {
        if let shadow {
            content.sonicShadow(shadow)
        } else {
            content
        }
    }
}

/// The "audio is playing" bars, at the two sizes the app uses.
///
/// Folded in here rather than given its own file because `ArtworkView` is its only consumer —
/// both of the old implementations (`PlayerWaveformView`, 5 bars; `MiniWaveformView`, 3 bars)
/// were only ever drawn inside an artwork tile.
struct SonicWaveform: View {

    enum Size {
        case full, mini

        var barCount: Int { self == .full ? 5 : 3 }
        var barWidth: CGFloat { self == .full ? 6 : 3 }
        var spacing: CGFloat { self == .full ? 5 : Radius.hairline }
        var restingHeight: CGFloat { self == .full ? Spacing.sm : Spacing.xs + 2 }

        /// Uneven on purpose, so the row reads as a level meter and not a progress bar.
        var peaks: [CGFloat] { self == .full ? [28, 36, 20, 32, 24] : [10, 6, 8] }
    }

    let isPlaying: Bool
    var size: Size = .full

    @State private var animating = false

    var body: some View {
        HStack(alignment: .center, spacing: size.spacing) {
            ForEach(0..<size.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: Radius.hairline)
                    .frame(
                        width: size.barWidth,
                        height: animating ? size.peaks[index % size.peaks.count] : size.restingHeight
                    )
                    .animation(
                        isPlaying ? Motion.waveformBar(index: index) : Motion.settle,
                        value: animating
                    )
            }
        }
        .onAppear { animating = isPlaying }
        .onChange(of: isPlaying) { _, playing in animating = playing }
        .accessibilityHidden(true)
    }
}

#Preview("Sizes and states") {
    VStack(spacing: Spacing.xl) {
        HStack(alignment: .bottom, spacing: Spacing.xl) {
            ArtworkView(image: nil, side: Sizing.artworkCompact, isPlaying: true)
            ArtworkView(
                image: nil, side: Sizing.artworkCollapsed, cornerRadius: Radius.md,
                isPlaying: true, showsWaveform: false
            )
            ArtworkView(
                image: nil, side: Sizing.thumbnail, cornerRadius: Radius.sm,
                isPlaying: true, shadow: nil
            )
        }
        ArtworkView(image: nil, side: Sizing.artworkCompact, isPlaying: false)
    }
    .padding(Spacing.xxl)
}
