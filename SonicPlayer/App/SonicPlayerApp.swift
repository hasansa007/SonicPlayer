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

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        Self.clearLegacyLanguageOverride()
    }

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
                // No `\.locale`, no `\.layoutDirection`, no `.id(appLanguage)` (#68). SwiftUI
                // derives both from the localization `Bundle.main` resolved at launch, and that is
                // now the only thing that decides the language — so an override could only ever
                // disagree with the strings on screen. The `.id()` existed to discard the view tree
                // when the in-app picker changed the language mid-session, which nothing can do any
                // more.
                AppView()
                    .environment(Self.app)
            }
        }
    }

    /// Clears the `AppleLanguages` override the old in-app picker wrote (#68), and **only** that
    /// one (#70).
    ///
    /// Without this, anyone who chose a language before that picker was removed stays pinned to it
    /// with no way back: the control that set it is gone, and the value sits in the app's own
    /// defaults. So the key has to go — but it cannot go unconditionally.
    ///
    /// **`AppleLanguages` is not ours alone.** It is the same key iOS's per-app *Preferred
    /// Language* writes into — the control this app now sends people to. Deleting it on sight would
    /// wipe a live choice the user made in Settings, on the first launch after updating, once and
    /// unrepairably. That is worse than the bug it was meant to fix.
    ///
    /// **Which keys may go is `LegacyLanguageOverride`'s decision, and it is tested.** The
    /// obvious rule — "`appLanguage` exists, so the override is ours" — is wrong in the exact way
    /// this function exists to prevent, and shipped twice before review caught it. That is why the
    /// arithmetic is out of here.
    ///
    /// Read through `persistentDomain` rather than `object(forKey:)`, which searches
    /// `NSArgumentDomain` first. This app already takes launch arguments (`ScreenshotMode`), so a
    /// stray `-appLanguage` would otherwise conjure a phantom key and take a real system language
    /// down with it — while `removeObject` could not even clear the phantom.
    ///
    /// The flag is set **last**, so an interrupted launch retries instead of latching a migration
    /// that never ran. An earlier version set it first to avoid re-checking forever; that traded
    /// at-least-once for two dictionary lookups, which was the wrong way round.
    ///
    /// Skipped under test: `init()` runs before the `isRunningTests` guard on `body`, so without
    /// this the app's test host would mutate `UserDefaults.standard` on every run — the global
    /// mutable state `CLAUDE.md` singles out, and exactly what `isRunningTests` exists to prevent.
    private static func clearLegacyLanguageOverride() {
        guard !isRunningTests else { return }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didClearLegacyLanguageOverride") else { return }

        let persisted = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        for key in LegacyLanguageOverride.keysToRemove(from: persisted) {
            defaults.removeObject(forKey: key)
        }

        defaults.set(true, forKey: "didClearLegacyLanguageOverride")
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
