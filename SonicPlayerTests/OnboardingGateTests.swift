import Foundation
import Testing
@testable import SonicPlayer

/// **The key bump is the behaviour, so it is what gets pinned** (#102).
///
/// Onboarding was rewritten around the wheel — the Next button *is* a `DialRing` now, the pages sit
/// on the app's own card, and the copy names gestures instead of features. Someone who completed the
/// old carousel was taught an app that no longer exists, so `seenKey` moved from
/// `hasSeenOnboarding_v2` to `_v3` and they meet the new one once.
///
/// The failure this guards against is a tidy-up, not a typo: the obvious-looking "migrate the old
/// flag forward" or "read either key" change reads as harmless and silently restores the exact
/// suppression the bump exists to defeat. The first test fails if anyone writes it.
///
/// Each test gets its own `UserDefaults` suite rather than `.standard` — these run in parallel with
/// everything else, and `SettingsViewModel` is in the same process.
@MainActor
struct OnboardingGateTests {

    private func defaults(_ name: String) -> UserDefaults {
        let suite = UserDefaults(suiteName: "onboarding.gate.\(name)")!
        suite.removePersistentDomain(forName: "onboarding.gate.\(name)")
        return suite
    }

    @Test func completingTheOldOnboardingDoesNotSuppressTheNewOne() {
        let store = defaults(#function)
        store.set(true, forKey: "hasSeenOnboarding_v2")

        #expect(OnboardingViewModel.ifNeeded(defaults: store) != nil)
    }

    @Test func completingThisOnboardingSuppressesIt() {
        let store = defaults(#function)

        OnboardingViewModel.markSeen(defaults: store)

        #expect(OnboardingViewModel.ifNeeded(defaults: store) == nil)
    }

    @Test func aFreshInstallSeesIt() {
        #expect(OnboardingViewModel.ifNeeded(defaults: defaults(#function)) != nil)
    }
}
