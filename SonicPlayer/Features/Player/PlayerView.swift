import ComposableArchitecture
import SwiftUI
import MediaPlayer

struct PlayerView: View {
    @Bindable var store: StoreOf<PlayerFeature>
    @State private var showQueue = false

    var colors: [Color] {
        Color.sonicTealColors
    }
    
    var body: some View {
        ZStack {
            // Dynamic background gradient based on artwork
            LinearGradient(
                colors: [
                    colors.first?.opacity(0.3) ?? Color.sonicPrimaryLight.opacity(0.3),
                    Color.sonicBackground,
                    Color.sonicBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if store.currentTrack == nil {
                emptyStateView
            } else {
                playerContent
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            headerView

            EmptyStateView(
                icon: "music.note",
                title: "No Track Selected",
                message: "Select a file from the Library tab to start playing",
                iconStyle: AnyShapeStyle(.linearGradient(
                    colors: [Color.sonicPrimaryDark, Color.sonicPrimary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )),
                iconSize: 80,
                spacing: 16
            )
        }
        .padding()
    }

    private var playerContent: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack(alignment: .top) {
                if isLandscape {
                    // Landscape layout: artwork, controls, queue
                    landscapeLayout(geometry: geometry)
                } else {
                    // Portrait layout: vertical stack
                    portraitLayout
                }
            }
        }
    }

    private var portraitLayout: some View {
        VStack(spacing: 20) {
            headerView

            // Combined section to maintain consistent height
            VStack(spacing: 20) {
                // Animated thumbnail
                animatedThumbnailView
                    .frame(height: showQueue ? 100 : nil)
                    .padding(.top, showQueue ? 20 : 0)

                if showQueue {
                    // Playback mode buttons
                    playbackModeButtons
                        .transition(.opacity)
                        .padding(.top, 8)
                }

                // Track info or queue (takes remaining space)
                if showQueue {
                    queueListView
                } else {
                    trackInfoView
                }
            }
            .frame(maxHeight: .infinity)

            // Player controls (fixed at bottom)
            fullPlayerControls
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func landscapeLayout(geometry: GeometryProxy) -> some View {
        HStack(spacing: 20) {
            // Left: Artwork + track info
            VStack(spacing: 16) {
                Spacer()
                landscapeArtwork
                trackInfoView
                Spacer()
            }
            .frame(width: geometry.size.width * 0.30)

            // Middle: Controls
            VStack(spacing: 16) {
                headerView
                progressSliderWithSkipsView
                controlsView
                VolumeView()
                    .frame(height: 40)
                    .padding(.horizontal)
                bottomControlsView
                Spacer(minLength: 0)
            }
            .frame(maxWidth: showQueue ? geometry.size.width * 0.34 : .infinity)

            if showQueue {
                // Right: Queue
                VStack(alignment: .leading, spacing: 12) {
                    Text("Up Next")
                        .font(.headline)
                        .foregroundColor(.sonicTextPrimary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)

                    queueListView
                        .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var landscapeArtwork: some View {
        ZStack {
            if let artwork = store.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.sonicPrimaryLight.opacity(0.15))
                    }
            } else {
                // Gradient background
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // Waveform
            WaveformView(
                isPlaying: store.isPlaying,
                barCount: 12,
                barWidth: 4,
                baseHeight: 24,
                amplitudeRange: 4...28
            )
            .foregroundColor(.white.opacity(0.8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Border overlay
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        }
        .frame(width: 180, height: 180)
        .shadow(
            color: colors.first?.opacity(0.5) ?? Color.sonicPrimary.opacity(0.4),
            radius: 20,
            x: 0,
            y: 10
        )
    }

    private var animatedThumbnailView: some View {
        HStack(alignment: .top, spacing: 12) {
            // Artwork / Waveform
            if store.currentTrack != nil {
                ZStack {
                    if let artwork = store.artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .frame(width: showQueue ? 80 : 250, height: showQueue ? 80 : 250)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Color.sonicPrimaryLight.opacity(0.15))
                            }
                    } else {
                        // Gradient background
                        RoundedRectangle(cornerRadius: showQueue ? 12 : 24)
                            .fill(
                                LinearGradient(
                                    colors: colors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    // Waveform (artwork loading removed for now)
                    if showQueue {
                        WaveformView(
                                isPlaying: store.isPlaying,
                                barWidth: 3,
                                baseHeight: 10,
                                amplitudeRange: 4...10
                            )
                            .frame(width: 40, height: 30)
                            .foregroundColor(.white.opacity(0.8))
                    } else {
                        WaveformView(
                                isPlaying: store.isPlaying,
                                barCount: 16,      // Enough bars to fill width
                                barWidth: 4,       // Thicker bars
                                baseHeight: 32,    // Taller base
                                amplitudeRange: 4...34 // More visible animation
                            )
                            .foregroundColor(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped() // Ensure waveform is clipped
                    }

                    // Border overlay
                    RoundedRectangle(cornerRadius: showQueue ? 12 : 24)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: showQueue ? 1 : 2
                        )
                }
                .frame(width: showQueue ? 80 : 250, height: showQueue ? 80 : 250)
                .shadow(
                    color: colors.first?.opacity(showQueue ? 0.3 : 0.5) ?? Color.sonicPrimary.opacity(0.4),
                    radius: showQueue ? 8 : 20,
                    x: 0,
                    y: showQueue ? 4 : 10
                )
            }

            if showQueue {
                // Track info when minimized
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.currentTrack?.title ?? "Unknown Track")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicTextPrimary)
                        .lineLimit(2)

                    if let format = store.currentTrack?.format {
                        Text(format.displayName)
                            .font(.caption2)
                            .foregroundColor(.sonicTextSecondary)
                    }
                }
                .transition(.opacity)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: showQueue ? .leading : .center)
    }

    private var playbackModeButtons: some View {
        HStack(spacing: 12) {
            // Shuffle button
            Button {
                // TODO: Add shuffle action
            } label: {
                Image(systemName: "shuffle")
                    .font(.body)
                    .foregroundColor(.sonicTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .buttonStyle(ScaleButtonStyle())

            // Repeat button
            Button {
                // TODO: Add repeat action
            } label: {
                Image(systemName: "repeat")
                    .font(.body)
                    .foregroundColor(.sonicTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .buttonStyle(ScaleButtonStyle())

            // Loop button
            Button {
                // TODO: Add loop action
            } label: {
                Image(systemName: "infinity")
                    .font(.body)
                    .foregroundColor(.sonicTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .buttonStyle(ScaleButtonStyle())
        }
    }

    private var queueListView: some View {
        ScrollView {
            if store.queue.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Text("There's no music in the queue.")
                        .font(.subheadline)
                        .foregroundColor(.sonicTextSecondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(store.queue.enumerated()), id: \.element.id) { index, track in
                        HStack(spacing: 12) {
                            if index == store.currentIndex {
                                Image(systemName: "speaker.wave.3.fill")
                                    .font(.caption)
                                    .foregroundColor(.sonicPrimary)
                                    .frame(width: 24)
                            } else {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 24)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.subheadline)
                                    .fontWeight(index == store.currentIndex ? .semibold : .regular)
                                    .foregroundColor(.sonicTextPrimary)
                                    .lineLimit(1)

                                Text(track.durationFormatted)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            if index == store.currentIndex {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.sonicPrimary.opacity(0.15))
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                    }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Only jump if it's a different track
                            if index != store.currentIndex {
                                store.send(.jumpToTrack(index))
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var fullPlayerControls: some View {
        VStack(spacing: 20) {
            Spacer()

            // Progress slider with skip buttons
            progressSliderWithSkipsView

            // Playback controls
            controlsView

            // Volume Slider
            VolumeView()
                .frame(height: 40)
                .padding(.horizontal)

            // Bottom controls (Speed and Playlist)
            bottomControlsView

            Spacer()
        }
    }

    private var headerView: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.sonicTextSecondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
        }
    }

    private var trackInfoView: some View {
        VStack(spacing: 8) {
            ScrollingText(text: store.currentTrack?.title ?? "Unknown Track")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.sonicTextPrimary)
                .frame(height: 28)
                .padding(.horizontal, 10)

            if let format = store.currentTrack?.format {
                Text(format.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(LinearGradient.sonic(colors: colors))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.sonicPrimary.opacity(0.12))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            }
                    }
            }
        }
    }

    private var progressSliderWithSkipsView: some View {
        let colors = self.colors // Use the global computed colors

        return VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Skip Backward Button (left side)
                Button {
                    store.send(.skipBackward)
                } label: {
                    Image(systemName: "gobackward.\(Int(store.skipDuration.rawValue))")
                        .font(.title3)
                        .sonicGradientForeground(colors: colors)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(ScaleButtonStyle())

                // Custom slider with dynamic colors
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Track background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.sonicBorder.opacity(0.3))
                            }
                            .frame(height: 8)

                        // Progress with dynamic gradient
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient.sonic(
                                    colors: colors.isEmpty ? [.sonicPrimaryDark, .sonicPrimary] : colors
                                )
                            )
                            .frame(width: geometry.size.width * store.progress, height: 8)
                            .animation(.linear(duration: 0.1), value: store.progress)
                            .shadow(
                                color: (colors.first ?? .sonicPrimary).opacity(0.4),
                                radius: 4,
                                x: 0,
                                y: 2
                            )
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let progress = min(max(0, value.location.x / geometry.size.width), 1)
                                let newTime = progress * store.duration
                                store.send(.seekToPosition(newTime))
                            }
                    )
                }
                .frame(height: 8)

                // Skip Forward Button (right side)
                Button {
                    store.send(.skipForward)
                } label: {
                    Image(systemName: "goforward.\(Int(store.skipDuration.rawValue))")
                        .font(.title3)
                        .sonicGradientForeground(colors: colors)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(ScaleButtonStyle())
            }

            // Time labels
            HStack {
                Text(store.currentTimeFormatted ?? "0:00")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.sonicTextSecondary)
                    .monospacedDigit()

                Spacer()

                Text(store.durationFormatted ?? "0:00")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.sonicTextSecondary)
                    .monospacedDigit()
            }
        }
    }

    private var controlsView: some View {
        let colors = self.colors // Use the global computed colors

        return HStack(spacing: 40) {
            // Previous Track
            Button {
                store.send(.previousTrack)
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .foregroundStyle(store.hasPreviousTrack ? LinearGradient.sonic(colors: colors) : LinearGradient.sonic(colors: [Color.sonicTextMuted]))
                    .frame(width: 56, height: 56)
            }
            .disabled(!store.hasPreviousTrack && store.currentTime < 3)
            .buttonStyle(ScaleButtonStyle())

            // Play/Pause button
            Button {
                store.send(.playPauseButtonTapped)
            } label: {
                
                ZStack {
                    Circle()
                        .fill(LinearGradient.sonic(colors: colors))
                        .frame(width: 80, height: 80)
                        .shadow(color: (colors.first ?? Color.sonicBlue).opacity(0.4), radius: 12, x: 0, y: 6)

                    Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .offset(x: store.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(ScaleButtonStyle())

            // Next Track
            Button {
                store.send(.nextTrack)
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .foregroundStyle(store.hasNextTrack ? LinearGradient.sonic(colors: colors) : LinearGradient.sonic(colors: [Color.sonicTextMuted]))
                    .frame(width: 56, height: 56)
            }
            .disabled(!store.hasNextTrack)
            .buttonStyle(ScaleButtonStyle())
        }
    }
    
    private var bottomControlsView: some View {
        let colors = self.colors // Use the global computed colors

        return HStack(spacing: 16) {

            // Speed control
            Menu {
                ForEach(PlaybackSpeed.allCases) { speed in
                    Button {
                        store.send(.setPlaybackSpeed(speed))
                    } label: {
                        HStack {
                            Text(speed.displayText)
                            if speed == store.playbackSpeed {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "speedometer")
                        .font(.body)
                    Text(store.playbackSpeed.displayText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .sonicGradientForeground(colors: colors)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .sonicGradientBackground(colors: colors, opacity: 0.12)
                .sonicGradientStroke(colors: colors, opacity: 0.2)
            }

            Spacer()

            // Queue button (wordless)
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showQueue.toggle()
                }
            } label: {
                Image(systemName: showQueue ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                    .font(.title3)
                    .sonicGradientForeground(colors: colors)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .sonicGradientBackground(colors: colors, opacity: showQueue ? 0.2 : 0.12)
                    .sonicGradientStroke(colors: colors, opacity: 0.2)
            }
        }
    }
}

struct VolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView()
        volumeView.showsVolumeSlider = true
        // Hide route button by removing it from subviews
        for subview in volumeView.subviews where subview is UIButton {
            subview.isHidden = true
        }
        return volumeView
    }
    
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Scrolling Text

struct ScrollingText: View {
    let text: String
    @State private var offset: CGFloat = 10
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Measure text width
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

                // Duplicate for seamless loop (only if text is longer than container)
                if textWidth > containerWidth {
                    Text(text)
                        .offset(x: offset + textWidth + 40) // 40pt spacing between loops
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
        // Wait 2 seconds before starting scroll
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let duration = max(0.1, Double(textWidth) / 30)
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                offset = -(textWidth + 40)
            }
        }
    }
}
