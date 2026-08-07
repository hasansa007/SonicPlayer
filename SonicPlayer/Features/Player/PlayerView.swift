import SwiftUI
import MediaPlayer

struct PlayerView: View {
    let player: PlayerViewModel
    @State private var showQueue = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ZStack {
            // Background
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

            if player.currentTrack == nil {
                emptyStateView
            } else if verticalSizeClass == .compact {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            headerView

            EmptyStateView(
                icon: "music.note",
                title: "No Track Selected",
                message: "Select a file from the Library to start playing",
                iconStyle: AnyShapeStyle(LinearGradient.sonicGradient),
                iconSize: 80,
                spacing: 16
            )
        }
        .padding()
    }

    private var portraitLayout: some View {
        VStack(spacing: 20) {
            headerView

            VStack(spacing: 20) {
                // Artwork
                artworkView
                    .frame(height: showQueue ? 100 : nil)

                // Track info or queue
                if showQueue {
                    queueListView
                } else {
                    trackInfoView
                }
            }
            .frame(maxHeight: .infinity)

            // Controls
            fullPlayerControls
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    private var landscapeLayout: some View {
        HStack(spacing: 20) {
            // Left side: artwork or queue
            VStack(spacing: 8) {
                if showQueue {
                    queueListView
                } else {
                    artworkView
                    Text(player.currentTrack?.title ?? "")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.sonicTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 260)
            .clipped()

            // Right side: controls
            VStack(spacing: 8) {
                progressSliderWithSkipsView
                controlsView
                bottomControlsView
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    // MARK: - Artwork

    private var artworkSize: CGFloat {
        if showQueue { return 80 }
        if verticalSizeClass == .compact { return 120 }
        return 280
    }

    private var artworkView: some View {
        Group {
            if let artwork = player.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: showQueue ? 12 : 16))
            } else {
                RoundedRectangle(cornerRadius: showQueue ? 12 : 16)
                    .fill(LinearGradient.sonicGradient)
                    .frame(width: artworkSize, height: artworkSize)
                    .overlay {
                        if player.isPlaying && !showQueue && player.progress > 0 {
                            PlayerWaveformView(isPlaying: player.isPlaying)
                                .frame(width: 80, height: 40)
                                .foregroundColor(.white.opacity(0.8))
                        } else {
                            Image(systemName: "waveform")
                                .font(showQueue ? .title3 : .largeTitle)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
            }
        }
        .shadow(color: Color.sonicPrimary.opacity(0.2), radius: 16, x: 0, y: 8)
    }

    // MARK: - Track Info

    private var trackInfoView: some View {
        VStack(spacing: 8) {
            ScrollingText(text: player.currentTrack?.title ?? "Unknown Track")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.sonicTextPrimary)
                .frame(height: 28)
                .padding(.horizontal, 10)
        }
    }

    // MARK: - Queue

    private var queueListView: some View {
        ScrollView {
            if player.queue.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Text("No tracks in queue")
                        .font(.subheadline)
                        .foregroundColor(.sonicTextSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, track in
                        HStack(spacing: 12) {
                            if index == player.currentIndex {
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
                                    .fontWeight(index == player.currentIndex ? .semibold : .regular)
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
                            if index == player.currentIndex {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.sonicPrimary.opacity(0.1))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if index != player.currentIndex {
                                player.jumpToTrack(index)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Controls

    private var fullPlayerControls: some View {
        VStack(spacing: 20) {
            Spacer()
            progressSliderWithSkipsView
            controlsView
            VolumeView()
                .frame(height: 40)
                .padding(.horizontal)
            bottomControlsView
            Spacer()
        }
    }

    private var headerView: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.sonicTextSecondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
        }
    }

    private var progressSliderWithSkipsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    player.skipBackward()
                } label: {
                    Image(systemName: "gobackward.\(Int(player.skipDuration.rawValue))")
                        .font(.title3)
                        .foregroundColor(.sonicPrimary)
                        .frame(width: 44, height: 44)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.sonicBorder)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.sonicPrimary)
                            .frame(width: geometry.size.width * player.progress, height: 8)
                            .animation(.linear(duration: 0.1), value: player.progress)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let progress = min(max(0, value.location.x / geometry.size.width), 1)
                                let newTime = progress * player.duration
                                player.seek(to: newTime)
                            }
                    )
                }
                .frame(height: 8)

                Button {
                    player.skipForward()
                } label: {
                    Image(systemName: "goforward.\(Int(player.skipDuration.rawValue))")
                        .font(.title3)
                        .foregroundColor(.sonicPrimary)
                        .frame(width: 44, height: 44)
                }
            }

            HStack {
                Text(player.currentTimeFormatted ?? "0:00")
                    .font(.caption)
                    .foregroundColor(.sonicTextSecondary)
                    .monospacedDigit()

                Spacer()

                Text(player.durationFormatted ?? "0:00")
                    .font(.caption)
                    .foregroundColor(.sonicTextSecondary)
                    .monospacedDigit()
            }
        }
    }

