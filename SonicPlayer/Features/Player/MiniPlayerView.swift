import SwiftUI

struct MiniPlayerView: View {
    let player: PlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.sonicPrimary)
                    .frame(width: geo.size.width * player.progress, height: 2)
                    .animation(.linear(duration: 0.3), value: player.progress)
            }
            .frame(height: 2)

            HStack(spacing: 12) {
                // Tap area: artwork + title → expand player
                Button {
                    player.setExpanded(true)
                } label: {
                    HStack(spacing: 10) {
                        // Thumbnail
                        ZStack {
                            if let artwork = player.artwork {
                                Image(uiImage: artwork)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient.sonicGradient)
                                    .frame(width: 40, height: 40)
                            }

                            if player.isPlaying {
                                MiniWaveformView(isPlaying: player.isPlaying)
                                    .frame(width: 24, height: 16)
                                    .foregroundColor(.white)
                            } else if player.artwork == nil {
                                Image(systemName: "music.note")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }

                        // Title
                        Text(player.currentTrack?.title ?? "Not Playing")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Previous
                Button {
                    player.previousTrack()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.body)
                        .foregroundColor(.sonicPrimary)
                }

                // Play/Pause
                Button {
                    player.playPauseTapped()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundColor(.sonicPrimary)
                        .frame(width: 44, height: 44)
                }

                // Next
                Button {
                    player.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                        .foregroundColor(.sonicPrimary)
                }

                // Close
                Button {
                    player.clearSession()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicTextMuted)
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
    }
}

// MARK: - Mini Waveform

struct MiniWaveformView: View {
    let isPlaying: Bool
    @State private var phases: [CGFloat] = [0, 0, 0]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .frame(width: 3, height: 6 + phases[index])
                    .animation(
                        isPlaying ?
                            .easeInOut(duration: 0.5).repeatForever().delay(Double(index) * 0.15) :
                            .easeOut(duration: 0.2),
                        value: phases[index]
                    )
            }
        }
        .onAppear {
            if isPlaying { startAnimation() }
        }
        .onChange(of: isPlaying) { _, newValue in
            if newValue { startAnimation() } else { stopAnimation() }
        }
    }

    func startAnimation() {
        for i in 0..<3 { phases[i] = CGFloat.random(in: 4...10) }
    }

    func stopAnimation() {
        for i in 0..<3 { phases[i] = 0 }
    }
}
