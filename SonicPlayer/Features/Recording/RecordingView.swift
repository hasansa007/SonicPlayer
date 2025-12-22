import ComposableArchitecture
import SwiftUI

struct RecordingView: View {
    @Bindable var store: StoreOf<RecordingFeature>

    var body: some View {
        ZStack {
            Color.sonicBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.top, 20)

                if store.isRecording {
                    // Recording interface
                    recordingInterface
                } else {
                    // Recordings list
                    recordingsList
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

    private var headerView: some View {
        VStack(spacing: 8) {
            Text("Recordings")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.sonicTextPrimary)

            if !store.isRecording && !store.recordings.isEmpty {
                Text("\(store.recordings.count) recording\(store.recordings.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundColor(.sonicTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var recordingInterface: some View {
        VStack(spacing: 40) {
            Spacer()

            // Recording time
            Text(formatTime(store.recordingTime))
                .font(.system(size: 56, weight: .light, design: .rounded))
                .foregroundColor(.sonicTextPrimary)
                .monospacedDigit()

            // Waveform visualization
            RecordingWaveformView(peakLevel: store.peakLevel)
                .frame(height: 100)
                .padding(.horizontal, 40)

            Spacer()

            // Stop button
            Button {
                store.send(.stopRecordingTapped)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 80, height: 80)
                        .shadow(color: Color.red.opacity(0.4), radius: 20, x: 0, y: 10)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.bottom, 60)
        }
    }

    private var recordingsList: some View {
        VStack(spacing: 0) {
            if store.isLoadingRecordings {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.sonicPrimary)
                    .frame(maxHeight: .infinity)
            } else if store.recordings.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.recordings, id: \.id) { recording in
                            RecordingRow(recording: recording) {
                                store.send(.recordingTapped(recording))
                            } onDelete: {
                                store.send(.deleteRecording(recording))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                .frame(maxHeight: .infinity)
            }

            // Floating record button
            if !store.isRecording {
                VStack {
                    recordButton
                        .padding(.vertical, 40)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.circle")
                .font(.system(size: 80))
                .foregroundStyle(LinearGradient.sonicGradient)

            VStack(spacing: 8) {
                Text("No Recordings Yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.sonicTextPrimary)

                Text("Tap the button below to start recording")
                    .font(.subheadline)
                    .foregroundColor(.sonicTextSecondary)
            }

            Spacer()
            Spacer()
        }
    }

    private var recordButton: some View {
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
                    .shadow(color: Color.red.opacity(0.4), radius: 20, x: 0, y: 10)

                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
            }
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

// MARK: - Recording Row

struct RecordingRow: View {
    let recording: AudioFile
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient.sonicGradient.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(LinearGradient.sonicGradient)
                }

                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(recording.title)
                        .font(.headline)
                        .foregroundColor(.sonicTextPrimary)
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        Label(recording.durationFormatted, systemImage: "clock")
                        Label(formatDate(recording.creationDate), systemImage: "calendar")
                    }
                    .font(.caption)
                    .foregroundColor(.sonicTextSecondary)
                }

                Spacer()

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.title3)
                        .foregroundColor(.red)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
        // Convert dB to normalized value (0-1)
        let normalized = max(0, min(1, (peak + 50) / 50))
        let height = CGFloat(normalized)

        // Shift bars left and add new value
        bars.removeFirst()
        bars.append(height)
    }
}
