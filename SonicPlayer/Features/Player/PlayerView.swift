import SwiftUI
import MediaPlayer

/// The full-screen player (#47, epic #6).
///
/// What is left here is **composition and state** — which piece goes where, in which of the three
/// layouts. Every measurement resolves to a token in `DesignSystem/Tokens.swift`, the repeated
/// pieces are the three slice-1 components, and the seek arithmetic went to
/// `Domain/ScrubGeometry` (#52, #53). `scripts/lint-magic-numbers.sh` is what keeps it that way.
struct PlayerView: View {
    let player: PlayerViewModel

    @State private var showQueue = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// The empty/error icon, scaled. A bare `.system(size: 80)` is the same 80 points at every
    /// accessibility setting, so at AX5 it sat beside body text three times its relative size.
    @ScaledMetric(relativeTo: .largeTitle) private var stateIconSize = DisplayFont.stateIcon

    /// One line of the track title. Fixed at 28pt it clipped the descenders at the accessibility
    /// sizes — `ScrollingText` sits in a `GeometryReader`, which offers no intrinsic height, so
    /// whatever is reserved here is all the title ever gets.
    @ScaledMetric(relativeTo: .title3) private var titleLineHeight = Sizing.titleLine

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
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

            if let error = player.openError {
                errorState(error)
            } else if player.currentTrack == nil {
                emptyState
            } else if player.isLoadingTrack && player.duration == 0 {
                // `loadTrack` sets `currentTrack` and `isLoadingTrack` in the same breath, so
                // "loading" is not "no track" — it is "a track with nothing to show yet". Gating
                // on a zero duration keeps this off the screen during a track *switch*, where
                // the previous duration is still valid and blanking the player would be a
                // regression rather than a fix.
                loadingState
            } else if isLandscape {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        stateContainer {
            EmptyStateView(
                icon: "music.note",
                title: "No Track Selected",
                message: "Select a file from the Library to start playing",
                iconStyle: AnyShapeStyle(LinearGradient.sonicGradient),
                iconSize: stateIconSize,
                spacing: Spacing.lg
            )
        }
    }

    /// Previously rendered as the empty state, so a slow file was indistinguishable from no file.
    /// `isLoadingTrack` has been set in four places since #15 and read by no view until now.
    private var loadingState: some View {
        stateContainer {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    /// #33 gave the view model an `openError` and nothing ever rendered it — a failed open left
    /// the user on a blank player with no explanation.
    private func errorState(_ message: String) -> some View {
        stateContainer {
            VStack(spacing: Spacing.xl) {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Couldn't Open This File",
                    iconStyle: AnyShapeStyle(Color.sonicOrange),
                    iconSize: stateIconSize,
                    spacing: Spacing.lg
                )

                // Rendered separately rather than through `message:`, which is now a
                // `LocalizedStringKey`. This string comes from the failing `Error` and is
                // already localised by whoever produced it — running it through the catalog
                // would look up a key that by definition is not there.
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.sonicTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)

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
    }

    private func stateContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: Spacing.xxl) {
            grabber
            content()
        }
        .padding(Spacing.lg)
    }

    // MARK: - Layouts

