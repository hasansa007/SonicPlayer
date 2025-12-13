import ComposableArchitecture
import SwiftUI
import UIKit

@Reducer
struct FolderPickerFeature {
    @ObservableState
    struct State: Identifiable, Equatable {
        var id: String { folder?.id.absoluteString ?? "root" } // Corrected: Use absoluteString
        let folder: Folder? // nil is root
        var folderPath: String = ""
        var artwork: UIImage?
        var colors: [Color] = []
        var isRoot: Bool { folder == nil }

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.id == rhs.id &&
            lhs.folder == rhs.folder &&
            lhs.folderPath == rhs.folderPath &&
            lhs.colors == rhs.colors &&
            lhs.isRoot == rhs.isRoot
            // Exclude artwork from comparison
        }
    }

    enum Action {
        case onAppear
        case artworkLoaded(UIImage?, [Color])
        case tapped
    }

    @Dependency(\.artworkClient) var artworkClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard let folder = state.folder else { return .none }
                let url = folder.url
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
            }
        }
    }
}
