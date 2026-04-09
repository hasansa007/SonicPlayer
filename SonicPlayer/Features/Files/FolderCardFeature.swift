import ComposableArchitecture
import SwiftUI
import UIKit

@Reducer
struct CollectionItemCardFeature {
    @ObservableState
    struct State: Identifiable, Equatable {
        var id: URL { folder.id }
        let folder: CollectionItem
        var artwork: UIImage?
        var colors: [Color] = []
        var isSelected: Bool = false

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.id == rhs.id &&
            lhs.folder == rhs.folder &&
            lhs.colors == rhs.colors &&
            lhs.isSelected == rhs.isSelected
            // Exclude artwork from comparison as UIImage is not Equatable
        }
    }

    enum Action {
        case onAppear
        case artworkLoaded(UIImage?, [Color])
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
                let url = state.folder.url
                return .run { send in
                    async let artwork = artworkClient.getFolderArtwork(url)
                    async let colors = artworkClient.getColors(url, true, Color.sonicTealColors)
                    await send(.artworkLoaded(await artwork, await colors))
                }

            case let .artworkLoaded(artwork, colors):
                state.artwork = artwork
                state.colors = colors
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
