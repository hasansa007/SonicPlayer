import ComposableArchitecture
import SwiftUI

struct EditRecordingView: View {
    @Bindable var store: StoreOf<EditRecordingFeature>
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                topBar

                Spacer()

                // Waveform with trim handles
                if store.isTrimming {
                    trimWaveformView
                        .padding(.horizontal, 20)
                } else {
                    playbackWaveformView
                        .padding(.horizontal, 20)
                }

                Spacer()

                // Current time
                Text(formatTime(store.currentTime))
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .padding(.vertical, 40)

                // Playback controls
                playbackControls
                    .padding(.bottom, 40)

                // Bottom buttons
                bottomButtons
                    .padding(.bottom, 40)
            }

            // Trimming overlay
            if store.isTrimming_InProgress {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)

                    Text("Trimming audio...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
        .navigationBarHidden(true)
        .alert("Trim Failed", isPresented: Binding(
            get: { store.trimError != nil },
            set: { if !$0 { store.send(.cancelTrim) } }
        )) {
            Button("OK", role: .cancel) {
                store.send(.cancelTrim)
            }
        } message: {
            if let error = store.trimError {
                Text(error)
            }
        }
        .onAppear {
            store.send(.onAppear)
        }
        .onDisappear {
            store.send(.onDisappear)
        }
    }

    private var topBar: some View {
        HStack {
            if store.isTrimming {
                Button("Cancel") {
                    store.send(.cancelTrim)
                }
                .font(.headline)
                .foregroundColor(.white)

                Spacer()

                Text("Trim")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button("Apply") {
                    store.send(.applyTrim)
                }
                .font(.headline)
                .foregroundColor(.white)
                .disabled(store.isTrimming_InProgress)
            } else {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundColor(.white)
                }

                Spacer()

                Text(store.recording.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                Color.clear.frame(width: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var playbackWaveformView: some View {
        VStack(spacing: 20) {
            // Simplified waveform (placeholder)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 100)

                // Playback position indicator
                GeometryReader { geometry in
                    let progress = store.recording.duration > 0 ? store.currentTime / store.recording.duration : 0
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: 2)
                        .offset(x: geometry.size.width * CGFloat(progress))
                }
            }
            .frame(height: 100)

            // Timeline
            HStack {
                Text(formatTime(0))
                    .font(.caption)
                    .foregroundColor(.gray)

                Spacer()

                Text(formatTime(store.recording.duration))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }

    private var trimWaveformView: some View {
        VStack(spacing: 20) {
            // Waveform with trim region
            ZStack {
                // Full waveform (grayed out)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 100)

                // Trim region overlay
                GeometryReader { geometry in
                    let totalWidth = geometry.size.width
                    let startX = CGFloat(store.trimStart / store.recording.duration) * totalWidth
                    let endX = CGFloat(store.trimEnd / store.recording.duration) * totalWidth
                    let trimWidth = endX - startX

                    // Highlighted trim region
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.yellow.opacity(0.6))
                        .frame(width: max(0, trimWidth), height: 100)
                        .offset(x: startX)

                    // Left handle
                    TrimHandle(isLeft: true)
                        .offset(x: startX - 15)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newStart = (value.location.x / totalWidth) * store.recording.duration
                                    store.send(.trimStartChanged(max(0, min(newStart, store.trimEnd - 1))))
                                }
                        )

                    // Right handle
                    TrimHandle(isLeft: false)
                        .offset(x: endX - 15)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newEnd = (value.location.x / totalWidth) * store.recording.duration
                                    store.send(.trimEndChanged(max(store.trimStart + 1, min(newEnd, store.recording.duration))))
                                }
                        )

                    // Playback position
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: 2)
                        .offset(x: CGFloat(store.currentTime / store.recording.duration) * totalWidth)
                }
            }
            .frame(height: 100)

            // Timeline
            HStack {
                Text(formatTime(store.trimStart))
                    .font(.caption)
                    .foregroundColor(.white)

                Spacer()

                Text(formatTime(store.trimEnd))
                    .font(.caption)
                    .foregroundColor(.white)
            }

            // Duration display
            Text("Duration: \(formatTime(store.trimEnd - store.trimStart))")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 60) {
            // Skip backward
            Button {
                store.send(.skipBackward)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 60, height: 60)

                    Image(systemName: "gobackward.15")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }

            // Play/Pause
            Button {
                store.send(.playPauseTapped)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 80, height: 80)
                        .shadow(color: Color.white.opacity(0.3), radius: 10, x: 0, y: 5)

                    Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundColor(.black)
                        .offset(x: store.isPlaying ? 0 : 3)
                }
            }

            // Skip forward
            Button {
                store.send(.skipForward)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 60, height: 60)

                    Image(systemName: "goforward.15")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
        }
    }

    private var bottomButtons: some View {
        HStack(spacing: 40) {
            // Trim button
            Button {
                store.send(.trimTapped)
            } label: {
                Text("Trim")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(width: 140, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(Color.yellow)
                    )
            }
            .opacity(store.isTrimming ? 0.5 : 1)
            .disabled(store.isTrimming)

            // Delete button
            Button {
                store.send(.deleteRangeTapped)
            } label: {
                Text("Delete")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(width: 140, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(Color.yellow)
                    )
            }
            .opacity(store.isTrimming ? 1 : 0.5)
            .disabled(!store.isTrimming || store.isTrimming_InProgress)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
        }
    }
}

// MARK: - Trim Handle

struct TrimHandle: View {
    let isLeft: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.yellow)
                .frame(width: 30, height: 100)

            // Grip lines
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 2, height: 20)
                }
            }

            // Arrow indicator
            Image(systemName: isLeft ? "chevron.left" : "chevron.right")
                .font(.caption)
                .foregroundColor(.black.opacity(0.5))
        }
    }
}
