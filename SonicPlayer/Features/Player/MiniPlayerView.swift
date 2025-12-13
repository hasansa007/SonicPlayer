import ComposableArchitecture
import SwiftUI

struct MiniPlayerView: View {
    let store: StoreOf<PlayerFeature>

    var body: some View {
        HStack(spacing: 12) {
            // Album art thumbnail with waveform
            ZStack {
                if let artwork = store.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.sonicPrimaryLight.opacity(0.15))
                        }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient.sonic(
                                colors: Color.sonicTealColors
                            )
                        )
                        .frame(width: 40, height: 40)
                }

                if store.isPlaying {
                    MiniWaveformView(isPlaying: store.isPlaying)
                        .frame(width: 24, height: 16)
                        .foregroundColor(.white)
                } else if store.currentTrack == nil || store.artwork == nil {
                     // Only show note icon if no artwork
                    Image(systemName: "music.note")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            .shadow(radius: 2)

            // Track Title (scrolling) - constrained to available space
            ScrollingText(text: store.currentTrack?.title ?? "Not Playing")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 20)
                .clipped()

            // Play/Pause Button
            Button {
                store.send(.playPauseButtonTapped)
            } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .sonicGradientForeground(colors: store.artwork != nil ? store.colors : Color.sonicTealColors)
            }

            // Skip Button
            Button {
                store.send(.skipForward)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .sonicGradientForeground(colors: store.artwork != nil ? store.colors : Color.sonicTealColors)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient.sonic(
                                colors: (store.artwork != nil ? store.colors : Color.sonicTealColors).map { $0.opacity(0.15) }
                            )
                        )
                }
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.25), lineWidth: 1.5)
                }
        }
        .shadow(color: (store.colors.first ?? Color.sonicPrimary).opacity(0.15), radius: 20, x: 0, y: 10)
        .shadow(color: (store.colors.last ?? Color.sonicPrimary).opacity(0.15), radius: 15, x: 0, y: 5)
        .padding(.horizontal, 24)
        .onTapGesture {
            store.send(.setExpanded(true))
        }
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
        for i in 0..<3 {
            phases[i] = CGFloat.random(in: 4...10)
        }
    }

    func stopAnimation() {
        for i in 0..<3 {
            phases[i] = 0
        }
    }
}
