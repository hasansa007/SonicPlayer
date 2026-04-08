import ComposableArchitecture
import SwiftUI

struct RecordingView: View {
    @Bindable var store: StoreOf<RecordingFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sonicBackground.ignoresSafeArea()

                if store.isRecording {
                    recordingInterface
                } else if store.isSaveFlowPresented {
                    saveFlowInterface
                } else {
                    preRecordingInterface
                }
            }
            .navigationTitle(store.isRecording ? "Recording" : "New Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !store.isRecording {
                        Button {
                            store.send(.discardRecording)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.sonicTextSecondary)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isSaveFlowPresented {
                        Button("Save") {
                            store.send(.saveRecording)
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicPrimary)
                    }
                }
            }
        }
        .alert("Microphone Permission Required", isPresented: $store.showPermissionAlert.sending(\.setShowPermissionAlert)) {
            Button("Allow Microphone") {
                store.send(.requestPermissions)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sonic Player needs access to your microphone to record audio.")
        }
        .sheet(item: $store.scope(state: \.editRecording, action: \.editRecording)) { editStore in
            EditRecordingView(store: editStore)
        }
        .onAppear {
            store.send(.onAppear)
        }
    }

    // MARK: - Pre-Recording (Start Screen)

    private var preRecordingInterface: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundColor(.sonicTextMuted)

            Text("Tap to start recording")
                .font(.subheadline)
                .foregroundColor(.sonicTextSecondary)

            Button {
                store.send(.startRecordingTapped)
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.red.opacity(0.8), Color.red],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 80, height: 80)
                        .shadow(color: Color.red.opacity(0.3), radius: 16, x: 0, y: 8)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                }
            }

            Spacer()
        }
    }

    // MARK: - Recording Interface

    private var recordingInterface: some View {
        VStack(spacing: 40) {
            Spacer()

            Text(formatTime(store.recordingTime))
                .font(.system(size: 60, weight: .light, design: .rounded))
                .foregroundColor(.sonicTextPrimary)
                .monospacedDigit()

            RecordingWaveformView(peakLevel: store.peakLevel)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)

            // Stop button
            Button {
                store.send(.stopRecordingTapped)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 72, height: 72)
                        .shadow(color: Color.red.opacity(0.3), radius: 16, x: 0, y: 8)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                }
            }

            Spacer()
        }
    }

    // MARK: - Save Flow

    @State private var previewPlaying = false

    private var saveFlowInterface: some View {
        VStack(spacing: 24) {
            Spacer()

            // Waveform preview with play button
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.sonicBorder.opacity(0.2))
                    .frame(height: 80)
                    .overlay {
                        HStack(spacing: 2) {
                            ForEach(0..<30, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.sonicPrimary.opacity(0.4))
                                    .frame(width: 3, height: CGFloat.random(in: 8...40))
                            }
                        }
                    }

                // Play button overlay
                Button {
                    previewPlaying.toggle()
                } label: {
                    Image(systemName: previewPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                }
            }
            .padding(.horizontal, 24)

            // Name field
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.sonicTextSecondary)

                TextField("Recording name", text: Binding(
                    get: { store.saveFileName },
                    set: { store.send(.setSaveFileName($0)) }
                ))
                .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 24)

            // Play & Edit button
            Button {
                store.send(.saveAndEditRecording)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "scissors")
                        .font(.subheadline)
                    Text("Edit Recording")
                        .font(.body)
                        .fontWeight(.medium)
                }
                .foregroundColor(.sonicPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.sonicSurface, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
    }
}

// MARK: - Recording Waveform View

struct RecordingWaveformView: View {
    let peakLevel: Float
    @State private var bars: [CGFloat] = Array(repeating: 0.3, count: 50)

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<bars.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [Color.red.opacity(0.8), Color.red],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 3)
                    .frame(height: bars[index] * 100)
            }
        }
        .onChange(of: peakLevel) { _, newValue in
            updateBars(peak: newValue)
        }
    }

    private func updateBars(peak: Float) {
        let normalized = max(0, min(1, (peak + 50) / 50))
        let height = CGFloat(normalized)
        bars.removeFirst()
        bars.append(height)
    }
}
