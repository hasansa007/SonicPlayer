import ComposableArchitecture
import Foundation

/// What is left of the root reducer after #18 — three sheet flags and the quick actions that set
/// them. Everything else is a view model owned by `AppView`.
///
/// **The `AppCommand` channel is gone.** It existed because a few reducer cases needed to reach the
/// player, and the one that justified it — playing a tapped file — needed the queue, which was
/// computed from `filesRoot.items` and lived only in the store. `CollectionsViewModel` now passes
/// its own file list out through `onPlay`, so there is nothing left for the channel to carry.
///
/// #19 deletes this type outright. It survives this slice only because the quick actions arrive
/// through `AppDelegate`, which holds the store — moving that is #19's to do.
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var isRecordingSheetPresented: Bool = false
        var isSettingsSheetPresented: Bool = false
        var isImportSheetPresented: Bool = false
    }

    enum Action {
        case recordButtonTapped
        case dismissRecordingSheet
        case settingsTapped
        case dismissSettings
        case importTapped
        case dismissImportSheet

        case quickActionRecord
        case quickActionImport
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .recordButtonTapped, .quickActionRecord:
                state.isRecordingSheetPresented = true
                return .none

            case .dismissRecordingSheet:
                state.isRecordingSheetPresented = false
                return .none

            case .settingsTapped:
                state.isSettingsSheetPresented = true
                return .none

            case .dismissSettings:
                state.isSettingsSheetPresented = false
                return .none

            case .importTapped, .quickActionImport:
                state.isImportSheetPresented = true
                return .none

            case .dismissImportSheet:
                state.isImportSheetPresented = false
                return .none
            }
        }
    }
}
