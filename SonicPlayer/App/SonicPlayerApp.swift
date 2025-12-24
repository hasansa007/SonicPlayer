import ComposableArchitecture
import SwiftUI

@main
struct SonicPlayerApp: App {
    @MainActor
    static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }
    @AppStorage("appLanguage") private var appLanguage = "system"

    var body: some Scene {
        WindowGroup {
            AppView(store: Self.store)
                .environment(\.locale, appLanguage == "system" ? Locale.current : Locale(identifier: appLanguage))
                .id(appLanguage)
        }
    }
}
