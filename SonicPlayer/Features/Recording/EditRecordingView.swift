import SwiftUI

struct EditRecordingView: View {

    /// Owns its view model rather than being handed one (#17).
    ///
    /// Both presenters — the Files browser and Home — hold only the `AudioFile`, because
    /// `CollectionsFeature` is still a reducer and its value-typed `State` cannot store a
    /// reference. Constructing here keeps the model's lifetime tied to the sheet's identity;
    /// building it in the `.sheet` closure instead would make a new one on every body pass.
    @State private var viewModel: EditRecordingViewModel
    @Environment(\.dismiss) var dismiss
    @State private var isRenaming = false
    @State private var renameText = ""

    init(recording: AudioFile, onFinished: @escaping () -> Void = {}) {
        let model = EditRecordingViewModel(recording: recording)
        model.onFinished = onFinished
        _viewModel = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Waveform
                    waveformArea
                        .padding(.horizontal, 20)

                    // Time
                    Text(formatTime(viewModel.currentTime))
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .padding(.top, 32)
                        .padding(.bottom, 24)

                    // Playback controls
                    playbackControls
                        .padding(.bottom, 16)

                    Spacer()
                }

                // Trimming overlay
                if viewModel.isTrimming_InProgress {
                    Color.black.opacity(0.7).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView().scaleEffect(1.5).tint(.white)
                        Text("Trimming audio...").font(.headline).foregroundColor(.white)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        viewModel.discardChanges()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body).fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(viewModel.recording.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isTrimming {
                        HStack(spacing: 12) {
                            // Apply trim (keep selected range)
                            Button {
                                viewModel.applyTrim()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "scissors")
                                        .font(.caption)
                                    Text("Trim")
                                        .font(.subheadline).fontWeight(.semibold)
                                }
                                .foregroundColor(.sonicPrimary)
                            }
                            .disabled(viewModel.isTrimming_InProgress)

                            // Cancel trim
                            Button {
                                viewModel.cancelTrim()
                            } label: {
                                Text("Cancel")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }

                            // Delete selected range
                            Button {
                                viewModel.deleteRangeTapped()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                    Text("Delete")
                                        .font(.subheadline)
                                }
                                .foregroundColor(.red)
                            }
                            .disabled(viewModel.isTrimming_InProgress)
                        }
                    } else {
                        HStack(spacing: 16) {
                            overflowMenu

                            Button {
                                viewModel.saveChanges()
                                dismiss()
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.body).fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.sonicPrimary))
                            }
                            .disabled(!viewModel.hasEdits)
                            .opacity(viewModel.hasEdits ? 1.0 : 0.4)
                        }
                    }
                }
            }
        }
        .alert("Action Failed", isPresented: Binding(
            get: { viewModel.trimError != nil },
            set: { if !$0 { viewModel.cancelTrim() } }
        )) {
            Button("OK", role: .cancel) { viewModel.cancelTrim() }
        } message: {
            if let error = viewModel.trimError { Text(error) }
        }
        .alert("Rename", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { viewModel.renameTapped(trimmed) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .interactiveDismissDisabled()
        .onAppear { viewModel.onAppear() }
    }

    // MARK: - Overflow Menu (⋯)

    private var overflowMenu: some View {
        Menu {
            Button {
                renameText = viewModel.recording.title
                isRenaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                viewModel.trimTapped()
            } label: {
                Label("Select & Trim", systemImage: "scissors")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundColor(.white)
        }
    }

    // MARK: - Waveform

    private var waveformArea: some View {
        VStack(spacing: 8) {
            ZStack {
                if viewModel.isTrimming {
                    trimWaveform
                } else {
                    playbackWaveform
                }
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Timeline
            HStack {
                Text(formatTime(viewModel.isTrimming ? viewModel.trimStart : 0))
                    .font(.caption2).monospacedDigit()
                    .foregroundColor(.gray)
                Spacer()
                if viewModel.isTrimming {
                    Text("Duration: \(formatTime(viewModel.trimEnd - viewModel.trimStart))")
                        .font(.caption2)
                        .foregroundColor(.sonicPrimary)
                }
                Spacer()
                Text(formatTime(viewModel.isTrimming ? viewModel.trimEnd : viewModel.recording.duration))
                    .font(.caption2).monospacedDigit()
                    .foregroundColor(.gray)
            }
        }
    }

    private var playbackWaveform: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))

            // Waveform bars
            HStack(spacing: 2) {
                ForEach(0..<40, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.sonicPrimary.opacity(0.35))
                        .frame(width: 3, height: CGFloat.random(in: 10...60))
                }
            }

            // Playback position
            GeometryReader { geo in
                let progress = viewModel.recording.duration > 0 ? viewModel.currentTime / viewModel.recording.duration : 0
                Rectangle()
                    .fill(Color.sonicPrimary)
                    .frame(width: 2)
                    .offset(x: geo.size.width * CGFloat(progress))
            }

            // Scrub gesture
            GeometryReader { geo in
                Color.clear.contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let progress = min(max(0, value.location.x / geo.size.width), 1)
                                let time = progress * viewModel.recording.duration
                                viewModel.scrub(to: time)
                            }
                    )
            }
        }
    }

    private var trimWaveform: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))

            GeometryReader { geo in
                let totalWidth = geo.size.width
                let startX = CGFloat(viewModel.trimStart / viewModel.recording.duration) * totalWidth
                let endX = CGFloat(viewModel.trimEnd / viewModel.recording.duration) * totalWidth

                // Dimmed areas
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: startX)

                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: totalWidth - endX)
                    .offset(x: endX)

                // Selected region
                Rectangle()
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: max(0, endX - startX))
                    .offset(x: startX)

                // Waveform bars
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
                    .fill(Color.yellow)
                    .frame(width: 4, height: 120)
                    .offset(x: startX - 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newStart = (value.location.x / totalWidth) * viewModel.recording.duration
                                viewModel.trimStartChanged(max(0, min(newStart, viewModel.trimEnd - 1)))
                            }
                    )

                // Right handle
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.yellow)
                    .frame(width: 4, height: 120)
                    .offset(x: endX - 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newEnd = (value.location.x / totalWidth) * viewModel.recording.duration
                                viewModel.trimEndChanged(max(viewModel.trimStart + 1, min(newEnd, viewModel.recording.duration)))
                            }
                    )

                // Playback position
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .offset(x: CGFloat(viewModel.currentTime / viewModel.recording.duration) * totalWidth)
            }
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 48) {
            Button { viewModel.skipBackward() } label: {
                Image(systemName: "gobackward.15")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 52, height: 52)
            }

            Button { viewModel.playPauseTapped() } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                        .shadow(color: .white.opacity(0.2), radius: 12, x: 0, y: 4)

                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.black)
                        .offset(x: viewModel.isPlaying ? 0 : 2)
                }
            }

            Button { viewModel.skipForward() } label: {
                Image(systemName: "goforward.15")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
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
}
