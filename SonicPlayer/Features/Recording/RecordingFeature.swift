import ComposableArchitecture
import Foundation

@Reducer
struct RecordingFeature {
    @ObservableState
    struct State: Equatable {
        // Recording state
        var isRecording: Bool = false
        var recordingTime: TimeInterval = 0
        var currentRecordingURL: URL?
        var peakLevel: Float = 0
        var hasPermission: Bool = false
        var showPermissionAlert: Bool = false

        // Save flow state
        var isSaveFlowPresented: Bool = false
        var saveFileName: String = ""
        var saveDestination: URL? = nil // nil = Library root (Documents)

        // Edit state (inline after recording stops)
        var inlineEdit: EditRecordingFeature.State?
        // Legacy sheet-based edit (kept for file browser edits)
        @Presents var editRecording: EditRecordingFeature.State?

        var recordingsCollection: URL? {
            guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            return documentsDir.appendingPathComponent("Recordings", isDirectory: true)
        }
    }

    enum Action {
        case onAppear
        case checkPermissions
        case permissionsChecked(Bool)
        case requestPermissions
        case permissionsRequested(Bool)

        // Recording
        case startRecordingTapped
        case stopRecordingTapped
        case recordingStarted(URL)
        case recordingStopped(URL?)
        case recordingFailed(Error)
        case updateRecordingTime
        case timeUpdated(TimeInterval, Float)

        // Save flow
        case setSaveFileName(String)
        case setSaveDestination(URL?)
        case saveRecording
        case saveAndEditRecording
        case discardRecording
        case recordingSaved(AudioFile?)
        case dismissSaveFlow

        // Edit
        case inlineEditLoaded(AudioFile)
        case inlineEdit(EditRecordingFeature.Action)
        case editRecording(PresentationAction<EditRecordingFeature.Action>)

        // Permission alert
        case setShowPermissionAlert(Bool)
    }

    @Dependency(\.audioRecorder) var audioRecorder
    @Dependency(\.fileManager) var fileManager
    @Dependency(\.continuousClock) var clock
    @Dependency(\.audioPlayer) var audioPlayer

