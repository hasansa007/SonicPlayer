import ComposableArchitecture
import SwiftUI

struct EditRecordingView: View {
    @Bindable var store: StoreOf<EditRecordingFeature>
    @Environment(\.dismiss) var dismiss
    @State private var isRenaming = false
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                GeometryReader { proxy in
                    let isLandscape = proxy.size.width > proxy.size.height

                if isLandscape {
                    landscapeContent
                } else {
                    portraitContent
                }
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Button {
                        renameText = store.recording.title
                        isRenaming = true
                    } label: {
                        HStack(spacing: 8) {
                            Text(store.recording.title)
                                .font(.headline)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Image(systemName: "pencil")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if store.isTrimming {
                        Button {
                            store.send(.applyTrim)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.title3)
                                .foregroundColor(.white)
                        }
                        .disabled(store.isTrimming_InProgress)
                    }
                }
            }
        }
        .alert("Action Failed", isPresented: Binding(
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
        .alert("Rename Recording", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    store.send(.renameTapped(trimmed))
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            store.send(.onAppear)
        }
    }


    private var portraitContent: some View {
        VStack(spacing: 0) {
            Spacer()

            waveformView(height: 100)
                .padding(.horizontal, 20)

            Spacer()

            Text(formatTime(store.currentTime))
                .font(.system(size: 56, weight: .light, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .padding(.vertical, 40)

            playbackControls
                .padding(.bottom, 40)

            bottomButtons
                .padding(.bottom, 40)
        }
    }

    private var landscapeContent: some View {
        HStack(spacing: 32) {
            VStack(spacing: 20) {
                waveformView(height: 140)
                    .padding(.horizontal, 20)
                trimTimelineView
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 24) {
                Text(formatTime(store.currentTime))
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()

                playbackControls

                bottomButtons
            }
            .frame(width: 280)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func waveformView(height: CGFloat) -> some View {
        Group {
            if store.isTrimming {
                trimWaveformView(height: height)
            } else {
                playbackWaveformView(height: height)
            }
        }
    }

    private func playbackWaveformView(height: CGFloat) -> some View {
        VStack(spacing: 20) {
            // Simplified waveform (placeholder)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: height)

                // Playback position indicator
                GeometryReader { geometry in
                    let progress = store.recording.duration > 0 ? store.currentTime / store.recording.duration : 0
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: 2)
                        .offset(x: geometry.size.width * CGFloat(progress))
                }
            }
            .frame(height: height)

            trimTimelineView
            durationText
        }
    }

    private func trimWaveformView(height: CGFloat) -> some View {
        VStack(spacing: 20) {
            // Waveform with trim region
            ZStack {
                // Full waveform (grayed out)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: height)

                // Trim region overlay
                GeometryReader { geometry in
                    let totalWidth = geometry.size.width
                    let startX = CGFloat(store.trimStart / store.recording.duration) * totalWidth
                    let endX = CGFloat(store.trimEnd / store.recording.duration) * totalWidth
                    let trimWidth = endX - startX

                    // Highlighted trim region
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.yellow.opacity(0.6))
                        .frame(width: max(0, trimWidth), height: height)
                        .offset(x: startX)

                    // Left handle
                    TrimHandle(isLeft: true, height: height)
                        .offset(x: startX - 15)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newStart = (value.location.x / totalWidth) * store.recording.duration
                                    store.send(.trimStartChanged(max(0, min(newStart, store.trimEnd - 1))))
                                }
                        )

                    // Right handle
                    TrimHandle(isLeft: false, height: height)
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
            .frame(height: height)

            trimTimelineView
            durationText
        }
    }

    private var durationText: some View {
        Text("Duration: \(formatTime(store.trimEnd - store.trimStart))")
            .font(.subheadline)
            .foregroundColor(.gray)
            .opacity(store.isTrimming ? 1 : 0)
    }

    private var trimTimelineView: some View {
        HStack {
            Text(formatTime(store.isTrimming ? store.trimStart : 0))
                .font(.caption)
                .foregroundColor(store.isTrimming ? .white : .gray)

            Spacer()

            Text(formatTime(store.isTrimming ? store.trimEnd : store.recording.duration))
                .font(.caption)
                .foregroundColor(store.isTrimming ? .white : .gray)
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
                if store.isTrimming {
                    store.send(.cancelTrim)
                } else {
                    store.send(.trimTapped)
                }
            } label: {
                Text(store.isTrimming ? "Cancel Trim" : "Trim")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(width: 140, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(Color.yellow)
                    )
            }
            .opacity(store.isTrimming && store.isTrimming_InProgress ? 0.5 : 1)
            .disabled(store.isTrimming_InProgress)

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
    let height: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.yellow)
                .frame(width: 30, height: height)

            // Grip lines
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 2, height: max(10, height * 0.2))
                }
            }

            // Arrow indicator
            Image(systemName: isLeft ? "chevron.backward" : "chevron.forward")
                .font(.caption)
                .foregroundColor(.black.opacity(0.5))
        }
    }
}
