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
        var filesPath = StackState<FilesFeature.State>()
        var filesRoot = FilesFeature.State(currentDirectory: nil)

        // File browser (All Collections sheet)
        var allFoldersPath = StackState<FilesFeature.State>()

        var settings = SettingsFeature.State()
        var recording = RecordingFeature.State()

        // Sheets
        var isRecordingSheetPresented: Bool = false
        var isSettingsSheetPresented: Bool = false
        var isImportSheetPresented: Bool = false

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.player == rhs.player &&
            lhs.home == rhs.home &&
            lhs.filesPath == rhs.filesPath &&
            lhs.allFoldersPath == rhs.allFoldersPath &&
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
        case filesPath(StackAction<FilesFeature.State, FilesFeature.Action>)
        case filesRoot(FilesFeature.Action)
        case allFoldersPath(StackAction<FilesFeature.State, FilesFeature.Action>)

        case settings(SettingsFeature.Action)
        case recording(RecordingFeature.Action)

        // Sheets
        case recordButtonTapped
        case dismissRecordingSheet
        case settingsTapped
        case dismissSettings
        case importFiles([URL])
        case dismissImportSheet
        case openedFromFiles(URL)

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
            FilesFeature()
        }

        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
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

            case .home(.dismissAllFolders):
                state.allFoldersPath.removeAll()
                state.home.isShowingAllFolders = false
                return .none

            case .home(.importTapped):
                state.isImportSheetPresented = true
                return .none

            case .home(.newFolderTapped):
                return .send(.filesRoot(.createFolderTapped))

            // MARK: - File Browser

            case let .filesRoot(.folderTapped(folder)):
                if state.home.isShowingAllFolders {
                    state.allFoldersPath.append(FilesFeature.State(currentDirectory: folder.url))
                } else {
                    state.filesPath.append(FilesFeature.State(currentDirectory: folder.url))
                }
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

            case let .filesPath(.element(id: _, action: .folderTapped(folder))):
                state.filesPath.append(FilesFeature.State(currentDirectory: folder.url))
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

            // MARK: - All Folders Path (same navigation as filesPath)

            case let .allFoldersPath(.element(id: _, action: .folderTapped(folder))):
                state.allFoldersPath.append(FilesFeature.State(currentDirectory: folder.url))
                return .none

            case let .allFoldersPath(.element(id: id, action: .fileTapped(file))):
                if let filesState = state.allFoldersPath[id: id] {
                    let playlist = filesState.items.compactMap { item -> AudioFile? in
                        if case let .file(audioFile) = item { return audioFile }
                        return nil
                    }
                    let folderURL = filesState.currentDirectory
                    let source: PlaylistSource? = folderURL.map { .folder($0) }
                    return .send(.player(.loadTrack(file, playlist, source)))
                }
                return .none

            case let .allFoldersPath(.element(id: id, action: .playAllTapped)):
                if let filesState = state.allFoldersPath[id: id] {
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
                // Only dismiss if edit view is NOT being shown
                if state.recording.editRecording == nil {
                    state.isRecordingSheetPresented = false
                }
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

            // MARK: - Settings → Player

            case let .settings(.setDefaultSkipDuration(duration)):
                return .send(.player(.setSkipDuration(duration)))

            case let .settings(.setDefaultPlaybackSpeed(speed)):
                return .send(.player(.setPlaybackSpeed(speed)))

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

            // Dismiss recording sheet when edit view closes
            case .recording(.editRecording(.dismiss)):
                state.isRecordingSheetPresented = false
                return .merge(
                    .send(.filesRoot(.refreshFiles)),
                    .send(.home(.loadRecentFiles))
                )

            // MARK: - Lifecycle

            case let .scenePhaseChanged(phase):
                return .send(.player(.scenePhaseChanged(phase)))

            case .player, .home, .filesRoot, .filesPath, .allFoldersPath, .settings, .recording:
                return .none
            }
        }
        .forEach(\.filesPath, action: \.filesPath) {
            FilesFeature()
        }
        .forEach(\.allFoldersPath, action: \.allFoldersPath) {
            FilesFeature()
        }
    }
}
