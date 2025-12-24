import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable { // Keep manual Equatable.
        var selectedTab: Tab = .home
        var player = PlayerFeature.State()

        var home = HomeFeature.State()

        // Navigation Stack for Files
        var filesPath = StackState<FilesFeature.State>()
        var filesRoot = FilesFeature.State(currentDirectory: nil) // Root

        var settings = SettingsFeature.State()
        var recording = RecordingFeature.State()

        // App Mode
        enum AppMode: Hashable {
            case browsing
            case recording
        }
        
        var isRecordingMode: Bool {
            selectedTab == .recording || recording.isRecording
        }

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.selectedTab == rhs.selectedTab &&
            lhs.player == rhs.player &&
            lhs.home == rhs.home &&
            lhs.filesPath == rhs.filesPath &&
            lhs.recording == rhs.recording
            // Intentionally ignore:
            // - `filesRoot`: can be large and changes frequently while browsing.
            // - `settings`: persists via UserDefaults and doesn't need to drive app-level equality.
        }
    }

    enum Action {
        case selectTab(Tab)
        case player(PlayerFeature.Action)
        case home(HomeFeature.Action)

        // Files Actions
        case filesPath(StackAction<FilesFeature.State, FilesFeature.Action>)
        case filesRoot(FilesFeature.Action)

        case settings(SettingsFeature.Action)
        case recording(RecordingFeature.Action)

        // Refresh logic
        case checkAndRefreshSuggestions

        // Lifecycle
        case scenePhaseChanged(ScenePhase)
    }

    enum Tab: Hashable {
        case home
        case files
        case recording
        case settings
    }

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
            case let .selectTab(tab):
                let wasRecordingMode = state.isRecordingMode
                state.selectedTab = state.isTabAvailable(tab) ? tab : state.fallbackTab()
                state.ensureValidTabForCurrentMode()
                if tab == .recording && !wasRecordingMode && state.isRecordingMode {
                    return .send(.player(.suspendSession))
                }
                if tab == .home && wasRecordingMode && !state.isRecordingMode {
                    return .send(.player(.restoreSession))
                }
                return .none
                
            // Home Actions
            case .home(.libraryTapped):
                state.selectedTab = state.isTabAvailable(.files) ? .files : .home
                return .none
                
            case let .home(.folderTapped(folder)):
                state.navigateToFolderInLibrary(folder.url)
                return .none
                
            case let .home(.playTrack(track)):
                if state.player.currentTrack?.id == track.id {
                    return .send(.player(.playPauseButtonTapped))
                } else {
                    return .send(.player(.loadTrack(track, [track], .singleFile)))
                }
                
            // Handle Root Folder Navigation
            case let .filesRoot(.folderTapped(folder)):
                state.filesPath.append(FilesFeature.State(currentDirectory: folder.url))
                return .none
                
            case let .filesRoot(.fileTapped(file)):
                // Create playlist from root items
                let playlist = state.filesRoot.items.compactMap { item -> AudioFile? in
                    if case let .file(audioFile) = item { return audioFile }
                    return nil
                }
                return .send(.player(.loadTrack(file, playlist, .singleFile)))

            // Handle Stack Navigation
            case let .filesPath(.element(id: _, action: .folderTapped(folder))):
                state.filesPath.append(FilesFeature.State(currentDirectory: folder.url))
                return .none

            case let .filesPath(.element(id: id, action: .fileTapped(file))):
                // Create playlist from current folder items
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
                
            case .scenePhaseChanged:
                // Forward scene phase to player for persistence
                return .send(.player(.scenePhaseChanged))
                
            case let .settings(.setDefaultSkipDuration(duration)):
                return .send(.player(.setSkipDuration(duration)))

            case let .settings(.setDefaultPlaybackSpeed(speed)):
                return .send(.player(.setPlaybackSpeed(speed)))

            case .recording(.recordingStarted),
                 .recording(.recordingStopped),
                 .recording(.recordingFailed):
                state.ensureValidTabForCurrentMode()
                return .none

            case .player(.trackLoaded), .player(.sessionLoaded):
                state.home.lastPlayedTrack = state.player.currentTrack
                state.home.isPlaying = state.player.isPlaying
                state.home.playbackProgress = state.player.progress
                return .send(.checkAndRefreshSuggestions)

            case .checkAndRefreshSuggestions:
                // Check if playing from a suggested folder
                if let playlistSource = state.player.currentPlaylistSource,
                   case let .folder(folderURL) = playlistSource {
                    // Standardize URLs for comparison
                    let standardizedFolderURL = folderURL.standardizedFileURL
                    let isInSuggestions = state.home.suggestedFolders.contains {
                        $0.url.standardizedFileURL == standardizedFolderURL
                    }
                    if isInSuggestions {
                        return .send(.home(.refreshSuggestions(excludingFolderURL: folderURL)))
                    }
                }
                return .none

            case .player(.playPauseButtonTapped):
                // This action flips the boolean in PlayerFeature immediately (optimistic UI)
                // We should reflect that in Home
                state.home.isPlaying = state.player.isPlaying
                return .none

            case .player(.timeUpdate):
                // Update playback progress for home view
                state.home.playbackProgress = state.player.progress
                return .none
                
            case .player(.clearSession): // New: Reset UpNext if player session clears
                state.home.lastPlayedTrack = nil
                state.home.isPlaying = false
                state.home.playbackProgress = 0
                return .none

            case .player, .home, .filesRoot, .filesPath, .settings, .recording:
                return .none
            }
        }
        .forEach(\.filesPath, action: \.filesPath) {
            FilesFeature()
        }
    }
}

private extension AppFeature.State {
    func isTabAvailable(_ tab: AppFeature.Tab) -> Bool {
        if !isRecordingMode { return true }
        if recording.isRecording {
            return tab == .recording || tab == .settings
        }
        return tab != .files
    }

    mutating func ensureValidTabForCurrentMode() {
        if !isTabAvailable(selectedTab) {
            selectedTab = fallbackTab()
        }
        if isRecordingMode {
            filesPath.removeAll()
        }
    }

    mutating func navigateToFolderInLibrary(_ folderURL: URL) {
        guard isTabAvailable(.files) else {
            selectedTab = fallbackTab()
            return
        }
        selectedTab = .files
        filesPath.removeAll()
        filesPath.append(FilesFeature.State(currentDirectory: folderURL))
    }

    func fallbackTab() -> AppFeature.Tab {
        if isRecordingMode && recording.isRecording {
            return .recording
        }
        return .home
    }
}
