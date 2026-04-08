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

                VStack(spacing: 0) {
                    Spacer()

                    // Waveform
                    waveformArea
                        .padding(.horizontal, 20)

                    // Time
                    Text(formatTime(store.currentTime))
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
                if store.isTrimming_InProgress {
                    Color.black.opacity(0.7).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView().scaleEffect(1.5).tint(.white)
                        Text("Trimming audio...").font(.headline).foregroundColor(.white)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body).fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(store.recording.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if store.isTrimming {
                        HStack(spacing: 12) {
                            // Apply trim (keep selected range)
                            Button {
                                store.send(.applyTrim)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "scissors")
                                        .font(.caption)
                                    Text("Trim")
                                        .font(.subheadline).fontWeight(.semibold)
                                }
                                .foregroundColor(.sonicPrimary)
                            }
                            .disabled(store.isTrimming_InProgress)

                            // Cancel trim
                            Button {
                                store.send(.cancelTrim)
                            } label: {
                                Text("Cancel")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }

                            // Delete selected range
                            Button {
                                store.send(.deleteRangeTapped)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                    Text("Delete")
                                        .font(.subheadline)
                                }
                                .foregroundColor(.red)
                            }
                            .disabled(store.isTrimming_InProgress)
                        }
                    } else {
                        HStack(spacing: 16) {
                            overflowMenu

                            Button {
                                dismiss()
                            } label: {
                                Text("Save")
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.sonicPrimary)
                            }
                        }
                    }
                }
            }
        }
        .alert("Action Failed", isPresented: Binding(
            get: { store.trimError != nil },
            set: { if !$0 { store.send(.cancelTrim) } }
        )) {
            Button("OK", role: .cancel) { store.send(.cancelTrim) }
        } message: {
            if let error = store.trimError { Text(error) }
        }
        .alert("Rename", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { store.send(.renameTapped(trimmed)) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .interactiveDismissDisabled()
        .onAppear { store.send(.onAppear) }
    }

    // MARK: - Overflow Menu (⋯)

    private var overflowMenu: some View {
        Menu {
            Button {
                renameText = store.recording.title
                isRenaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                store.send(.trimTapped)
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
                if store.isTrimming {
                    trimWaveform
                } else {
                    playbackWaveform
                }
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Timeline
            HStack {
                Text(formatTime(store.isTrimming ? store.trimStart : 0))
                    .font(.caption2).monospacedDigit()
                    .foregroundColor(.gray)
                Spacer()
                if store.isTrimming {
                    Text("Duration: \(formatTime(store.trimEnd - store.trimStart))")
                        .font(.caption2)
                        .foregroundColor(.sonicPrimary)
                }
                Spacer()
                Text(formatTime(store.isTrimming ? store.trimEnd : store.recording.duration))
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
                let progress = store.recording.duration > 0 ? store.currentTime / store.recording.duration : 0
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
                                let time = progress * store.recording.duration
                                store.send(.playbackTimeUpdated(time))
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
                let startX = CGFloat(store.trimStart / store.recording.duration) * totalWidth
                let endX = CGFloat(store.trimEnd / store.recording.duration) * totalWidth

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
                                let newStart = (value.location.x / totalWidth) * store.recording.duration
                                store.send(.trimStartChanged(max(0, min(newStart, store.trimEnd - 1))))
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
                                let newEnd = (value.location.x / totalWidth) * store.recording.duration
                                store.send(.trimEndChanged(max(store.trimStart + 1, min(newEnd, store.recording.duration))))
                            }
                    )

                // Playback position
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .offset(x: CGFloat(store.currentTime / store.recording.duration) * totalWidth)
            }
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 48) {
            Button { store.send(.skipBackward) } label: {
                Image(systemName: "gobackward.15")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 52, height: 52)
            }

            Button { store.send(.playPauseTapped) } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                        .shadow(color: .white.opacity(0.2), radius: 12, x: 0, y: 4)

                    Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.black)
                        .offset(x: store.isPlaying ? 0 : 2)
                }
            }

            Button { store.send(.skipForward) } label: {
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