    private var controlsView: some View {
        HStack(spacing: 40) {
            Button {
                player.previousTrack()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .foregroundColor(player.hasPreviousTrack ? .sonicPrimary : .sonicTextMuted)
                    .frame(width: 56, height: 56)
            }
            .disabled(!player.hasPreviousTrack && player.currentTime < 3)

            Button {
                player.playPauseTapped()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.sonicPrimary)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.sonicPrimary.opacity(0.3), radius: 8, x: 0, y: 4)

                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .offset(x: player.isPlaying ? 0 : 2)
                }
            }

            Button {
                player.nextTrack()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .foregroundColor(player.hasNextTrack ? .sonicPrimary : .sonicTextMuted)
                    .frame(width: 56, height: 56)
            }
            .disabled(!player.hasNextTrack)
        }
    }

    private var bottomControlsView: some View {
        HStack {
            // Speed control
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.sonicPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            // Repeat mode
            Button {
                player.toggleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode.icon)
                    .font(.title3)
                    .foregroundColor(player.repeatMode == .off ? .sonicTextMuted : .sonicPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.sonicPrimary.opacity(player.repeatMode == .off ? 0.05 : 0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            // Shuffle
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundColor(player.isShuffleEnabled ? .sonicPrimary : .sonicTextMuted)
                    .frame(width: 44, height: 44)
                    .background(Color.sonicPrimary.opacity(player.isShuffleEnabled ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 8))
            }

            // Queue toggle
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showQueue.toggle()
                }
            } label: {
                Image(systemName: showQueue ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                    .font(.title3)
                    .foregroundColor(.sonicPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.sonicPrimary.opacity(showQueue ? 0.15 : 0.1), in: RoundedRectangle(cornerRadius: 8))
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

struct ScrollingText: View {
    let text: String
    @State private var offset: CGFloat = 10
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

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
                        .offset(x: offset + textWidth + 40)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let duration = max(0.1, Double(textWidth) / 30)
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                offset = -(textWidth + 40)
            }
        }
    }
}

// MARK: - Player Waveform Animation

struct PlayerWaveformView: View {
    let isPlaying: Bool
    @State private var animating = false

    private let barCount = 5
    private let minHeight: CGFloat = 8

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .frame(width: 6, height: animating ? barHeight(index) : minHeight)
                    .animation(
                        isPlaying ?
                            .easeInOut(duration: Double.random(in: 0.3...0.6))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1) :
                            .easeOut(duration: 0.3),
                        value: animating
                    )
            }
        }
        .onAppear {
            if isPlaying { animating = true }
        }
        .onChange(of: isPlaying) { _, newValue in
            animating = newValue
        }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let heights: [CGFloat] = [28, 36, 20, 32, 24]
        return heights[index % heights.count]
    }
}
