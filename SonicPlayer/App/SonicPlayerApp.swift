import ComposableArchitecture
import SwiftUI
import UIKit

@main
struct SonicPlayerApp: App {
    @MainActor
    static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }
    @AppStorage("appLanguage") private var appLanguage = "system"
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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

// MARK: - App Delegate for Quick Actions

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        handleShortcut(shortcutItem)
        completionHandler(true)
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcutItem = options.shortcutItem {
            handleShortcut(shortcutItem)
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        return config
    }

    @MainActor
    private func handleShortcut(_ shortcutItem: UIApplicationShortcutItem) {
        switch shortcutItem.type {
        case "com.hasan.sonicplayer.record":
            SonicPlayerApp.store.send(.quickActionRecord)
        case "com.hasan.sonicplayer.import":
            SonicPlayerApp.store.send(.quickActionImport)
        default:
            break
        }
    }
}
