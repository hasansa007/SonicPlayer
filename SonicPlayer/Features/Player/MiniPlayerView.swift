import ComposableArchitecture
import SwiftUI

struct MiniPlayerView: View {
    let store: StoreOf<PlayerFeature>

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.sonicPrimary)
                    .frame(width: geo.size.width * store.progress, height: 2)
                    .animation(.linear(duration: 0.3), value: store.progress)
            }
            .frame(height: 2)

            HStack(spacing: 12) {
                // Tap area: artwork + title → expand player
                Button {
                    store.send(.setExpanded(true))
                } label: {
                    HStack(spacing: 10) {
                        // Thumbnail
                        ZStack {
                            if let artwork = store.artwork {
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

                            if store.isPlaying {
                                MiniWaveformView(isPlaying: store.isPlaying)
                                    .frame(width: 24, height: 16)
                                    .foregroundColor(.white)
                            } else if store.artwork == nil {
                                Image(systemName: "music.note")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }

                        // Title
                        Text(store.currentTrack?.title ?? "Not Playing")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Play/Pause
                Button {
                    store.send(.playPauseButtonTapped)
                } label: {
                    Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundColor(.sonicPrimary)
                        .frame(width: 44, height: 44)
                }

                // Skip Forward
                Button {
                    store.send(.skipForward)
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .foregroundColor(.sonicPrimary)
                }

                // Close
                Button {
                    store.send(.clearSession)
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
