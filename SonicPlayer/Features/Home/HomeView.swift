import ComposableArchitecture
import SwiftUI

struct HomeHeaderView: View {
    let store: StoreOf<HomeFeature>

    var body: some View {
        if let track = store.lastPlayedTrack, track.duration > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text("Continue Listening")
                    .font(.title3)
                    .fontWeight(.semibold)

                continueListeningCard(track: track)
            }
        }
    }

    private func continueListeningCard(track: AudioFile) -> some View {
        HStack(spacing: 12) {
            // Row tap → present player
            Button {
                store.send(.playTrack(track))
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient.sonicGradient)
                            .frame(width: 48, height: 48)

                        Image(systemName: store.isPlaying ? "waveform" : "play.fill")
                            .font(store.isPlaying ? .title3 : .body)
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(track.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.sonicTextPrimary)
                            .lineLimit(1)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.sonicBorder)
                                    .frame(height: 4)

                                Capsule()
                                    .fill(Color.sonicPrimary)
                                    .frame(width: max(4, geo.size.width * store.playbackProgress), height: 4)
                            }
                        }
                        .frame(height: 4)

                        Text(track.durationFormatted)
                            .font(.caption)
                            .foregroundColor(.sonicTextSecondary)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Play/Pause button → just toggle, don't present player
            Button {
                store.send(.togglePlayPause)
            } label: {
                Image(systemName: store.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.sonicPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.sonicSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sonicBorder.opacity(0.5), lineWidth: 0.5)
        )
    }
}
