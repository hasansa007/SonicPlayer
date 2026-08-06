import ComposableArchitecture
import SwiftUI

@Reducer
struct CollectionItemCardFeature {
    @ObservableState
    struct State: Identifiable, Equatable {
        var id: URL { folder.id }
        let folder: CollectionItem
        var isSelected: Bool = false
    }

    enum Action {
        case tapped
        case moveTapped
        case renameTapped
        case deleteTapped
        case toggleSelection
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
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
