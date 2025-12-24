import ComposableArchitecture
import SwiftUI

struct RecordingView: View {
    @Bindable var store: StoreOf<RecordingFeature>
    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let isLandscape = proxy.size.width > proxy.size.height

                ZStack {
                    Color.sonicBackground.ignoresSafeArea()

                    if store.isRecording {
                        recordingInterface(isLandscape: isLandscape)
                    } else {
                        recordingsList(isLandscape: isLandscape)
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
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.url])
            }
            .onAppear {
                store.send(.onAppear)
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.large)
            .background(Color.sonicBackground.ignoresSafeArea())
        }
    }

    private func recordingInterface(isLandscape: Bool) -> some View {
        Group {
            if isLandscape {
                ZStack {
                    HStack(spacing: 40) {
                        VStack(spacing: 24) {
                        Text(formatTime(store.recordingTime))
                            .font(.system(size: 56, weight: .light, design: .rounded))
                            .foregroundColor(.sonicTextPrimary)
                            .monospacedDigit()

                        RecordingWaveformView(peakLevel: store.peakLevel)
                            .frame(height: 140)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 40)

                    HStack {
                        Spacer()
                        stopButton
                    }
                    .padding(.trailing, 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
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

                        Spacer()
                    }

                    portraitActionButton(stopButton)
                }
            }
        }
    }

    private func recordingsList(isLandscape: Bool) -> some View {
        ZStack {
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
                        if isLandscape {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                                ForEach(store.recordings, id: \.id) { recording in
                                    RecordingItemRowView(recording: recording) {
                                        store.send(.recordingTapped(recording))
                                    } onDelete: {
                                        store.send(.deleteRecording(recording))
                                    }
                                    .contextMenu {
                                        Button {
                                            store.send(.recordingTapped(recording))
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        Button {
                                            shareItem = ShareItem(url: recording.url)
                                        } label: {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                        Button(role: .destructive) {
                                            store.send(.deleteRecording(recording))
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(store.recordings, id: \.id) { recording in
                                    RecordingItemRowView(recording: recording) {
                                        store.send(.recordingTapped(recording))
                                    } onDelete: {
                                        store.send(.deleteRecording(recording))
                                    }
                                    .contextMenu {
                                        Button {
                                            store.send(.recordingTapped(recording))
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        Button {
                                            shareItem = ShareItem(url: recording.url)
                                        } label: {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                        Button(role: .destructive) {
                                            store.send(.deleteRecording(recording))
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }

            }

            if !store.isRecording && isLandscape {
                HStack {
                    Spacer()
                    recordButton
                }
                .padding(.trailing, 28)
            }

            if !store.isRecording && !isLandscape {
                portraitActionButton(recordButton)
            }
        }
    }

    private func portraitActionButton(_ button: some View) -> some View {
        VStack {
            Spacer()
            button
                .padding(.vertical, 40)
        }
    }

    private var stopButton: some View {
        Button {
            store.send(.stopRecordingTapped)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 80, height: 80)
                    .shadow(color: Color.red.opacity(0.4), radius: 20, x: 0, y: 10)
                    .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
            }
        }
    }

    private var emptyStateView: some View {
        EmptyStateView(
            icon: "waveform.circle",
            title: "No Recordings Yet",
            message: "Tap the button below to start recording",
            iconStyle: AnyShapeStyle(LinearGradient.sonicGradient),
            iconSize: 80,
            spacing: 24
        )
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
                    .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)

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

struct RecordingItemRowView: View {
    let recording: AudioFile
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        FileItemRow(
            title: recording.title,
            subtitle: "\(recording.durationFormatted) • \(formatDate(recording.creationDate))",
            artwork: nil,
            colors: Color.sonicTealColors,
            fallbackSystemImage: "waveform", showsChevron: true,
            onTap: onTap
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
