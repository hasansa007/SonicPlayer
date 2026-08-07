import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        // File browser (home)
        var filesPath = StackState<CollectionsFeature.State>()
        var filesRoot = CollectionsFeature.State(currentDirectory: nil)

        // Sheets
        var isRecordingSheetPresented: Bool = false
        var isSettingsSheetPresented: Bool = false
        var isImportSheetPresented: Bool = false

        /// Outbound commands for the view models that no longer live in the store (#15, #16).
        ///
        /// Player and Home are `@Observable` classes owned by `AppView`, so this reducer cannot
        /// call them. Several of its cases still need to — playing a tapped file needs the
        /// playlist, which is computed from `filesRoot.items` and only exists here.
        ///
        /// `AppView` drains this and sends `.commandsHandled`. **Temporary**: #19 turns
        /// `AppFeature` into a coordinator that holds the view models directly, and this goes
        /// with it.
        var commands: [AppCommand] = []

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.filesPath == rhs.filesPath &&
            lhs.isRecordingSheetPresented == rhs.isRecordingSheetPresented &&
            lhs.isSettingsSheetPresented == rhs.isSettingsSheetPresented &&
            lhs.isImportSheetPresented == rhs.isImportSheetPresented &&
            lhs.commands == rhs.commands
        }
    }

    /// One-way requests from the reducer to `PlayerViewModel` / `HomeViewModel`.
    enum AppCommand: Equatable {
        case play(AudioFile, [AudioFile]?, PlaylistSource?)
        /// Recording takes over the shared AVPlayer, so playback stops first.
        case pauseIfPlaying
        /// The check needs the playing track, which lives on the view model now — so the view
        /// model performs it. See #22 for why the items travel rather than being read back.
        case clearSessionIfAffected([URL])
        case refreshRecents
    }

    enum Action {
        // File browser
        case filesPath(StackAction<CollectionsFeature.State, CollectionsFeature.Action>)
        case filesRoot(CollectionsFeature.Action)

        // Sheets
        case recordButtonTapped
        case dismissRecordingSheet
        case settingsTapped
        case dismissSettings
        case importFiles([URL])
        case importTapped
        case dismissImportSheet

        // From Home, which is a view model now — these need reducer state, so they stay actions
        case viewAllCollectionsTapped
        case deleteRecentFile(AudioFile)
        case editRecentFile(AudioFile)
        case moveRecentFile(AudioFile)

        // Quick Actions
        case quickActionRecord
        case quickActionImport

        case commandsHandled
    }

    @Dependency(\.fileManager) var fileManager

    var body: some ReducerOf<Self> {
        Scope(state: \.filesRoot, action: \.filesRoot) {
            CollectionsFeature()
        }

        Reduce { state, action in
            switch action {

            // MARK: - From Home

            case .viewAllCollectionsTapped:
                state.filesPath.append(CollectionsFeature.State(currentDirectory: nil))
                return .none

            case let .deleteRecentFile(file):
                state.filesRoot.selectedItems = [.file(file)]
                return .send(.filesRoot(.deleteSelectedTapped))

            case let .editRecentFile(file):
                state.filesRoot.audioToEdit = file
                return .none

            case let .moveRecentFile(file):
                state.filesRoot.itemsToMove = [.file(file)]
                state.filesRoot.isShowingCollectionPicker = true
                return .none

            case .importTapped:
                state.isImportSheetPresented = true
                return .none

            // Refresh home after edit view dismissal, so recents reflect any saved changes
            case .filesRoot(.editAudioDismissed):
                state.commands.append(.refreshRecents)
                return .send(.filesRoot(.refreshFiles))

            // MARK: - File Browser

            case let .filesRoot(.collectionTapped(folder)):
                state.filesPath.append(CollectionsFeature.State(currentDirectory: folder.url))
                return .none

            case let .filesRoot(.fileTapped(file)):
                state.commands.append(.play(file, state.filesRoot.audioFiles, .singleFile))
                return .none

            case .filesRoot(.playAllTapped):
                let playlist = state.filesRoot.audioFiles
                guard let first = playlist.first else { return .none }
                state.commands.append(.play(first, playlist, .singleFile))
                return .none

            case let .filesPath(.element(id: _, action: .collectionTapped(folder))):
                state.filesPath.append(CollectionsFeature.State(currentDirectory: folder.url))
                return .none

            case let .filesPath(.element(id: id, action: .fileTapped(file))):
                guard let filesState = state.filesPath[id: id] else { return .none }
                let source: PlaylistSource? = filesState.currentDirectory.map { .folder($0) }
                state.commands.append(.play(file, filesState.audioFiles, source))
                return .none

            case let .filesPath(.element(id: id, action: .playAllTapped)):
                guard
                    let filesState = state.filesPath[id: id],
                    let first = filesState.audioFiles.first
                else { return .none }
                let source: PlaylistSource? = filesState.currentDirectory.map { .folder($0) }
                state.commands.append(.play(first, filesState.audioFiles, source))
                return .none

            // MARK: - Sheets

            case .recordButtonTapped:
                // Recording takes over the shared AVPlayer
                state.commands.append(.pauseIfPlaying)
                state.isRecordingSheetPresented = true
                return .none

            // Sent both when the sheet is dismissed and when the recorder finishes saving or
            // discarding. Discarding an unsaved recording moved to `RecordingViewModel`, which is
            // the only thing that can still see whether one is in progress.
            case .dismissRecordingSheet:
                state.isRecordingSheetPresented = false
                state.commands.append(.refreshRecents)
                return .send(.filesRoot(.refreshFiles))

            case .settingsTapped:
                state.isSettingsSheetPresented = true
                return .none

            case .dismissSettings:
                state.isSettingsSheetPresented = false
                return .none

            case let .importFiles(urls):
                state.isImportSheetPresented = false
                state.commands.append(.refreshRecents)
                return .send(.filesRoot(.importFiles(urls)))

            case .dismissImportSheet:
                state.isImportSheetPresented = false
                return .none

            // MARK: - Quick Actions

            case .quickActionRecord:
                state.isRecordingSheetPresented = true
                return .none

            case .quickActionImport:
                state.isImportSheetPresented = true
                return .none

            // MARK: - Player coordination

            // The items travel in the action rather than being read back out of state, because
            // CollectionsFeature clears its selection before this runs — #22. The affected-track
            // check itself now lives on PlayerViewModel, which is where the track is.
            case let .filesRoot(.willRemoveItems(items)),
                 let .filesPath(.element(id: _, action: .willRemoveItems(items))):
                state.commands.append(.clearSessionIfAffected(items.map(\.url)))
                return .none

            // After files are reloaded (after any mutation), refresh home recents too
            case .filesRoot(.itemsLoaded):
                state.commands.append(.refreshRecents)
                return .none

            case .commandsHandled:
                state.commands.removeAll()
                return .none

            case .filesRoot, .filesPath:
                return .none
            }
        }
        .forEach(\.filesPath, action: \.filesPath) {
            CollectionsFeature()
        }
    }
}
