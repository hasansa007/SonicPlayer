import ComposableArchitecture
import SwiftUI

@Reducer
struct FileRowFeature {
    @ObservableState
    struct State: Identifiable, Equatable {
        var id: UUID { file.id }
        let file: AudioFile
        var isSelected: Bool = false
        var creationDate: Date? // Add creationDate
    }

    enum Action {
        case tapped
        case moveTapped
        case renameTapped
        case editTapped
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

            case .editTapped:
                return .none // Handled by parent

            case .deleteTapped:
                return .none // Handled by parent

            case .toggleSelection:
                return .none // Handled by parent
            }
        }
    }
}
