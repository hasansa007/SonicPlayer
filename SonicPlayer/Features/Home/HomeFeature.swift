import ComposableArchitecture
import Foundation
import UIKit
import SwiftUI

@Reducer
struct HomeFeature {
    @ObservableState
    struct State: Equatable {
        var recentFolders: [Folder] = []
        var suggestedFolders: [Folder] = []
        var lastPlayedTrack: AudioFile?
        var isPlaying: Bool = false
        var playbackProgress: Double = 0 // 0.0 to 1.0

        // Track shown folders for rotation
        var shownFolderURLs: Set<URL> = []
        var allAvailableFolders: [Folder] = []
        var hasRefreshedSuggestions: Bool = false

        // Artwork cache
        var artworkCache: [URL: UIImage] = [:]
        var colorCache: [URL: [Color]] = [:]

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.recentFolders == rhs.recentFolders &&
            lhs.suggestedFolders == rhs.suggestedFolders &&
            lhs.lastPlayedTrack == rhs.lastPlayedTrack &&
            lhs.isPlaying == rhs.isPlaying &&
            lhs.playbackProgress == rhs.playbackProgress &&
            lhs.shownFolderURLs == rhs.shownFolderURLs &&
            lhs.allAvailableFolders == rhs.allAvailableFolders &&
            lhs.hasRefreshedSuggestions == rhs.hasRefreshedSuggestions &&
            // Exclude artworkCache from comparison as UIImage is not Equatable
            lhs.colorCache == rhs.colorCache
        }
    }

    enum Action {
        case onAppear
        case loadData
        case dataLoaded([Folder], [Folder], [Folder]) // Recent, Suggested, All
        case folderTapped(Folder)
        case libraryTapped
        case playTrack(AudioFile)
        case updatePlaybackStatus(Bool)
        case refreshSuggestions(excludingFolderURL: URL)

        // Artwork actions
        case loadArtwork(URL, isFolder: Bool)
        case artworkLoaded(URL, UIImage?)
        case colorsLoaded(URL, [Color])
    }

    @Dependency(\.fileManager) var fileManager
    @Dependency(\.artworkClient) var artworkClient
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.loadData)

            case .loadData:
                return .run { send in
                    do {
                        let rootItems = try await fileManager.listItems(nil)
                        let folders = rootItems.compactMap { item -> Folder? in
                            if case let .folder(f) = item { return f }
                            return nil
                        }

                        // Mock categorization
                        let recent = Array(folders.prefix(3))
                        let suggested = Array(folders.dropFirst(3).prefix(5))

                        await send(.dataLoaded(recent, suggested, folders))
                    } catch {
                        print("Failed to load home data: \(error)")
                    }
                }

            case let .dataLoaded(recent, suggested, allFolders):
                // Always update allAvailableFolders (file system may have changed)
                state.allAvailableFolders = allFolders

                // Only update suggestions if they haven't been manually refreshed
                if !state.hasRefreshedSuggestions {
                    state.recentFolders = recent
                    state.suggestedFolders = suggested
                    // Mark initial suggestions as shown (use standardized URLs)
                    state.shownFolderURLs = Set(suggested.map { $0.url.standardizedFileURL })
                }
                return .none
                
            case .folderTapped:
                return .none
                
            case .libraryTapped:
                return .none
                
            case .playTrack:
                return .none
                
            case let .updatePlaybackStatus(isPlaying):
                state.isPlaying = isPlaying
                return .none

            case let .refreshSuggestions(excludingFolderURL):
                // Standardize URL for consistent comparison
                let standardizedURL = excludingFolderURL.standardizedFileURL

                // Mark as shown
                state.shownFolderURLs.insert(standardizedURL)

                // Remove from suggestions (create new array instead of mutating)
                var updatedSuggestions = state.suggestedFolders.filter { $0.url.standardizedFileURL != standardizedURL }

                // Build available pool (exclude only shown folders - recent folders can be suggested)
                let availableForSuggestion = state.allAvailableFolders.filter { folder in
                    !state.shownFolderURLs.contains(folder.url.standardizedFileURL)
                }

                // Rotate in new suggestions to reach 5 total
                let needed = updatedSuggestions.count + 1

                if needed > 0 {
                    if !availableForSuggestion.isEmpty {
                        let newSuggestions = Array(availableForSuggestion.prefix(needed))
                        updatedSuggestions.append(contentsOf: newSuggestions)
                        newSuggestions.forEach { state.shownFolderURLs.insert($0.url.standardizedFileURL) }
                    } else {
                        // Pool exhausted - reset and try again
                        state.shownFolderURLs = [standardizedURL]

                        // Get fresh pool
                        let freshPool = state.allAvailableFolders.filter { folder in
                            folder.url.standardizedFileURL != standardizedURL
                        }

                        if !freshPool.isEmpty {
                            let newSuggestions = Array(freshPool.prefix(needed))
                            updatedSuggestions.append(contentsOf: newSuggestions)
                            newSuggestions.forEach { state.shownFolderURLs.insert($0.url.standardizedFileURL) }
                        }
                    }
                }

                // Replace the entire array to trigger observation
                state.suggestedFolders = updatedSuggestions
                // Mark that suggestions have been manually refreshed
                state.hasRefreshedSuggestions = true
                return .none

            case let .loadArtwork(url, isFolder):
                // Check if already cached
                if state.artworkCache[url] != nil && state.colorCache[url] != nil {
                    return .none
                }

                return .run { send in
                    async let artwork = isFolder ?
                        await artworkClient.getFolderArtwork(url) :
                        await artworkClient.getArtwork(url)
                    async let colors = await artworkClient.getColors(url, isFolder, nil)

                    await send(.artworkLoaded(url, await artwork))
                    await send(.colorsLoaded(url, await colors))
                }

            case let .artworkLoaded(url, artwork):
                state.artworkCache[url] = artwork
                return .none

            case let .colorsLoaded(url, colors):
                state.colorCache[url] = colors
                return .none
            }
        }
    }
}
