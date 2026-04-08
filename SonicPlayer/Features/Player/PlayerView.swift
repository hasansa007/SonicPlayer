import ComposableArchitecture
import SwiftUI
import MediaPlayer

struct PlayerView: View {
    @Bindable var store: StoreOf<PlayerFeature>
    @State private var showQueue = false

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

            if store.currentTrack == nil {
                emptyStateView
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
        .padding(.bottom, 16)
    }

    // MARK: - Artwork (simplified — no waveform overlay)

    private var artworkView: some View {
        Group {
            if let artwork = store.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: showQueue ? 80 : 280, height: showQueue ? 80 : 280)
                    .clipShape(RoundedRectangle(cornerRadius: showQueue ? 12 : 16))
            } else {
                RoundedRectangle(cornerRadius: showQueue ? 12 : 16)
                    .fill(LinearGradient.sonicGradient)
                    .frame(width: showQueue ? 80 : 280, height: showQueue ? 80 : 280)
                    .overlay {
                        Image(systemName: "waveform")
                            .font(showQueue ? .title3 : .largeTitle)
                            .foregroundColor(.white.opacity(0.7))
                    }
            }
        }
        .shadow(color: Color.sonicPrimary.opacity(0.2), radius: 16, x: 0, y: 8)
    }

    // MARK: - Track Info

    private var trackInfoView: some View {
        VStack(spacing: 8) {
            ScrollingText(text: store.currentTrack?.title ?? "Unknown Track")
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
            if store.queue.isEmpty {
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
                                    .fill(Color.sonicPrimary.opacity(0.1))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
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
                    store.send(.skipBackward)
                } label: {
                    Image(systemName: "gobackward.\(Int(store.skipDuration.rawValue))")
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
                            .frame(width: geometry.size.width * store.progress, height: 8)
                            .animation(.linear(duration: 0.1), value: store.progress)
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

                Button {
                    store.send(.skipForward)
                } label: {
                    Image(systemName: "goforward.\(Int(store.skipDuration.rawValue))")
                        .font(.title3)
                        .foregroundColor(.sonicPrimary)
                        .frame(width: 44, height: 44)
                }
            }

            HStack {
                Text(store.currentTimeFormatted ?? "0:00")
                    .font(.caption)
                    .foregroundColor(.sonicTextSecondary)
                    .monospacedDigit()

                Spacer()

                Text(store.durationFormatted ?? "0:00")
                    .font(.caption)
                    .foregroundColor(.sonicTextSecondary)
                    .monospacedDigit()
            }
        }
    }

    private var controlsView: some View {
        HStack(spacing: 40) {
            Button {
                store.send(.previousTrack)
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .foregroundColor(store.hasPreviousTrack ? .sonicPrimary : .sonicTextMuted)
                    .frame(width: 56, height: 56)
            }
            .disabled(!store.hasPreviousTrack && store.currentTime < 3)

            Button {
                store.send(.playPauseButtonTapped)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.sonicPrimary)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.sonicPrimary.opacity(0.3), radius: 8, x: 0, y: 4)

                    Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .offset(x: store.isPlaying ? 0 : 2)
                }
            }

            Button {
                store.send(.nextTrack)
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .foregroundColor(store.hasNextTrack ? .sonicPrimary : .sonicTextMuted)
                    .frame(width: 56, height: 56)
            }
            .disabled(!store.hasNextTrack)
        }
    }

    private var bottomControlsView: some View {
        HStack(spacing: 16) {
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
                Text(store.playbackSpeed.displayText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(.sonicPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.sonicPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

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
