import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var player = PlayerFeature.State()
        var home = HomeFeature.State()

        // File browser (home)
        var filesPath = StackState<CollectionsFeature.State>()
        var filesRoot = CollectionsFeature.State(currentDirectory: nil)


        var recording = RecordingFeature.State()

        // Sheets
        var isRecordingSheetPresented: Bool = false
        var isSettingsSheetPresented: Bool = false
        var isImportSheetPresented: Bool = false

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.player == rhs.player &&
            lhs.home == rhs.home &&
            lhs.filesPath == rhs.filesPath &&
            lhs.recording == rhs.recording &&
            lhs.isRecordingSheetPresented == rhs.isRecordingSheetPresented &&
            lhs.isSettingsSheetPresented == rhs.isSettingsSheetPresented &&
            lhs.isImportSheetPresented == rhs.isImportSheetPresented
        }
    }

    enum Action {
        case player(PlayerFeature.Action)
        case home(HomeFeature.Action)

        // File browser
        case filesPath(StackAction<CollectionsFeature.State, CollectionsFeature.Action>)
        case filesRoot(CollectionsFeature.Action)

        case recording(RecordingFeature.Action)

        // Sheets
        case recordButtonTapped
        case dismissRecordingSheet
        case settingsTapped
        case dismissSettings
        case importFiles([URL])
        case dismissImportSheet
        case openedFromFiles(URL)

        // Quick Actions
        case quickActionRecord
        case quickActionImport

        // Lifecycle
        case scenePhaseChanged(ScenePhase)
    }

    @Dependency(\.fileManager) var fileManager

    var body: some ReducerOf<Self> {
        Scope(state: \.player, action: \.player) {
            PlayerFeature()
        }

        Scope(state: \.home, action: \.home) {
            HomeFeature()
        }

        Scope(state: \.filesRoot, action: \.filesRoot) {
            CollectionsFeature()
        }

        Scope(state: \.recording, action: \.recording) {
            RecordingFeature()
        }

        Reduce { state, action in
            switch action {

            // MARK: - Home Actions

            case let .home(.playTrack(track)):
                state.player.isExpanded = true
                if state.player.currentTrack?.id != track.id {
                    return .send(.player(.loadTrack(track, [track], .singleFile)))
                }
                return .none

            case .home(.togglePlayPause):
                return .send(.player(.playPauseButtonTapped))

            case let .home(.fileTapped(file)):
                let queue = state.home.recentFiles
                return .send(.player(.loadTrack(file, queue, .singleFile)))

            case .home(.viewAllCollectionsTapped):
                state.filesPath.append(CollectionsFeature.State(currentDirectory: nil))
                return .none

            case let .home(.renameRecentFile(file)):
                return .send(.filesRoot(.renameItemTapped(.file(file))))

            case let .home(.deleteRecentFile(file)):
                state.filesRoot.selectedItems = [.file(file)]
                return .send(.filesRoot(.deleteSelectedTapped))

            case let .home(.editRecentFile(file)):
                state.filesRoot.editAudio = EditRecordingFeature.State(recording: file)
                return .none

            case let .home(.moveRecentFile(file)):
                state.filesRoot.itemsToMove = [.file(file)]
                state.filesRoot.isShowingCollectionPicker = true
                return .none

            // Refresh home after edit view dismissal (so recent files reflect any saved changes)
            case .filesRoot(.editAudio(.dismiss)):
                return .merge(
                    .send(.filesRoot(.refreshFiles)),
                    .send(.home(.loadRecentFiles))
                )

            case .home(.importTapped):
                state.isImportSheetPresented = true
                return .none

            case .home(.newCollectionTapped):
                return .send(.filesRoot(.createCollectionTapped))

            // MARK: - File Browser

            case let .filesRoot(.collectionTapped(folder)):
                state.filesPath.append(CollectionsFeature.State(currentDirectory: folder.url))
                return .none

            case let .filesRoot(.fileTapped(file)):
                let playlist = state.filesRoot.items.compactMap { item -> AudioFile? in
                    if case let .file(audioFile) = item { return audioFile }
                    return nil
                }
                return .send(.player(.loadTrack(file, playlist, .singleFile)))

            case .filesRoot(.playAllTapped):
                let playlist = state.filesRoot.items.compactMap { item -> AudioFile? in
                    if case let .file(audioFile) = item { return audioFile }
                    return nil
                }
                guard let first = playlist.first else { return .none }
                return .send(.player(.loadTrack(first, playlist, .singleFile)))

            case let .filesPath(.element(id: _, action: .collectionTapped(folder))):
                state.filesPath.append(CollectionsFeature.State(currentDirectory: folder.url))
                return .none

            case let .filesPath(.element(id: id, action: .fileTapped(file))):
                if let filesState = state.filesPath[id: id] {
                    let playlist = filesState.items.compactMap { item -> AudioFile? in
                        if case let .file(audioFile) = item { return audioFile }
                        return nil
                    }
                    let folderURL = filesState.currentDirectory
                    let source: PlaylistSource? = folderURL.map { .folder($0) }
                    return .send(.player(.loadTrack(file, playlist, source)))
                }
                return .none

            case let .filesPath(.element(id: id, action: .playAllTapped)):
                if let filesState = state.filesPath[id: id] {
                    let playlist = filesState.items.compactMap { item -> AudioFile? in
                        if case let .file(audioFile) = item { return audioFile }
                        return nil
                    }
                    guard let first = playlist.first else { return .none }
                    let folderURL = filesState.currentDirectory
                    let source: PlaylistSource? = folderURL.map { .folder($0) }
                    return .send(.player(.loadTrack(first, playlist, source)))
                }
                return .none

            // MARK: - Sheets

            case .recordButtonTapped:
                var effects: [Effect<Action>] = []
                if state.player.isPlaying {
                    effects.append(.send(.player(.playPauseButtonTapped)))
                }
                state.isRecordingSheetPresented = true
                return effects.isEmpty ? .none : .merge(effects)

            case .dismissRecordingSheet:
                state.isRecordingSheetPresented = false
                // Clean up any in-progress/unsaved recording
                if state.recording.currentRecordingURL != nil {
                    return .merge(
                        .send(.recording(.discardRecording)),
                        .send(.filesRoot(.refreshFiles)),
                        .send(.home(.loadRecentFiles))
                    )
                }
                return .merge(
                    .send(.filesRoot(.refreshFiles)),
                    .send(.home(.loadRecentFiles))
                )

            case .settingsTapped:
                state.isSettingsSheetPresented = true
                return .none

            case .dismissSettings:
                state.isSettingsSheetPresented = false
                return .none

            case .recording(.recordingSaved):
                state.isRecordingSheetPresented = false
                return .merge(
                    .send(.filesRoot(.refreshFiles)),
                    .send(.home(.loadRecentFiles))
                )

            case .recording(.discardRecording):
                state.isRecordingSheetPresented = false
                return .none

            case let .importFiles(urls):
                state.isImportSheetPresented = false
                return .merge(
                    .send(.filesRoot(.importFiles(urls))),
                    .send(.home(.loadRecentFiles))
                )

            case .dismissImportSheet:
                state.isImportSheetPresented = false
                return .none

            case let .openedFromFiles(url):
                // Import the file then play it
                return .run { send in
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                    // Import to Documents
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let dest = docs.appendingPathComponent(url.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: dest.path) {
                        try? FileManager.default.copyItem(at: url, to: dest)
                    }

                    await send(.filesRoot(.refreshFiles))

                    // Load metadata and play
                    if let file = try? await fileManager.getMetadata(dest) {
                        await send(.player(.loadTrack(file, [file], .singleFile)))
                    }
                }

            // MARK: - Quick Actions

            case .quickActionRecord:
                state.isRecordingSheetPresented = true
                return .none

            case .quickActionImport:
                state.isImportSheetPresented = true
                return .none

            // MARK: - Player Events

            case .player(.trackLoaded), .player(.sessionLoaded):
                state.home.lastPlayedTrack = state.player.currentTrack
                state.home.isPlaying = state.player.isPlaying
                state.home.playbackProgress = state.player.progress
                return .none

            case .player(.playPauseButtonTapped):
                state.home.isPlaying = state.player.isPlaying
                return .none

            case .player(.timeUpdate):
                state.home.playbackProgress = state.player.progress
                return .none

            case .player(.clearSession):
                state.home.lastPlayedTrack = nil
                state.home.isPlaying = false
                state.home.playbackProgress = 0
                return .none

            // MARK: - Lifecycle

            case let .scenePhaseChanged(phase):
                return .send(.player(.scenePhaseChanged(phase)))

            // Clear player if the currently playing track (or its parent) is being moved
            // Clear the player when the track it is playing is deleted or moved away.
            //
            // These read the items out of the ACTION, not out of state. CollectionsFeature runs
            // first and clears selectedItems/itemsToMove as it starts, so reading state here
            // always saw an empty set and this never fired — #22.
            case let .filesRoot(.willRemoveItems(items)),
                 let .filesPath(.element(id: _, action: .willRemoveItems(items))):
                if let currentTrack = state.player.currentTrack,
                   PathMatching.isAffected(trackURL: currentTrack.url, byAnyOf: items.map(\.url)) {
                    return .send(.player(.clearSession))
                }
                return .none

            // After files are reloaded (after any mutation), refresh home recent files too
            case .filesRoot(.itemsLoaded):
                return .send(.home(.loadRecentFiles))

            case .player, .home, .filesRoot, .filesPath, .recording:
                return .none
            }
        }
        .forEach(\.filesPath, action: \.filesPath) {
            CollectionsFeature()
        }
    }
}
