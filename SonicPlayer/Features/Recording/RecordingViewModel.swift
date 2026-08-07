import Foundation
import Observation

/// Replaces `RecordingFeature` (#17).
///
/// Two things here are easy to get subtly wrong:
///
/// 1. **Stop, *then* tear down the meter.** The reducer used
///    `.concatenate(with: .cancel(id: CancelID.recordingTimer))` — deliberately not `.merge`. The
///    stop must fully complete before the meter loop dies, or the final level reading races the
///    recorder shutting down. Sequential `await` preserves it: awaiting the stop and only then
///    cancelling. Inverting these two lines is silent.
/// 2. **The meter loop is a hand-written sleep loop.** `Clock.timer(interval:)` is not stdlib — it
///    comes from swift-clocks via TCA, which this epic removes. `meterInterval` is the tested unit;
///    the sleep around it is untested glue by design.
@MainActor
@Observable
final class RecordingViewModel {

    /// The level-meter cadence. Extracted so it is assertable — the sleep loop that consumes it is
    /// not, and does not need to be.
    static let meterInterval: Duration = .milliseconds(100)

    // MARK: - Recording

    var isRecording = false
    var recordingTime: TimeInterval = 0
    var currentRecordingURL: URL?
    var peakLevel: Float = 0
    var hasPermission = false
    var showPermissionAlert = false

    // MARK: - Save flow

    var isSaveFlowPresented = false
    var saveFileName = ""
    /// nil = Library root (Documents).
    var saveDestination: URL?

    /// The editor shown inline once recording stops. Same type the Files browser presents as a
    /// sheet, so its shape has to serve both (#17).
    var inlineEdit: EditRecordingViewModel?

    /// Formerly `AppFeature` observing `.recording(.recordingSaved)` / `.discardRecording` to
    /// dismiss the sheet and refresh the file list.
    var onFinished: () -> Void = {}

