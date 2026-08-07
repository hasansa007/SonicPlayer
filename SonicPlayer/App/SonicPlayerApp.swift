import SwiftUI
import UIKit

@main
struct SonicPlayerApp: App {
    /// The root object, replacing `StoreOf<AppFeature>` (#19).
    ///
    /// Static for one reason: `AppDelegate` below receives quick actions from UIKit, outside any
    /// view, and `@State` cannot be static. Everything else reaches it through the environment.
    @MainActor
    static let app = AppViewModel()

    @AppStorage("appLanguage") private var appLanguage = "system"
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// The unit-test bundle is hosted by this app, so the app launches during test runs. Building
    /// the root object here would start real work — session restore, the playback clock, the audio
    /// player — inside the test's dependency context, where those clients are unimplemented. That
    /// surfaces as failures attributed to whichever test happens to be running, intermittently.
    /// `app` is a `static let` and therefore lazy, so not touching it here means it is never
    /// created under test. This survived the move off TCA unchanged and is still load-bearing.
    private static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup {
            if Self.isRunningTests {
                EmptyView()
            } else {
                AppView()
                    .environment(Self.app)
                    .environment(\.locale, resolvedLocale)
                    .environment(\.layoutDirection, resolvedLayoutDirection)
                    .id(appLanguage)
            }
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

    /// The one thing that kept a root `Store` alive until #19: UIKit delivers quick actions here,
    /// outside any view, so whatever it talks to has to be reachable statically.
    ///
    /// `target` is a parameter — resolved in the body rather than as a default argument, since a
    /// default argument is evaluated in a nonisolated context — so a test can drive this without
    /// touching `SonicPlayerApp.app`, which `isRunningTests` exists to keep uncreated under test.
    @MainActor
    func handleShortcut(_ shortcutItem: UIApplicationShortcutItem, target: AppViewModel? = nil) {
        let app = target ?? SonicPlayerApp.app
        switch QuickAction(rawValue: shortcutItem.type) {
        case .record: app.quickActionRecord()
        case .importMedia: app.quickActionImport()
        case nil: break
        }
    }
}
