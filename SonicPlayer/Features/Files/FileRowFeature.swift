import ComposableArchitecture
import SwiftUI
import UIKit
import AVFoundation // For URL.resourceValues

@Reducer
struct FileRowFeature {
    @ObservableState
    struct State: Identifiable, Equatable {
        var id: UUID { file.id }
        let file: AudioFile
        var artwork: UIImage?
        var colors: [Color] = []
        var isSelected: Bool = false
        var creationDate: Date? // Add creationDate

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.id == rhs.id &&
            lhs.file == rhs.file &&
            lhs.colors == rhs.colors &&
            lhs.isSelected == rhs.isSelected &&
            lhs.creationDate == rhs.creationDate
            // Exclude artwork from comparison as UIImage is not Equatable
        }
    }

    enum Action {
        case onAppear
        case artworkLoaded(UIImage?, [Color])
        case dateLoaded(Date) // New action for loading date
        case tapped
        case moveTapped
        case renameTapped
        case deleteTapped
        case toggleSelection
    }

    @Dependency(\.artworkClient) var artworkClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let url = state.file.url
                return .run { send in
                    // Load artwork and colors
                    async let artwork = artworkClient.getArtwork(url)
                    async let colors = artworkClient.getColors(url, false, Color.sonicTealColors)
                    
                    // Load creation date
                    if let resources = try? url.resourceValues(forKeys: [.creationDateKey]),
                       let date = resources.creationDate {
                        await send(.dateLoaded(date))
                    }

                    await send(.artworkLoaded(await artwork, await colors))
                }

            case let .artworkLoaded(artwork, colors):
                state.artwork = artwork
                state.colors = colors
                return .none

            case let .dateLoaded(date):
                state.creationDate = date
                return .none

            case .tapped:
                return .none // Handled by parent

            case .moveTapped:
                return .none // Handled by parent

            case .renameTapped:
                return .none // Handled by parent

            case .deleteTapped:
                return .none // Handled by parent
                
            case .toggleSelection:
                return .none // Handled by parent
            }
        }
    }
}