    private var portraitLayout: some View {
        VStack(spacing: Spacing.xl) {
            grabber

            VStack(spacing: Spacing.xl) {
                artwork

                if showQueue {
                    queueList
                } else {
                    trackTitle
                }
            }
            .frame(maxHeight: .infinity)

            VStack(spacing: Spacing.xl) {
                Spacer()
                scrubberRow
                transportRow
                VolumeView()
                    .frame(height: Sizing.tapTarget)
                    .padding(.horizontal, Spacing.lg)
                toolRow
                Spacer()
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.bottom, Spacing.xxxl)
    }

    private var landscapeLayout: some View {
        HStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.sm) {
                if showQueue {
                    queueList
                } else {
                    artwork
                    Text(player.currentTrack?.title ?? "")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.sonicTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: Sizing.landscapeColumn)
            .clipped()

            VStack(spacing: Spacing.sm) {
                scrubberRow
                transportRow
                toolRow
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Pieces

    private var grabber: some View {
        RoundedRectangle(cornerRadius: Radius.hairline)
            .fill(Color.sonicTextSecondary.opacity(0.3))
            .frame(width: Sizing.grabber.width, height: Sizing.grabber.height)
            .padding(.top, Spacing.sm)
            .accessibilityHidden(true)
    }

    private var artworkSide: CGFloat {
        if showQueue { return Sizing.artworkCollapsed }
        if isLandscape { return Sizing.artworkCompact }
        return Sizing.artworkFull
    }

    private var artwork: some View {
        ArtworkView(
            image: player.artwork,
            side: artworkSide,
            cornerRadius: showQueue ? Radius.md : Radius.lg,
            isPlaying: player.isPlaying && player.progress > 0,
            showsWaveform: !showQueue
        )
    }

    private var trackTitle: some View {
        ScrollingText(text: player.currentTrack?.title ?? String(localized: "Unknown Track"))
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundColor(.sonicTextPrimary)
            .frame(height: titleLineHeight)
            .padding(.horizontal, Spacing.sm)
    }

    private var scrubberRow: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.lg) {
                IconControlButton(
                    systemImage: "gobackward.\(Int(player.skipDuration.rawValue))",
                    label: Text("Skip back \(Int(player.skipDuration.rawValue)) seconds"),
                    action: { player.skipBackward() }
                )

                SonicScrubber(
                    progress: player.progress,
                    duration: player.duration,
                    onSeek: { player.seek(to: $0) }
                )

                IconControlButton(
                    systemImage: "goforward.\(Int(player.skipDuration.rawValue))",
                    label: Text("Skip forward \(Int(player.skipDuration.rawValue)) seconds"),
                    action: { player.skipForward() }
                )
            }

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

    /// **Transport keeps its LTR order in every language, RTL included.**
    ///
    /// An `HStack` mirrors under RTL, so `[previous, play, next]` rendered as `[next, play,
    /// previous]` in Arabic: the glyphs were right, the order was not, and "next" sat where the eye
    /// expects "previous". These controls point at the direction the *media* travels rather than
    /// the direction text is read — the same reason Apple's own player does not mirror them — so
    /// pinning the row to `.leftToRight` is the fix rather than swapping the icons, which would
    /// leave the arrows pointing away from the buttons they belong to.
    ///
    /// It also settles the play glyph's optical nudge below, which is an absolute `.offset(x:)` and
    /// would otherwise push the triangle the wrong way in Arabic.
    private var transportRow: some View {
        HStack(spacing: Spacing.xxxl) {
            IconControlButton(
                systemImage: "backward.end.fill",
                label: Text("Previous track"),
                size: .secondary,
                font: .sonicTransportGlyph,
                isEnabled: player.hasPreviousTrack || player.canRestartCurrentTrack,
                action: { player.previousTrack() }
            )

            Button {
                player.playPauseTapped()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.sonicPrimary)
                        .frame(width: Sizing.playButton, height: Sizing.playButton)
                        .sonicShadow(Elevation.control)

                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.sonicTransportGlyph)
                        .foregroundColor(.white)
                        // The play triangle's visual centre sits left of its bounding box's;
                        // the pause bars' does not, so only one glyph is nudged.
                        .offset(x: player.isPlaying ? 0 : Sizing.playGlyphOpticalOffset)
                }
            }
            .accessibilityLabel(Text(player.isPlaying ? "Pause" : "Play"))

            IconControlButton(
                systemImage: "forward.end.fill",
                label: Text("Next track"),
                size: .secondary,
                font: .sonicTransportGlyph,
                isEnabled: player.hasNextTrack,
                action: { player.nextTrack() }
            )
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private var toolRow: some View {
        HStack {
            Menu {
                ForEach(PlaybackSpeed.allCases) { speed in
                    Button {
                        player.setPlaybackSpeed(speed)
                    } label: {
                        HStack {
                            Text(speed.displayText)
                            if speed == player.playbackSpeed {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(player.playbackSpeed.displayText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(.sonicPrimary)
                    .padding(.horizontal, Sizing.chipInsetH)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        Color.sonicPrimary.opacity(ControlTint.on),
                        in: RoundedRectangle(cornerRadius: Radius.sm)
                    )
            }
            .accessibilityLabel(Text("Playback speed"))

            Spacer(minLength: 0)

            IconControlButton(
                systemImage: player.repeatMode.icon,
                label: Text("Repeat"),
                style: .toggle(isOn: player.repeatMode != .off),
                action: { player.toggleRepeatMode() }
            )

            IconControlButton(
                systemImage: "shuffle",
                label: Text("Shuffle"),
                style: .toggle(isOn: player.isShuffleEnabled),
                action: { player.toggleShuffle() }
            )

            IconControlButton(
                systemImage: showQueue ? "list.bullet.rectangle.fill" : "list.bullet.rectangle",
                label: Text("Queue"),
                style: .toggle(isOn: showQueue),
                action: { withAnimation(Motion.panel) { showQueue.toggle() } }
            )
        }
    }

    private var queueList: some View {
        ScrollView {
            if player.queue.isEmpty {
                Text("No tracks in queue")
                    .font(.subheadline)
                    .foregroundColor(.sonicTextSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Sizing.queuePlaceholder)
            } else {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, track in
                        queueRow(index: index, track: track)
                    }
                }
                .padding(.horizontal, Spacing.xs)
            }
        }
    }

    /// #48 gave the shared Row its second and third consumers, so the queue row that slice 1
    /// deliberately left inline is now `SonicRow` — which is exactly the sequence ADR 0002
    /// describes: build the component in the slice where the second caller appears, not before.
    private func queueRow(index: Int, track: AudioFile) -> some View {
        SonicRow(
            leading: index == player.currentIndex
                ? .marker(systemImage: "speaker.wave.3.fill", text: nil)
                : .marker(systemImage: nil, text: "\(index + 1)"),
            title: track.title,
            secondary: .duration(track.durationFormatted),
            isEmphasised: index == player.currentIndex,
            isSelected: index == player.currentIndex
        )
        .onTapGesture {
            if index != player.currentIndex {
                player.jumpToTrack(index)
            }
        }
    }
}

// MARK: - Volume View

struct VolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView()
        volumeView.showsVolumeSlider = true
        for subview in volumeView.subviews where subview is UIButton {
            subview.isHidden = true
        }
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Scrolling Text

/// A title too long for its container, scrolled horizontally.
///
/// **This is already correct under RTL. Do not make it direction-aware — that breaks it.** (#54)
///
/// The offsets below look absolute and are not: **SwiftUI mirrors `.offset(x:)` under RTL**, the
/// same way `ZStack(alignment: .leading)` mirrors its anchor. Measured 2026-08-08 with three
/// squares at offsets `0`, `+100`, `-100` in this exact container, located by pixel:
///
///     en:  offset 0 -> x140    offset +100 -> x440    (+100 moved RIGHT)
///     ar:  offset 0 -> x1064   offset +100 -> x764    (+100 moved LEFT)
///
/// So `-(textWidth + wrapGap)` travels leftward in English and **rightward in Arabic**, which is
/// what each reading direction needs, and the wrapped copy lands on the trailing side in both.
/// Verified end to end on a long Arabic title by tracking the wrap gap across four frames:
/// `ar 83 -> 638 -> 777 -> 914` (rightward), `en 1036 -> 926 -> 788 -> 648` (leftward).
///
/// #54 claimed the opposite — that the anchor flips and these offsets do not — and a fix built on
/// that reading double-flipped the sign and made Arabic scroll backwards. Reasoning about it gave
/// the wrong answer three times; only rendering it and measuring settled it. The issue is closed
/// as not-a-bug and carries the same numbers.
struct ScrollingText: View {
    let text: String
    @State private var offset: CGFloat = 10
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    /// The gap between the title and its wrapped second copy.
    private static let wrapGap = Spacing.xxxl
    /// Points per second. Long titles take proportionally longer rather than speeding up.
    private static let scrollSpeed: Double = 30
    /// How long the title sits still before it starts, so a glance can read the beginning.
    private static let startDelay: TimeInterval = 2

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Text(text)
                    .background(
                        GeometryReader { textGeometry in
                            Color.clear
                                .onAppear {
                                    textWidth = textGeometry.size.width
                                    containerWidth = geometry.size.width
                                }
                                .onChange(of: text) { _, _ in
                                    textWidth = textGeometry.size.width
                                    containerWidth = geometry.size.width
                                    offset = 0
                                }
                        }
                    )
                    .offset(x: offset)
                    .fixedSize()

                if textWidth > containerWidth {
                    Text(text)
                        .offset(x: offset + textWidth + Self.wrapGap)
                        .fixedSize()
                }
            }
            .clipped()
            .onAppear {
                if textWidth > containerWidth {
                    startScrolling()
                }
            }
            .onChange(of: textWidth) { _, newWidth in
                offset = 0
                if newWidth > containerWidth {
                    startScrolling()
                }
            }
        }
    }

    private func startScrolling() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.startDelay) {
            let duration = max(0.1, Double(textWidth) / Self.scrollSpeed)
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                offset = -(textWidth + Self.wrapGap)
            }
        }
    }
}