    var recordingsCollection: URL? {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return nil }
        return documentsDir.appendingPathComponent("Recordings", isDirectory: true)
    }

    /// Replaces `CancelID.recordingTimer`.
    private var meterTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?

    private let audioRecorder: AudioRecorderClient
    private let audioPlayer: AudioPlayerClient
    private let fileManager: FileManagerClient

    init(
        audioRecorder: AudioRecorderClient = .live,
        audioPlayer: AudioPlayerClient = .live,
        fileManager: FileManagerClient = .live
    ) {
        self.audioRecorder = audioRecorder
        self.audioPlayer = audioPlayer
        self.fileManager = fileManager
    }

    isolated deinit {
        meterTask?.cancel()
        workTask?.cancel()
    }

    // MARK: - Permissions

    func onAppear() {
        checkPermissions()
    }

    func checkPermissions() {
        Task { [weak self, audioRecorder] in
            let granted = await audioRecorder.checkPermissions()
            self?.hasPermission = granted
            if !granted { self?.showPermissionAlert = true }
        }
    }

    func requestPermissions() {
        Task { [weak self, audioRecorder] in
            let granted = await audioRecorder.requestPermissions()
            self?.hasPermission = granted
            self?.showPermissionAlert = !granted
        }
    }

    // MARK: - Recording

    func startRecordingTapped() {
        guard hasPermission else {
            requestPermissions()
            return
        }
        guard let recordingsCollection else { return }

        try? FileManager.default.createDirectory(at: recordingsCollection, withIntermediateDirectories: true)

        let recordingURL = recordingsCollection
            .appendingPathComponent(RecordingFilename.make(at: Date()))

        currentRecordingURL = recordingURL
        recordingTime = 0
        peakLevel = 0

        workTask = Task { [weak self, audioRecorder] in
            do {
                try await audioRecorder.startRecording(recordingURL)
                self?.recordingStarted(recordingURL)
            } catch {
                self?.recordingFailed(error)
            }
        }
    }

    private func recordingStarted(_ url: URL) {
        isRecording = true
        currentRecordingURL = url
        startMeterTimer()
    }

    func stopRecordingTapped() {
        guard isRecording else { return }
        isRecording = false

        Task { [weak self, audioRecorder] in
            do {
                let url = try await audioRecorder.stopRecording()
                self?.recordingStopped(url)
            } catch {
                self?.recordingFailed(error)
            }
            // AFTER the stop completes, never alongside it — see the note on this type.
            self?.stopMeterTimer()
        }
    }

    private func recordingStopped(_ url: URL?) {
        recordingTime = 0
        peakLevel = 0

        guard let url else { return }
        currentRecordingURL = url
        saveFileName = url.deletingPathExtension().lastPathComponent
        isSaveFlowPresented = true

        // Copy to a temp file so the inline editor is non-destructive from the first frame.
        let tempEditURL = EditRecordingViewModel.tempEditURL(pathExtension: "m4a")
        try? FileManager.default.copyItem(at: url, to: tempEditURL)

        workTask = Task { [weak self, fileManager] in
            guard let metadata = try? await fileManager.getMetadata(tempEditURL) else { return }
            self?.presentInlineEditor(for: metadata)
        }
    }

    private func presentInlineEditor(for audioFile: AudioFile) {
        inlineEdit = EditRecordingViewModel(
            recording: audioFile,
            audioPlayer: audioPlayer,
            fileManager: fileManager
        )
    }

    private func recordingFailed(_ error: Error) {
        isRecording = false
        currentRecordingURL = nil
        print("Recording failed: \(error.localizedDescription)")
    }

    // MARK: - Level meter

    private func startMeterTimer() {
        meterTask?.cancel()
        meterTask = Task { [weak self, audioRecorder] in
            while !Task.isCancelled {
                // Sleep first: `clock.timer(interval:)` also fired *after* each interval, so the
                // first sample lands 100ms in rather than immediately.
                try? await Task.sleep(for: Self.meterInterval)
                guard !Task.isCancelled else { return }
                let time = await audioRecorder.currentTime()
                let peak = await audioRecorder.peakPower()
                guard !Task.isCancelled else { return }
                self?.recordingTime = time
                self?.peakLevel = peak
            }
        }
    }

    private func stopMeterTimer() {
        meterTask?.cancel()
        meterTask = nil
    }

    // MARK: - Save flow

    func setSaveFileName(_ name: String) { saveFileName = name }
    func setSaveDestination(_ url: URL?) { saveDestination = url }
    func dismissSaveFlow() { isSaveFlowPresented = false }

    func saveRecording() {
        // Source is the edited temp file; the original is the raw recording.
        guard let editedURL = inlineEdit?.recording.url else { return }
        let originalURL = currentRecordingURL

        let destination = recordingsCollection ?? fileManager.documentsDirectory()
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let baseName = saveFileName.isEmpty ? "Recording" : saveFileName

        // `excluding: originalURL` keeps the name when saving a recording over itself, rather than
        // producing "<name> 2.m4a".
        let finalTargetURL = UniqueNameResolver.resolve(
            baseName: baseName, ext: "m4a", in: destination, excluding: originalURL
        )

        isSaveFlowPresented = false
        inlineEdit = nil

        Task { [weak self, audioPlayer] in
            await audioPlayer.stop()
            do {
                if let originalURL, originalURL != finalTargetURL {
                    try? FileManager.default.removeItem(at: originalURL)
                }
                if FileManager.default.fileExists(atPath: finalTargetURL.path) {
                    try? FileManager.default.removeItem(at: finalTargetURL)
                }
                try FileManager.default.moveItem(at: editedURL, to: finalTargetURL)
            } catch {
                print("Failed to save recording: \(error.localizedDescription)")
            }
            // Reached on both branches, exactly as `.recordingSaved` was sent from both.
            self?.recordingSaved()
        }
    }

    private func recordingSaved() {
        resetSaveFlow()
        onFinished()
    }

    func discardRecording() {
        if let editURL = inlineEdit?.recording.url {
            try? FileManager.default.removeItem(at: editURL)
        }
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        resetSaveFlow()
        Task { [audioPlayer] in await audioPlayer.stop() }
        onFinished()
    }

    /// Dismissing the sheet with a recording still in progress throws it away. `AppFeature` used
    /// to make this call by reading `state.recording.currentRecordingURL`; it cannot see that any
    /// more, so the decision lives here and the view just asks.
    func discardIfUnsaved() {
        guard currentRecordingURL != nil else { return }
        discardRecording()
    }

    private func resetSaveFlow() {
        currentRecordingURL = nil
        saveFileName = ""
        saveDestination = nil
        isSaveFlowPresented = false
        inlineEdit = nil
    }
}
