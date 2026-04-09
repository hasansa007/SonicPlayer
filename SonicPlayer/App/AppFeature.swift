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


        var settings = SettingsFeature.State()
        var recording = RecordingFeature.State()

        // Onboarding
        var onboarding: OnboardingFeature.State?

        // Sheets
        var isRecordingSheetPresented: Bool = false
        var isSettingsSheetPresented: Bool = false
        var isImportSheetPresented: Bool = false

        init() {
            let hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
            if !hasSeenOnboarding {
                self.onboarding = OnboardingFeature.State()
            }
        }

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.player == rhs.player &&
            lhs.home == rhs.home &&
            lhs.filesPath == rhs.filesPath &&
            lhs.onboarding == rhs.onboarding &&
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

        case settings(SettingsFeature.Action)
        case recording(RecordingFeature.Action)
        case onboarding(OnboardingFeature.Action)

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

        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }

        Scope(state: \.recording, action: \.recording) {
            RecordingFeature()
        }

        Reduce { state, action in
            switch action {

            // MARK: - Onboarding

            case .onboarding(.getStartedTapped):
                UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                state.onboarding = nil
                return .none

            case let .onboarding(onboardingAction):
                guard var onboardingState = state.onboarding else { return .none }
                let onboardingReducer = OnboardingFeature()
                _ = onboardingReducer.reduce(into: &onboardingState, action: onboardingAction)
                state.onboarding = onboardingState
                return .none

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

            case .home(.dismissAllCollections):
                state.home.isShowingAllCollections = false
                return .none

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

            // MARK: - Quick Actions

            case .quickActionRecord:
                state.isRecordingSheetPresented = true
                return .none

            case .quickActionImport:
                state.isImportSheetPresented = true
                return .none

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

            // Clear player if currently playing track is deleted (file or parent folder)
            case .filesRoot(.alert(.presented(.confirmDelete))):
                if let currentTrack = state.player.currentTrack {
                    let trackPath = currentTrack.url.path
                    let shouldClear = state.filesRoot.selectedItems.contains { item in
                        item.url == currentTrack.url || trackPath.hasPrefix(item.url.path + "/")
                    }
                    if shouldClear {
                        return .send(.player(.clearSession))
                    }
                }
                return .none

            case let .filesPath(.element(id: id, action: .alert(.presented(.confirmDelete)))):
                if let currentTrack = state.player.currentTrack,
                   let filesState = state.filesPath[id: id] {
                    let trackPath = currentTrack.url.path
                    let shouldClear = filesState.selectedItems.contains { item in
                        item.url == currentTrack.url || trackPath.hasPrefix(item.url.path + "/")
                    }
                    if shouldClear {
                        return .send(.player(.clearSession))
                    }
                }
                return .none

            case .player, .home, .filesRoot, .filesPath, .settings, .recording:
                return .none
            }
        }
        .forEach(\.filesPath, action: \.filesPath) {
            CollectionsFeature()
        }
    }
}
