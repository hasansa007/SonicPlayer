import ComposableArchitecture
import Foundation

@Reducer
struct OnboardingFeature {
    @ObservableState
    struct State: Equatable {
        var currentPage: Int = 0
        let totalPages = 4
    }

    enum Action {
        case nextPage
        case setPage(Int)
        case getStartedTapped
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .nextPage:
                if state.currentPage < state.totalPages - 1 {
                    state.currentPage += 1
                }
                return .none
            case let .setPage(page):
                state.currentPage = page
                return .none
            case .getStartedTapped:
                return .none // Handled by parent
            }
        }
    }
}
