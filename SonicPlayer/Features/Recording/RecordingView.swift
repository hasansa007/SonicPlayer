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
                    saveEditInterface
                } else {
                    preRecordingInterface
                }
            }
            .navigationTitle(store.isRecording ? "Recording" : (store.isSaveFlowPresented ? "Edit Recording" : "New Recording"))
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
                        if let inlineEdit = store.inlineEdit, inlineEdit.isTrimming {
                            HStack(spacing: 12) {
                                Button {
                                    store.send(.inlineEdit(.applyTrim))
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "scissors")
                                            .font(.caption)
                                        Text("Trim")
                                            .font(.subheadline).fontWeight(.semibold)
                                    }
                                    .foregroundColor(.sonicPrimary)
                                }

                                Button {
                                    store.send(.inlineEdit(.cancelTrim))
                                } label: {
                                    Text("Cancel")
                                        .font(.subheadline)
                                        .foregroundColor(.sonicTextSecondary)
                                }

                                Button {
                                    store.send(.inlineEdit(.deleteRangeTapped))
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                        Text("Delete")
                                            .font(.subheadline)
                                    }
                                    .foregroundColor(.red)
                                }
                            }
                        } else {
                            Button("Save") {
                                store.send(.saveRecording)
                            }
                            .fontWeight(.semibold)
                            .foregroundColor(.sonicPrimary)
                        }
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
        .alert("Action Failed", isPresented: Binding(
            get: { store.inlineEdit?.trimError != nil },
            set: { if !$0 { store.send(.inlineEdit(.cancelTrim)) } }
        )) {
            Button("OK", role: .cancel) { store.send(.inlineEdit(.cancelTrim)) }
        } message: {
            if let error = store.inlineEdit?.trimError { Text(error) }
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

            Text("Ready to record?")
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
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.red.opacity(0.5), radius: 20, x: 0, y: 8)
                        .shadow(color: Color.red.opacity(0.3), radius: 40, x: 0, y: 12)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                }
            }

            Spacer()
        }
    }

    // MARK: - Recording Interface

    private var recordingInterface: some View {
        ScrollView {
            VStack(spacing: 40) {
                Spacer().frame(height: 20)

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
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Combined Save + Edit Interface

    private var saveEditInterface: some View {
        ScrollView {
            VStack(spacing: 0) {
            if let inlineEdit = store.inlineEdit {
                // Waveform area
                inlineWaveformArea(inlineEdit)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                // Time display
                Text(formatEditTime(inlineEdit.currentTime))
                    .font(.system(size: 36, weight: .light, design: .rounded))
                    .foregroundColor(.sonicTextPrimary)
                    .monospacedDigit()
                    .padding(.top, 16)

                // Playback controls
                inlinePlaybackControls
                    .padding(.top, 12)

                Spacer()

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

                // Trim button (if not already in trim mode)
                if !inlineEdit.isTrimming {
                    Button {
                        store.send(.inlineEdit(.trimTapped))
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "scissors")
                                .font(.subheadline)
                            Text("Select & Trim")
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.sonicPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.sonicPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }

                Spacer().frame(height: 24)
            } else {
                // Loading state while metadata loads
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .tint(.sonicPrimary)
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundColor(.sonicTextSecondary)
                    Spacer()
                }
            }

            }
        }
        .overlay {
            // Trimming overlay
            if store.inlineEdit?.isTrimming_InProgress == true {
                ZStack {
                    Color.black.opacity(0.7).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView().scaleEffect(1.5).tint(.sonicPrimary)
                        Text("Trimming audio...").font(.headline).foregroundColor(.sonicTextPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Inline Waveform

    private func inlineWaveformArea(_ editState: EditRecordingFeature.State) -> some View {
        VStack(spacing: 8) {
            ZStack {
                if editState.isTrimming {
                    inlineTrimWaveform(editState)
                } else {
                    inlinePlaybackWaveform(editState)
                }
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Timeline
            HStack {
                Text(formatEditTime(editState.isTrimming ? editState.trimStart : 0))
                    .font(.caption2).monospacedDigit()
                    .foregroundColor(.sonicTextSecondary)
                Spacer()
                if editState.isTrimming {
                    Text("Duration: \(formatEditTime(editState.trimEnd - editState.trimStart))")
                        .font(.caption2)
                        .foregroundColor(.sonicPrimary)
                }
                Spacer()
                Text(formatEditTime(editState.isTrimming ? editState.trimEnd : editState.recording.duration))
                    .font(.caption2).monospacedDigit()
                    .foregroundColor(.sonicTextSecondary)
            }
        }
    }

    private func inlinePlaybackWaveform(_ editState: EditRecordingFeature.State) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.sonicPrimary.opacity(0.06))

            HStack(spacing: 2) {
                ForEach(0..<40, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.sonicPrimary.opacity(0.35))
                        .frame(width: 3, height: CGFloat.random(in: 10...60))
                }
            }

            GeometryReader { geo in
                let progress = editState.recording.duration > 0 ? editState.currentTime / editState.recording.duration : 0
                Rectangle()
                    .fill(Color.sonicPrimary)
                    .frame(width: 2)
                    .offset(x: geo.size.width * CGFloat(progress))
            }

            GeometryReader { geo in
                Color.clear.contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let progress = min(max(0, value.location.x / geo.size.width), 1)
                                let time = progress * editState.recording.duration
                                store.send(.inlineEdit(.playbackTimeUpdated(time)))
                            }
                    )
            }
        }
    }

    private func inlineTrimWaveform(_ editState: EditRecordingFeature.State) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.sonicPrimary.opacity(0.06))

            GeometryReader { geo in
                let totalWidth = geo.size.width
                let startX = CGFloat(editState.trimStart / editState.recording.duration) * totalWidth
                let endX = CGFloat(editState.trimEnd / editState.recording.duration) * totalWidth

                Rectangle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: startX)

                Rectangle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: totalWidth - endX)
                    .offset(x: endX)

                Rectangle()
                    .fill(Color.sonicPrimary.opacity(0.15))
                    .frame(width: max(0, endX - startX))
                    .offset(x: startX)

                HStack(spacing: 2) {
                    ForEach(0..<40, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.sonicPrimary.opacity(0.35))
                            .frame(width: 3, height: CGFloat.random(in: 10...60))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Left handle
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.sonicPrimary)
                    .frame(width: 4, height: 120)
                    .offset(x: startX - 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newStart = (value.location.x / totalWidth) * editState.recording.duration
                                store.send(.inlineEdit(.trimStartChanged(max(0, min(newStart, editState.trimEnd - 1)))))
                            }
                    )

                // Right handle
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.sonicPrimary)
                    .frame(width: 4, height: 120)
                    .offset(x: endX - 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newEnd = (value.location.x / totalWidth) * editState.recording.duration
                                store.send(.inlineEdit(.trimEndChanged(max(editState.trimStart + 1, min(newEnd, editState.recording.duration)))))
                            }
                    )

                // Playback position
                Rectangle()
                    .fill(Color.sonicTextPrimary)
                    .frame(width: 2)
                    .offset(x: CGFloat(editState.currentTime / editState.recording.duration) * totalWidth)
            }
        }
    }

    // MARK: - Inline Playback Controls

    private var inlinePlaybackControls: some View {
        HStack(spacing: 48) {
            Button { store.send(.inlineEdit(.skipBackward)) } label: {
                Image(systemName: "gobackward.15")
                    .font(.title2)
                    .foregroundColor(.sonicTextSecondary)
                    .frame(width: 52, height: 52)
            }

            Button { store.send(.inlineEdit(.playPauseTapped)) } label: {
                ZStack {
                    Circle()
                        .fill(Color.sonicPrimary)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.sonicPrimary.opacity(0.3), radius: 8, x: 0, y: 4)

                    Image(systemName: store.inlineEdit?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .offset(x: store.inlineEdit?.isPlaying == true ? 0 : 2)
                }
            }

            Button { store.send(.inlineEdit(.skipForward)) } label: {
                Image(systemName: "goforward.15")
                    .font(.title2)
                    .foregroundColor(.sonicTextSecondary)
                    .frame(width: 52, height: 52)
            }
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

    private func formatEditTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
