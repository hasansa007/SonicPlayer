import SwiftUI

/// The bar pinned above Home while something is playing (#47, epic #6).
///
/// Second consumer of all three slice-1 components — `SonicScrubber` for the progress hairline,
/// `ArtworkView` for the thumbnail, `IconControlButton` for the transport. It is what proves
/// they are shared rather than merely extracted.
///
/// **Previous and next were 20 × 17pt of tappable area** — a bare `Image` with no frame, against
/// Apple's 44 × 44 minimum. `IconControlButton` makes that shape unavailable, so they are now
/// the full target. The bar's own height is unchanged: `Sizing.thumbnail` plus
/// `Sizing.barRowInsetV` top and bottom.
struct MiniPlayerView: View {
    let player: PlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            SonicScrubber(
                progress: player.progress,
                height: Sizing.hairlineTrackHeight,
                cornerRadius: 0,
                showsTrack: false,
                animation: Motion.miniProgress
            )

            HStack(spacing: Spacing.md) {
                expandButton

                IconControlButton(
                    systemImage: "backward.fill",
                    label: Text("Previous track"),
                    action: { player.previousTrack() }
                )

                IconControlButton(
                    systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                    label: Text(player.isPlaying ? "Pause" : "Play"),
                    action: { player.playPauseTapped() }
                )

                IconControlButton(
                    systemImage: "forward.fill",
                    label: Text("Next track"),
                    action: { player.nextTrack() }
                )

                IconControlButton(
                    systemImage: "xmark",
                    label: Text("Stop playback"),
                    size: .compact,
                    font: .sonicTimeLabel,
                    action: { player.clearSession() }
                )
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Sizing.barRowInsetV)
        }
        .background(.ultraThinMaterial)
        .sonicShadow(Elevation.bar)
    }

    private var expandButton: some View {
        Button {
            player.setExpanded(true)
        } label: {
            HStack(spacing: Spacing.sm + 2) {
                ArtworkView(
                    image: player.artwork,
                    side: Sizing.thumbnail,
                    cornerRadius: Radius.sm,
                    isPlaying: player.isPlaying,
                    shadow: nil
                )

                Text(player.currentTrack?.title ?? String(localized: "Not Playing"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Open player"))
        .accessibilityValue(Text(player.currentTrack?.title ?? ""))
    }
}
