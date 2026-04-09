import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct HomeFeature {
    @ObservableState
    struct State: Equatable {
        var lastPlayedTrack: AudioFile?
        var isPlaying: Bool = false
        var playbackProgress: Double = 0
        var recentFiles: [AudioFile] = []
        var isShowingAllCollections: Bool = false
    }

    enum Action {
        case loadRecentFiles
        case recentFilesLoaded([AudioFile])
        case fileTapped(AudioFile)
        case playTrack(AudioFile)
        case togglePlayPause
        case importTapped
        case newCollectionTapped
        case viewAllCollectionsTapped
        case dismissAllCollections
    }

    @Dependency(\.fileManager) var fileManager

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .loadRecentFiles:
                return .run { send in
                    let files = try await loadRecentFiles(fileManager: fileManager)
                    await send(.recentFilesLoaded(files))
                }

            case let .recentFilesLoaded(files):
                state.recentFiles = files
                return .none

            case .viewAllCollectionsTapped:
                state.isShowingAllCollections = true
                return .none

            case .dismissAllCollections:
                state.isShowingAllCollections = false
                return .none

            case .fileTapped, .playTrack, .togglePlayPause, .importTapped, .newCollectionTapped:
                return .none
            }
        }
    }
}

private func loadRecentFiles(fileManager: FileManagerClient) async throws -> [AudioFile] {
    var allFiles: [AudioFile] = []
    var seenNames: Set<String> = []
    try await collectFiles(from: nil, into: &allFiles, seenNames: &seenNames, fileManager: fileManager)
    allFiles.sort { $0.creationDate > $1.creationDate }
    return Array(allFiles.prefix(10))
}

private func collectFiles(from directory: URL?, into files: inout [AudioFile], seenNames: inout Set<String>, fileManager: FileManagerClient) async throws {
    let items = try await fileManager.listItems(directory)
    for item in items {
        switch item {
        case .file(let audioFile):
            let name = audioFile.url.lastPathComponent
            if !seenNames.contains(name) {
                seenNames.insert(name)
                files.append(audioFile)
            }
        case .folder(let folder):
            try await collectFiles(from: folder.url, into: &files, seenNames: &seenNames, fileManager: fileManager)
        }
    }
}