    private enum CancelID { case recordingTimer }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.checkPermissions)

            case .checkPermissions:
                return .run { send in
                    let hasPermission = await audioRecorder.checkPermissions()
                    await send(.permissionsChecked(hasPermission))
                }

            case let .permissionsChecked(granted):
                state.hasPermission = granted
                if !granted {
                    state.showPermissionAlert = true
                }
                return .none

            case .requestPermissions:
                return .run { send in
                    let granted = await audioRecorder.requestPermissions()
                    await send(.permissionsRequested(granted))
                }

            case let .permissionsRequested(granted):
                state.hasPermission = granted
                state.showPermissionAlert = !granted
                return .none

            case .startRecordingTapped:
                guard state.hasPermission else {
                    return .send(.requestPermissions)
                }

                guard let recordingsCollection = state.recordingsCollection else {
                    return .none
                }

                // Create recordings folder if needed
                try? FileManager.default.createDirectory(at: recordingsCollection, withIntermediateDirectories: true)

                // Generate filename with timestamp
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
                let timestamp = dateFormatter.string(from: Date())
                let filename = "Recording \(timestamp).m4a"
                let recordingURL = recordingsCollection.appendingPathComponent(filename)

                state.currentRecordingURL = recordingURL
                state.recordingTime = 0
                state.peakLevel = 0

                return .run { send in
                    do {
                        try await audioRecorder.startRecording(recordingURL)
                        await send(.recordingStarted(recordingURL))
                    } catch {
                        await send(.recordingFailed(error))
                    }
                }

            case let .recordingStarted(url):
                state.isRecording = true
                state.currentRecordingURL = url
                return .send(.updateRecordingTime)

            case .stopRecordingTapped:
                guard state.isRecording else { return .none }

                state.isRecording = false

                return .run { send in
                    do {
                        let url = try await audioRecorder.stopRecording()
                        await send(.recordingStopped(url))
                    } catch {
                        await send(.recordingFailed(error))
                    }
                }
                .concatenate(with: .cancel(id: CancelID.recordingTimer))

            case let .recordingStopped(url):
                state.recordingTime = 0
                state.peakLevel = 0

                guard let url else { return .none }
                state.currentRecordingURL = url
                state.saveFileName = url.deletingPathExtension().lastPathComponent
                state.isSaveFlowPresented = true

                // Copy the original recording to a temp file for non-destructive editing
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("SonicPlayer/edit", isDirectory: true)
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let tempEditURL = tempDir.appendingPathComponent("edit-\(UUID().uuidString).m4a")
                try? FileManager.default.copyItem(at: url, to: tempEditURL)

                return .run { send in
                    if let metadata = try? await fileManager.getMetadata(tempEditURL) {
                        await send(.inlineEditLoaded(metadata))
                    }
                }

            case let .recordingFailed(error):
                state.isRecording = false
                state.currentRecordingURL = nil
                print("Recording failed: \(error.localizedDescription)")
                return .none

            case .updateRecordingTime:
                guard state.isRecording else { return .none }

                return .run { send in
                    for await _ in clock.timer(interval: .milliseconds(100)) {
                        let time = await audioRecorder.currentTime()
                        let peak = await audioRecorder.peakPower()
                        await send(.timeUpdated(time, peak))
                    }
                }
                .cancellable(id: CancelID.recordingTimer)

            case let .timeUpdated(time, peak):
                state.recordingTime = time
                state.peakLevel = peak
                return .none

            // MARK: - Save Flow

            case let .setSaveFileName(name):
                state.saveFileName = name
                return .none

            case let .setSaveDestination(url):
                state.saveDestination = url
                return .none

            case .saveRecording:
                // Source: edited temp file (inline edit URL)
                // Original: the raw recording file (temp location)
                let editedURL = state.inlineEdit?.recording.url
                let originalURL = state.currentRecordingURL
                guard let editedURL else { return .none }

                // Always save in the "Recordings" collection with the user-chosen name
                let destination = state.recordingsCollection ?? fileManager.documentsDirectory()
                try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                let baseName = state.saveFileName.isEmpty ? "Recording" : state.saveFileName

                // Compute final target URL (handle duplicates)
                let finalTargetURL: URL = {
                    var candidate = destination.appendingPathComponent("\(baseName).m4a")
                    var counter = 2
                    while FileManager.default.fileExists(atPath: candidate.path) && candidate != originalURL {
                        candidate = destination.appendingPathComponent("\(baseName) \(counter).m4a")
                        counter += 1
                    }
                    return candidate
                }()

                state.isSaveFlowPresented = false
                state.inlineEdit = nil

                return .run { send in
                    await audioPlayer.stop()
                    do {
                        // Delete the untouched original recording
                        if let originalURL, originalURL != finalTargetURL {
                            try? FileManager.default.removeItem(at: originalURL)
                        }
                        // Move edited temp to final destination
                        if FileManager.default.fileExists(atPath: finalTargetURL.path) {
                            try? FileManager.default.removeItem(at: finalTargetURL)
                        }
                        try FileManager.default.moveItem(at: editedURL, to: finalTargetURL)
                        await send(.recordingSaved(nil))
                    } catch {
                        print("Failed to save recording: \(error.localizedDescription)")
                        await send(.recordingSaved(nil))
                    }
                }

            case .saveAndEditRecording:
                guard let sourceURL = state.currentRecordingURL else { return .none }

                let destination = state.recordingsCollection ?? fileManager.documentsDirectory()
                try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                let fileName = state.saveFileName.isEmpty ? sourceURL.lastPathComponent : "\(state.saveFileName).m4a"
                let targetURL = destination.appendingPathComponent(fileName)

                state.isSaveFlowPresented = false

                return .run { send in
                    do {
                        if sourceURL != targetURL {
                            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
                        }
                        if let metadata = try? await fileManager.getMetadata(targetURL) {
                            await send(.recordingSaved(metadata))
                        }
                    } catch {
                        print("Failed to save recording: \(error.localizedDescription)")
                    }
                }

            case let .recordingSaved(audioFile):
                state.currentRecordingURL = nil
                state.saveFileName = ""
                state.saveDestination = nil
                state.inlineEdit = nil
                state.isSaveFlowPresented = false
                // If save & edit from file browser, open editor
                if let audioFile, !state.isSaveFlowPresented {
                    state.editRecording = EditRecordingFeature.State(recording: audioFile)
                }
                return .none

            case let .inlineEditLoaded(audioFile):
                state.inlineEdit = EditRecordingFeature.State(recording: audioFile)
                return .none

            case let .inlineEdit(editAction):
                // Forward inline edit actions to the EditRecordingFeature reducer
                guard var editState = state.inlineEdit else { return .none }
                let editReducer = EditRecordingFeature()
                let effect = editReducer.reduce(into: &editState, action: editAction)
                state.inlineEdit = editState
                return effect.map { Action.inlineEdit($0) }

            case .discardRecording:
                // Delete edit temp file
                if let editURL = state.inlineEdit?.recording.url {
                    try? FileManager.default.removeItem(at: editURL)
                }
                // Delete original recording
                if let url = state.currentRecordingURL {
                    try? FileManager.default.removeItem(at: url)
                }
                state.currentRecordingURL = nil
                state.saveFileName = ""
                state.saveDestination = nil
                state.isSaveFlowPresented = false
                state.inlineEdit = nil
                return .run { _ in
                    await audioPlayer.stop()
                }

            case .dismissSaveFlow:
                state.isSaveFlowPresented = false
                return .none

            case .editRecording(.dismiss):
                return .run { _ in
                    await audioPlayer.stop()
                }

            case .editRecording:
                return .none

            case let .setShowPermissionAlert(show):
                state.showPermissionAlert = show
                return .none
            }
        }
        .ifLet(\.$editRecording, action: \.editRecording) {
            EditRecordingFeature()
        }
    }
}

