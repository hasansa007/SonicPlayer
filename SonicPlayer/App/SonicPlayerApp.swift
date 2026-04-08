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
                .environment(\.locale, resolvedLocale)
                .environment(\.layoutDirection, resolvedLayoutDirection)
                .id(appLanguage)
        }
    }

    private var resolvedLayoutDirection: LayoutDirection {
        let rtlLanguages = ["ar", "he", "fa", "ur"]
        let lang = resolvedLocale.language.languageCode?.identifier ?? ""
        return rtlLanguages.contains(lang) ? .rightToLeft : .leftToRight
    }

    private var resolvedLocale: Locale {
        if appLanguage != "system" {
            return Locale(identifier: appLanguage)
        }

        let preferredIdentifier = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        return Locale(identifier: preferredIdentifier)
    }
}
