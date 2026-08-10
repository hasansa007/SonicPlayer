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

    /// How many samples the scrolling waveform keeps — five seconds at `meterInterval`, and the
    /// same bar count `RecordingWaveformView` has always drawn.
    static let levelWindow = 50

    // MARK: - Recording

    var isRecording = false
    /// A capture that is still open but not writing. `isRecording` stays true throughout: it means
    /// *a take is in progress*, which is what `stopRecordingTapped` and `addMarker` both need to
    /// know, and only stopping ends it.
    var isPaused = false
    var recordingTime: TimeInterval = 0
    var currentRecordingURL: URL?
    var peakLevel: Float = 0
    var hasPermission = false
    var showPermissionAlert = false

    /// The scrolling waveform, newest last, already normalised through `MeterLevel` — `peakLevel`
    /// stays as it was for the existing recorder view, which reads a single value rather than a
    /// history.
    private(set) var levels: [Double] = []

    /// **Raised the moment a take is written to disk**, before any naming or trimming.
    ///
    /// Distinct from `onFinished`, which means *the save flow completed* — and the save flow is
    /// rendered only by `RecordingView`, which the dial never presents. So from the dial nothing
    /// reloaded the library after a take: the file was on disk and the screen said the folder was
    /// empty, until an unrelated import happened to force a refresh.
    ///
    /// A separate edge rather than reusing `onFinished`, because these are different facts and one
    /// of them will be true in flows where the other never is.
    var onTakeLanded: ((URL) -> Void)?

    /// Timestamps dropped during this take (#75). Cleared when a take starts, and handed to the
    /// registry under the name the file lands as.
    private(set) var markers = RecordingMarkers()

    // MARK: - Input gain

    /// `0...1`. Only meaningful while `isGainSettable`, which is false on every built-in iPhone mic.
    private(set) var gain: Double = 1
    private(set) var isGainSettable = false

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

    /// The URL a take actually landed as — which is not knowable before the save, because
    /// `UniqueNameResolver` may have renamed it. Fired only when the file is really there, so
    /// markers are never filed under a name that does not exist (#75).
    var onSaved: (URL) -> Void = { _ in }

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

    /// **The first press asks and then records; it used to only ask.**
    ///
    /// This was `guard hasPermission else { requestPermissions(); return }` — so on a fresh install
    /// the first press raised the system prompt, returned, and did nothing after you granted.
    /// Pressing again worked, which is why it read as "recording does not work the first time"
    /// rather than as a permission problem.
    ///
    /// The dial made it certain rather than likely. `hasPermission` was seeded by
    /// `checkPermissions()`, called from `RecordingView.onAppear` — and the dial drives this type
    /// directly without ever presenting that view, so the flag was *always* false on the first
    /// press however many times the app had recorded before.
    ///
    /// Requesting is cheap when the answer is already yes: the system returns the stored grant
    /// without prompting, so this path costs one await rather than a dialog.
    func startRecordingTapped() {
        guard hasPermission else {
            workTask = Task { [weak self, audioRecorder] in
                let granted = await audioRecorder.requestPermissions()
                self?.hasPermission = granted
                self?.showPermissionAlert = !granted
                guard granted else { return }
                self?.beginTake()
            }
            return
        }
        beginTake()
    }

    private func beginTake() {
        guard let recordingsCollection else { return }

        try? FileManager.default.createDirectory(at: recordingsCollection, withIntermediateDirectories: true)

        let recordingURL = recordingsCollection
            .appendingPathComponent(RecordingFilename.make(at: Date()))

        currentRecordingURL = recordingURL
        recordingTime = 0
        peakLevel = 0
        levels = []
        markers = RecordingMarkers()
        isPaused = false

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
        readInputGain()
    }

    func stopRecordingTapped() {
        guard isRecording else { return }
        isRecording = false
        isPaused = false

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
        // The file exists from here on, whatever happens to the save flow above it.
        onTakeLanded?(url)

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
        isPaused = false
        currentRecordingURL = nil
        print("Recording failed: \(error.localizedDescription)")
    }

    // MARK: - Pause
    //
    // Pausing keeps the file open — only `stopRecording()` closes it — so a resumed take continues
    // into the same recording instead of producing a second one. The meter loop stays alive and
    // skips its body rather than being cancelled and restarted: restarting it would put the
    // teardown ordering this type's header warns about back in play, and buy nothing.

    func togglePauseTapped() {
        guard isRecording else { return }
        if isPaused { resumeTapped() } else { pauseTapped() }
    }

    func pauseTapped() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        Task { [audioRecorder] in await audioRecorder.pauseRecording() }
    }

    /// Clears the flag only once the recorder confirms it took the file back. A resume that
    /// silently failed would leave a running clock over a dead file, which is the one outcome worse
    /// than a stuck pause button.
    func resumeTapped() {
        guard isRecording, isPaused else { return }
        Task { [weak self, audioRecorder] in
            guard await audioRecorder.resumeRecording() else { return }
            self?.isPaused = false
        }
    }

    // MARK: - Markers

    /// Whether the marker landed. Refused when nothing is being captured, and when one is already
    /// within `RecordingMarkers.minimumSeparation` — which is what a paused clock produces, since
    /// every tap while paused reports the same elapsed time.
    @discardableResult
    func addMarker() -> Bool {
        guard isRecording else { return false }
        return markers.add(at: recordingTime)
    }

    // MARK: - Input gain

    private func readInputGain() {
        Task { [weak self, audioRecorder] in
            let settable = await audioRecorder.isInputGainSettable()
            let current = await audioRecorder.inputGain()
            self?.isGainSettable = settable
            self?.gain = Double(min(max(0, current), 1))
        }
    }

    /// `0...1`. A no-op on hardware with no settable gain — which is why `isGainSettable` is
    /// published: the dial refuses the axis rather than turning against nothing.
    func setGain(_ value: Double) {
        let clamped = min(max(0, value), 1)
        guard clamped != gain, isGainSettable else { return }
        gain = clamped
        Task { [audioRecorder] in _ = await audioRecorder.setInputGain(Float(clamped)) }
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
                // A paused take reports a frozen clock and a dead meter. Sampling it would scroll
                // a flat line across the waveform and say the recording was silent rather than
                // stopped.
                guard self?.isPaused == false else { continue }
                let time = await audioRecorder.currentTime()
                let peak = await audioRecorder.peakPower()
                guard !Task.isCancelled else { return }
                self?.recordingTime = time
                self?.peakLevel = peak
                self?.appendLevel(peak)
            }
        }
    }

    /// Newest last, oldest dropped. The window is what makes it a *scrolling* waveform rather than
    /// an ever-growing array behind a view that can only show the last five seconds anyway.
    private func appendLevel(_ peak: Float) {
        levels.append(MeterLevel.fraction(ofPeak: peak))
        if levels.count > Self.levelWindow {
            levels.removeFirst(levels.count - Self.levelWindow)
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
            var landed = false
            do {
                if let originalURL, originalURL != finalTargetURL {
                    try? FileManager.default.removeItem(at: originalURL)
                }
                if FileManager.default.fileExists(atPath: finalTargetURL.path) {
                    try? FileManager.default.removeItem(at: finalTargetURL)
                }
                try FileManager.default.moveItem(at: editedURL, to: finalTargetURL)
                landed = true
            } catch {
                print("Failed to save recording: \(error.localizedDescription)")
            }
            // `onSaved` fires only on the branch that produced a file — unlike `onFinished`, which
            // is reached on both, exactly as `.recordingSaved` was sent from both.
            if landed { self?.reportSaved(finalTargetURL) }
            self?.recordingSaved()
        }
    }

    /// Announces the name the take landed as, while `markers` still holds this session's drops —
    /// `resetSaveFlow()` clears them a moment later.
    private func reportSaved(_ url: URL) {
        onSaved(url)
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
        markers = RecordingMarkers()
        levels = []
        isPaused = false
    }
}