// MARK: - Edit Recording Feature (unchanged from original)

@Reducer
struct EditRecordingFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var id: UUID { recording.id }
        var recording: AudioFile
        var originalURL: URL // Untouched original — only replaced on save
        var hasEdits: Bool = false
        var isPlaying: Bool = false
        var currentTime: TimeInterval = 0
        var trimStart: TimeInterval = 0
        var trimEnd: TimeInterval
        var isTrimming: Bool = false
        var isTrimming_InProgress: Bool = false
        var trimError: String?

        init(recording: AudioFile) {
            self.recording = recording
            self.originalURL = recording.url
            self.trimEnd = recording.duration
        }
    }

    enum Action {
        case onAppear
        case tempCopyCreated(AudioFile)
        case playPauseTapped
        case skipForward
        case skipBackward
        case trimTapped
        case deleteRangeTapped
        case trimStartChanged(TimeInterval)
        case trimEndChanged(TimeInterval)
        case applyTrim
        case trimStarted
        case trimCompleted(URL)
        case trimFailed(Error)
        case deleteRangeCompleted(URL)
        case deleteRangeFailed(Error)
        case cancelTrim
        case deleted
        case trimApplied
        case saveChanges
        case discardChanges
        case renameTapped(String)
        case renameApplied(AudioFile)
        case renameFailed(String)
        case updatePlaybackTime
        case playbackTimeUpdated(TimeInterval)
        case playbackEnded
    }

    @Dependency(\.audioTrimmer) var audioTrimmer
    @Dependency(\.audioPlayer) var audioPlayer
    @Dependency(\.fileManager) var fileManager

    private enum CancelID { case playbackTimeUpdates }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.currentTime = 0
                // If we already have a temp copy, skip
                if state.recording.url != state.originalURL {
                    return .none
                }
                // Copy original to temp for non-destructive editing
                let originalURL = state.originalURL
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("SonicPlayer/edit", isDirectory: true)
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let tempURL = tempDir.appendingPathComponent("edit-\(UUID().uuidString).\(originalURL.pathExtension)")
                return .run { send in
                    do {
                        try FileManager.default.copyItem(at: originalURL, to: tempURL)
                        if let metadata = try? await fileManager.getMetadata(tempURL) {
                            await send(.tempCopyCreated(metadata))
                        }
                    } catch {
                        print("Failed to create temp edit copy: \(error.localizedDescription)")
                    }
                }

            case let .tempCopyCreated(audioFile):
                state.recording = audioFile
                state.trimEnd = audioFile.duration
                return .none

            case .playPauseTapped:
                if state.isPlaying {
                    state.isPlaying = false
                    return .merge(
                        .cancel(id: CancelID.playbackTimeUpdates),
                        .run { _ in
                            await audioPlayer.pause()
                        }
                    )
                }

                state.isPlaying = true
                let url = state.recording.url
                let startTime = state.currentTime
                let duration = state.recording.duration

                return .run { send in
                    do {
                        try await audioPlayer.prepare(url)
                        await audioPlayer.seek(startTime)
                        try await audioPlayer.play(url)
                    } catch {
                        await send(.playbackEnded)
                        return
                    }

                    for await time in await audioPlayer.timeUpdates() {
                        if time >= duration, duration > 0 {
                            await send(.playbackEnded)
                            break
                        }
                        await send(.playbackTimeUpdated(time))
                    }
                }
                .cancellable(id: CancelID.playbackTimeUpdates, cancelInFlight: true)

            case .updatePlaybackTime:
                return .none

            case let .playbackTimeUpdated(time):
                state.currentTime = time
                return .none

            case .playbackEnded:
                state.isPlaying = false
                state.currentTime = 0
                return .merge(
                    .cancel(id: CancelID.playbackTimeUpdates),
                    .run { _ in
                        await audioPlayer.stop()
                    }
                )

            case .skipForward:
                let newTime = min(state.currentTime + 15, state.recording.duration)
                state.currentTime = newTime
                return .run { _ in
                    await audioPlayer.seek(newTime)
                }

            case .skipBackward:
                let newTime = max(state.currentTime - 15, 0)
                state.currentTime = newTime
                return .run { _ in
                    await audioPlayer.seek(newTime)
                }

            case .trimTapped:
                state.isTrimming = true
                return .none

            case .deleteRangeTapped:
                guard state.isTrimming, !state.isTrimming_InProgress else { return .none }

                state.isTrimming_InProgress = true
                state.trimError = nil
                state.isPlaying = false

                let url = state.recording.url
                let start = state.trimStart
                let end = state.trimEnd

                return .run { send in
                    do {
                        await audioPlayer.stop()
                        let updatedURL = try await audioTrimmer.deleteAudioRange(url, start, end)
                        await send(.deleteRangeCompleted(updatedURL))
                    } catch {
                        await send(.deleteRangeFailed(error))
                    }
                }

            case let .trimStartChanged(time):
                state.trimStart = time
                return .none

            case let .trimEndChanged(time):
                state.trimEnd = time
                return .none

            case .applyTrim:
                guard !state.isTrimming_InProgress else { return .none }

                state.isTrimming_InProgress = true
                state.trimError = nil
                state.isPlaying = false

                let url = state.recording.url
                let start = state.trimStart
                let end = state.trimEnd

                return .run { send in
                    await send(.trimStarted)

                    do {
                        await audioPlayer.stop()
                        let trimmedURL = try await audioTrimmer.trimAudio(url, start, end)
                        await send(.trimCompleted(trimmedURL))
                    } catch {
                        await send(.trimFailed(error))
                    }
                }

            case .trimStarted:
                return .none

            case let .trimCompleted(newURL):
                // Delete the previous temp file (before the trim)
                let previousURL = state.recording.url
                if previousURL != newURL {
                    try? FileManager.default.removeItem(at: previousURL)
                }
                state.isTrimming_InProgress = false
                state.isTrimming = false
                state.hasEdits = true
                state.currentTime = 0
                state.trimStart = 0
                return .run { send in
                    if let metadata = try? await fileManager.getMetadata(newURL) {
                        await send(.tempCopyCreated(metadata))
                    }
                    await send(.trimApplied)
                }

            case let .trimFailed(error):
                state.isTrimming_InProgress = false
                state.trimError = error.localizedDescription
                return .none

            case let .deleteRangeCompleted(newURL):
                let previousURL = state.recording.url
                if previousURL != newURL {
                    try? FileManager.default.removeItem(at: previousURL)
                }
                state.isTrimming_InProgress = false
                state.isTrimming = false
                state.hasEdits = true
                state.currentTime = 0
                state.trimStart = 0
                return .run { send in
                    if let metadata = try? await fileManager.getMetadata(newURL) {
                        await send(.tempCopyCreated(metadata))
                    }
                    await send(.trimApplied)
                }

            case let .deleteRangeFailed(error):
                state.isTrimming_InProgress = false
                state.trimError = error.localizedDescription
                return .none

            case .cancelTrim:
                state.isTrimming = false
                state.trimStart = 0
                state.trimEnd = state.recording.duration
                state.trimError = nil
                return .none

            case .deleted, .trimApplied:
                return .none

            case .saveChanges:
                let tempURL = state.recording.url
                let originalURL = state.originalURL
                guard tempURL != originalURL else { return .none }
                return .run { _ in
                    await audioPlayer.stop()
                    do {
                        // Replace original with edited temp
                        if FileManager.default.fileExists(atPath: originalURL.path) {
                            try FileManager.default.removeItem(at: originalURL)
                        }
                        try FileManager.default.moveItem(at: tempURL, to: originalURL)
                    } catch {
                        print("Failed to save edits: \(error.localizedDescription)")
                    }
                }

            case .discardChanges:
                let tempURL = state.recording.url
                let originalURL = state.originalURL
                return .run { _ in
                    await audioPlayer.stop()
                    if tempURL != originalURL {
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                }

            case let .renameTapped(newName):
                let url = state.recording.url
                let fileExtension = url.pathExtension
                let finalName = newName.contains(".") ? newName : "\(newName).\(fileExtension)"
                let newURL = url.deletingLastPathComponent().appendingPathComponent(finalName)
                return .run { send in
                    do {
                        try await fileManager.renameItem(url, finalName)
                        if let updated = try? await fileManager.getMetadata(newURL) {
                            await send(.renameApplied(updated))
                        } else {
                            await send(.renameFailed("Rename failed."))
                        }
                    } catch {
                        await send(.renameFailed(error.localizedDescription))
                    }
                }

            case let .renameApplied(updated):
                state.recording = updated
                return .none

            case let .renameFailed(message):
                state.trimError = message
                return .none
            }
        }
    }
}
