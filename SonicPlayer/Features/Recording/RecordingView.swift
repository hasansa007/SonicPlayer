import SwiftUI

struct RecordingView: View {

    /// The inline editor UI here is hand-built rather than reusing `EditRecordingView` — that was
    /// true before #17 and is preserved. It reads `viewModel.inlineEdit`, the *same*
    /// `EditRecordingViewModel` the Files browser presents as a sheet.
    @Bindable var viewModel: RecordingViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var waveformSamples: [Float] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sonicBackground.ignoresSafeArea()

                if viewModel.isRecording {
                    recordingInterface
                } else if viewModel.isSaveFlowPresented {
                    saveEditInterface
                } else {
                    preRecordingInterface
                }
            }
            .navigationTitle(viewModel.isRecording ? "Recording" : (viewModel.isSaveFlowPresented ? "" : "New Recording"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isSaveFlowPresented {
                        TextField("Recording name", text: Binding(
                            get: { viewModel.saveFileName },
                            set: { viewModel.setSaveFileName($0) }
                        ))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicTextPrimary)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.sonicSurface, in: RoundedRectangle(cornerRadius: 8))
                        .frame(minWidth: 180, maxWidth: 260)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    if !viewModel.isRecording {
                        Button {
                            viewModel.discardRecording()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.sonicTextSecondary)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaveFlowPresented {
                        if let inlineEdit = viewModel.inlineEdit, inlineEdit.isTrimming {
                            HStack(spacing: 16) {
                                Button {
                                    viewModel.inlineEdit?.deleteRangeTapped()
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }

                                Button {
                                    viewModel.inlineEdit?.cancelTrim()
                                } label: {
                                    Image(systemName: "xmark")
                                        .foregroundColor(.sonicTextSecondary)
                                }

                                Button {
                                    viewModel.inlineEdit?.applyTrim()
                                } label: {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.sonicPrimary)
                                }
                            }
                        } else {
                            HStack(spacing: 16) {
                                if viewModel.inlineEdit != nil {
                                    Button {
                                        viewModel.inlineEdit?.trimTapped()
                                    } label: {
                                        Image(systemName: "pencil")
                                            .foregroundColor(.sonicPrimary)
                                    }
                                }

                                Button {
                                    viewModel.saveRecording()
                                } label: {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.sonicPrimary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .alert("Microphone Permission Required", isPresented: $viewModel.showPermissionAlert) {
            Button("Allow Microphone") {
                viewModel.requestPermissions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sonic Player needs access to your microphone to record audio.")
        }
        .alert("Action Failed", isPresented: Binding(
            get: { viewModel.inlineEdit?.trimError != nil },
            set: { if !$0 { viewModel.inlineEdit?.cancelTrim() } }
        )) {
            Button("OK", role: .cancel) { viewModel.inlineEdit?.cancelTrim() }
        } message: {
            if let error = viewModel.inlineEdit?.trimError { Text(error) }
        }
        .onAppear {
            viewModel.onAppear()
            loadWaveformIfNeeded()
        }
        .onChange(of: viewModel.inlineEdit?.recording.url) { _, _ in
            waveformSamples = []
            loadWaveformIfNeeded()
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
                viewModel.startRecordingTapped()
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
        VStack(spacing: 24) {
            Spacer()

            Text(formatTime(viewModel.recordingTime))
                .font(.system(size: 48, weight: .light, design: .rounded))
                .foregroundColor(.sonicTextPrimary)
                .monospacedDigit()

            RecordingWaveformView(peakLevel: viewModel.peakLevel)
                .frame(height: 80)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)

            // Stop button
            Button {
                viewModel.stopRecordingTapped()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.red.opacity(0.3), radius: 12, x: 0, y: 6)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Combined Save + Edit Interface

    private var saveEditInterface: some View {
        Group {
            if let inlineEdit = viewModel.inlineEdit {
                if verticalSizeClass == .compact {
                    landscapeEditLayout(inlineEdit)
                } else {
                    portraitEditLayout(inlineEdit)
                }
            } else {
                VStack(spacing: 16) {
                    Spacer().frame(height: 80)
                    ProgressView().tint(.sonicPrimary)
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundColor(.sonicTextSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .overlay {
            if viewModel.inlineEdit?.isTrimming_InProgress == true {
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

    // MARK: - Portrait Layout

    private func portraitEditLayout(_ inlineEdit: EditRecordingViewModel) -> some View {
        VStack(spacing: 28) {
            inlineWaveformArea(inlineEdit)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Spacer()

            Text(formatFullTime(inlineEdit.currentTime))
                .font(.system(size: 48, weight: .bold, design: .default))
                .foregroundColor(.sonicTextPrimary)
                .monospacedDigit()

            inlinePlaybackControls
                .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Landscape Layout

    private func landscapeEditLayout(_ inlineEdit: EditRecordingViewModel) -> some View {
        VStack(spacing: 12) {
            inlineWaveformArea(inlineEdit)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Spacer()

            Text(formatFullTime(inlineEdit.currentTime))
                .font(.system(size: 36, weight: .bold, design: .default))
                .foregroundColor(.sonicTextPrimary)
                .monospacedDigit()

            inlinePlaybackControls

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 12)
    }

    // MARK: - Real Waveform Bars (center-mirrored)

    @ViewBuilder
    private var realWaveformBars: some View {
        GeometryReader { geo in
            // Horizontal baseline
            Path { path in
                let y = geo.size.height / 2
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: geo.size.width, y: y))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .foregroundColor(.sonicTextMuted.opacity(0.4))

            // Mirrored waveform
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(waveformSamples.enumerated()), id: \.offset) { _, sample in
                    Capsule()
                        .fill(Color.sonicPrimary.opacity(0.7))
                        .frame(width: 3, height: max(3, CGFloat(sample) * geo.size.height * 0.85))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func loadWaveformIfNeeded() {
        guard waveformSamples.isEmpty, let url = viewModel.inlineEdit?.recording.url else { return }
        Task {
            let samples = await AudioWaveformExtractor.extract(url: url, sampleCount: 60)
            await MainActor.run {
                waveformSamples = samples
            }
        }
    }

    // MARK: - Inline Waveform

    private func inlineWaveformArea(_ editState: EditRecordingViewModel) -> some View {
        VStack(spacing: 8) {
            ZStack {
                if editState.isTrimming {
                    inlineTrimWaveform(editState)
                } else {
                    inlinePlaybackWaveform(editState)
                }
            }
            .frame(height: verticalSizeClass == .compact ? 140 : 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Time axis ticks
            timeAxisLabels(duration: editState.recording.duration)
                .padding(.horizontal, 4)

            if editState.isTrimming {
                Text("Duration: \(formatEditTime(editState.trimEnd - editState.trimStart))")
                    .font(.caption2)
                    .foregroundColor(.sonicPrimary)
            }
        }
    }

    // MARK: - Time Axis

    private func timeAxisLabels(duration: TimeInterval) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                let fraction = Double(index) / 4.0
                Text(formatEditTime(duration * fraction))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.sonicTextSecondary)
                    .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : (index == 4 ? .trailing : .center))
            }
        }
    }

    private func inlinePlaybackWaveform(_ editState: EditRecordingViewModel) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.sonicPrimary.opacity(0.06))

            realWaveformBars
                .padding(.horizontal, 8)

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
                                viewModel.inlineEdit?.scrub(to: time)
                            }
                    )
            }
        }
    }

    private func inlineTrimWaveform(_ editState: EditRecordingViewModel) -> some View {
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

                realWaveformBars
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 8)

                // Left handle
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.sonicPrimary)
                    .frame(width: 4, height: 120)
                    .offset(x: startX - 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newStart = (value.location.x / totalWidth) * editState.recording.duration
                                viewModel.inlineEdit?.trimStartChanged(max(0, min(newStart, editState.trimEnd - 1)))
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
                                viewModel.inlineEdit?.trimEndChanged(max(editState.trimStart + 1, min(newEnd, editState.recording.duration)))
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
        HStack(spacing: 44) {
            Button { viewModel.inlineEdit?.skipBackward() } label: {
                Image(systemName: "gobackward.15")
                    .font(.title)
                    .foregroundColor(.sonicTextPrimary)
                    .frame(width: 56, height: 56)
            }

            Button { viewModel.inlineEdit?.playPauseTapped() } label: {
                ZStack {
                    Circle()
                        .fill(Color.sonicPrimary)
                        .frame(width: 72, height: 72)
                        .shadow(color: Color.sonicPrimary.opacity(0.35), radius: 12, x: 0, y: 6)

                    Image(systemName: viewModel.inlineEdit?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .offset(x: viewModel.inlineEdit?.isPlaying == true ? 0 : 2)
                }
            }

            Button { viewModel.inlineEdit?.skipForward() } label: {
                Image(systemName: "goforward.15")
                    .font(.title)
                    .foregroundColor(.sonicTextPrimary)
                    .frame(width: 56, height: 56)
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

    private func formatFullTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
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
