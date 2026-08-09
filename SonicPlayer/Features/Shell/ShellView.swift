import SwiftUI

/// The wheel canvas (#6).
///
/// **The governing rule: the wheel is furniture.** It owns the bottom `Sizing.wheelZone` and
/// nothing is drawn over it. The stage above changes; the controls do not. That is what makes this
/// read as a device rather than as a skin.
///
/// **Landscape is deliberately unanswered.** 200pt of wheel in a 393pt-tall canvas does not work,
/// and the answer is the wheel moved to one side rather than this layout rotated. Until that is
/// designed, compact height falls back to `PlayerView`. **Slice 2 removes this fallback and must
/// not ship without the landscape design.**
struct ShellView: View {

    let shell: ShellViewModel
    let player: PlayerViewModel

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Fixed point sizes have to be read through `@ScaledMetric`, or they are the same number at
    /// every accessibility setting — the bug #47 fixed on the player, which this screen replaces.
    @ScaledMetric(relativeTo: .largeTitle) private var stateIconSize = DisplayFont.stateIcon
    @ScaledMetric(relativeTo: .title3) private var titleLineHeight = Sizing.titleLine

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        if isLandscape {
            PlayerView(player: player)
        } else {
            portrait
        }
    }

    private var portrait: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.sonicPrimaryLight.opacity(0.15),
                    Color.sonicBackground,
                    Color.sonicBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Centred in the space above the wheel, not pinned to the top. Top-aligning left a
            // hand's width of dead air between the time labels and the ring on a real device —
            // the mockups this was drawn from were 474pt tall and the phone is 874pt, so the gap
            // only existed at full size. Found by looking at it, which is what Task 12 is for.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                stage
                Spacer(minLength: 0)
            }
            .padding(.bottom, Sizing.wheelZone)

            if let hud = shell.hud {
                WheelHUD(label: hud.label, value: hud.value)
                    .padding(.bottom, Sizing.wheelZone - Spacing.xs)
                    .animation(Motion.hudFade, value: hud)
            }

            wheelZone
        }
    }

    /// Everything above the wheel.
    ///
    /// **All three states, in `PlayerView`'s order and for its reasons** — epic #6 requires every
    /// screen to have them. The order matters: `loadTrack` sets `currentTrack` and `isLoadingTrack`
    /// in the same breath, so "loading" is not "no track", and gating the loading state on a zero
    /// duration keeps it off the screen during a track *switch*, where the previous duration is
    /// still valid and blanking would be a regression rather than a fix.
    @ViewBuilder
    private var stage: some View {
        VStack(spacing: Spacing.xl) {
            if let error = player.openError {
                errorState(error)
            } else if player.currentTrack == nil {
                EmptyStateView(
                    icon: "music.note",
                    title: "No Track Selected",
                    message: "Select a file from the Library to start playing",
                    iconStyle: AnyShapeStyle(LinearGradient.sonicGradient),
                    iconSize: stateIconSize,
                    spacing: Spacing.lg
                )
            } else if player.isLoadingTrack && player.duration == 0 {
                loadingState
            } else {
                nowPlaying
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.xl)
    }

    private var loadingState: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(.sonicPrimary)
                .frame(height: stateIconSize)

            Text("Loading Track")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.sonicTextPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Spacing.xl) {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Couldn't Open This File",
                iconStyle: AnyShapeStyle(Color.sonicOrange),
                iconSize: stateIconSize,
                spacing: Spacing.lg
            )

            // Rendered separately rather than through `message:`, which is a `LocalizedStringKey`.
            // This string comes from the failing `Error` and is already localised by whoever
            // produced it — running it through the catalog looks up a key that is not there.
            Text(message)
                .font(.subheadline)
                .foregroundColor(.sonicTextSecondary)
                .multilineTextAlignment(.center)

            Button("Dismiss") { player.openError = nil }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.sonicPrimary)
                .padding(.horizontal, Sizing.chipInsetH)
                .padding(.vertical, Spacing.sm)
                .background(
                    Color.sonicPrimary.opacity(ControlTint.on),
                    in: RoundedRectangle(cornerRadius: Radius.sm)
                )
                .buttonStyle(ScaleButtonStyle())
        }
    }

    private var nowPlaying: some View {
        VStack(spacing: Spacing.xl) {
            ArtworkView(
                image: player.artwork,
                side: Sizing.artworkCompact,
                cornerRadius: Radius.lg,
                isPlaying: player.isPlaying && player.progress > 0,
                showsWaveform: true
            )

            ScrollingText(text: player.currentTrack?.title ?? String(localized: "Unknown Track"))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.sonicTextPrimary)
                .frame(height: titleLineHeight)

            // Coarse travel. The wheel is the fine half of the same control — drag to get near,
            // turn to land.
            SonicScrubber(
                progress: player.progress,
                duration: player.duration,
                onSeek: { player.seek(to: $0) }
            )

            HStack {
                Text(player.currentTimeFormatted ?? "0:00")
                Spacer()
                Text(player.durationFormatted ?? "0:00")
            }
            .font(.sonicTimeLabel)
            .foregroundColor(.sonicTextSecondary)
            .monospacedDigit()
        }
    }

    private var wheelZone: some View {
        RotaryWheel(
            hubLabel: player.isPlaying ? "❙❙" : "▶",
            isPlaying: player.isPlaying,
            onCommand: { shell.receive($0) }
        )
        .frame(height: Sizing.wheelZone, alignment: .center)
    }
}
