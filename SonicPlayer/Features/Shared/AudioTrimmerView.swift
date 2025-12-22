import ComposableArchitecture
import SwiftUI

struct AudioTrimmerView: View {
    let store: StoreOf<AudioTrimmerFeature>

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sonicBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // File info section
                    fileInfoSection

                    Spacer()

                    // Waveform section
                    waveformSection

                    Spacer()

                    // Timeline and trim controls
                    timelineSection

                    // Playback controls
                    playbackControls
                        .padding(.top, 24)

                    // Bottom action buttons
                    bottomActions
                        .padding(.top, 32)
                        .padding(.bottom, 40)
                }
                .padding(.horizontal)

                // Loading overlay
                if store.isTrimming {
                    loadingOverlay
                }
            }
            .navigationTitle("Trim Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        store.send(.cancelTapped)
                    }
                    .foregroundColor(.sonicTextPrimary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        store.send(.applyTapped)
                    }
                    .foregroundColor(.sonicPurple)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            store.send(.onAppear)
        }
    }

    private var fileInfoSection: some View {
        VStack(spacing: 8) {
            Text(store.audioFile.title)
                .font(.headline)
                .foregroundColor(.sonicTextPrimary)

            Text(store.timeRangeText)
                .font(.subheadline)
                .foregroundColor(.sonicTextSecondary)
        }
        .padding(.top, 16)
    }

    private var waveformSection: some View {
        ZStack {
            // Waveform placeholder (simplified representation)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 200)
                .overlay(
                    // Simple bars to represent waveform
                    HStack(spacing: 2) {
                        ForEach(0..<60, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(LinearGradient.sonicGradientPurple)
                                .frame(height: waveformHeight(for: index))
                        }
                    }
                    .padding(.horizontal, 8)
                )

            // Playhead indicator
            GeometryReader { geometry in
                let playheadX = (store.currentTime / store.duration) * geometry.size.width
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 2)
                    .offset(x: playheadX)
            }
        }
        .frame(height: 200)
    }

    private var timelineSection: some View {
        VStack(spacing: 12) {
            // Trim handles timeline
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 40)

                // Trim range
                GeometryReader { geometry in
                    let startX = (store.trimStart / store.duration) * geometry.size.width
                    let endX = (store.trimEnd / store.duration) * geometry.size.width
                    let width = endX - startX

                    ZStack {
                        // Selected range
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.sonicPurple.opacity(0.3))
                            .frame(width: width, height: 40)
                            .offset(x: startX)

                        // Start handle
                        trimHandle(isStart: true)
                            .offset(x: startX)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let newTime = (value.location.x / geometry.size.width) * store.duration
                                        store.send(.setTrimStart(newTime))
                                    }
                            )

                        // End handle
                        trimHandle(isStart: false)
                            .offset(x: endX - 8)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let newTime = ((startX + value.location.x) / geometry.size.width) * store.duration
                                        store.send(.setTrimEnd(newTime))
                                    }
                            )
                    }
                }
                .frame(height: 40)
            }

            // Duration display
            HStack {
                Text(formatTime(store.trimStart))
                    .font(.caption)
                    .foregroundColor(.sonicTextSecondary)

                Spacer()

                Text(formatTime(store.trimDuration))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.sonicPurple)

                Spacer()

                Text(formatTime(store.trimEnd))
                    .font(.caption)
                    .foregroundColor(.sonicTextSecondary)
            }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 40) {
            // Skip backward 15s
            Button {
                store.send(.skipBackward)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title2)
                    .foregroundColor(.sonicTextPrimary)
            }

            // Play/Pause
            Button {
                store.send(.playPauseTapped)
            } label: {
                Image(systemName: store.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.sonicPurple)
            }

            // Skip forward 15s
            Button {
                store.send(.skipForward)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.title2)
                    .foregroundColor(.sonicTextPrimary)
            }
        }
    }

    private var bottomActions: some View {
        HStack(spacing: 16) {
            // Trim button
            Button {
                store.send(.trimTapped)
            } label: {
                HStack {
                    Image(systemName: "scissors")
                    Text("Trim")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.sonicPurple.opacity(0.2))
                .foregroundColor(.sonicPurple)
                .cornerRadius(12)
            }

            // Delete button
            Button {
                store.send(.deleteTapped)
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.2))
                .foregroundColor(.red)
                .cornerRadius(12)
            }
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.sonicPurple)

                Text("Trimming audio...")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(Color.sonicBackground)
            .cornerRadius(16)
        }
    }

    private func trimHandle(isStart: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.yellow)
            .frame(width: 8, height: 40)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.yellow.opacity(0.5), lineWidth: 2)
            )
    }

    private func waveformHeight(for index: Int) -> CGFloat {
        // Generate pseudo-random waveform heights
        let seed = sin(Double(index) * 0.5) * cos(Double(index) * 0.3)
        let normalized = (seed + 1) / 2
        return 40 + (normalized * 120)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
