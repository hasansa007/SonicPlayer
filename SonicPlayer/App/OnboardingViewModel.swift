import Observation
import Foundation

/// Replaces `OnboardingFeature` (#14).
///
/// Second-simplest reducer in the app after Settings, and it validates the one pattern Settings
/// does not: presentation driven by optional state. Onboarding is shown while the view model
/// exists and dismissed by discarding it, which is what `store.onboarding != nil` did before.
///
/// The "seen" flag is read here rather than in `AppFeature.State.init()`, so nothing about
/// onboarding remains in the root reducer.
@MainActor
@Observable
final class OnboardingViewModel {

    /// **Bumped when the onboarding changes enough to be worth seeing again** (#102).
    ///
    /// `_v2` marked the five feature pages. `_v3` is the wheel: the Next button is the dial itself,
    /// the content sits on the app's own card, and every page names a gesture rather than a feature.
    /// Someone who saw `_v2` was taught an app that no longer exists, so they get this once.
    ///
    /// The old key is deliberately NOT read or migrated. Reading it would let a `_v2` flag suppress
    /// `_v3`, which is exactly the case this bump exists to defeat — and the flag is one boolean, so
    /// leaving it behind costs nothing. Bump again the next time the first run stops being true.
    private static let seenKey = "hasSeenOnboarding_v3"

    var currentPage = 0
    let totalPages = 5

    /// Set by the composition root: persists the flag and drops this view model.
    var onGetStarted: () -> Void = {}

    /// `nil` when onboarding has already been completed — the caller shows nothing.
    static func ifNeeded(defaults: UserDefaults = .standard) -> OnboardingViewModel? {
        // Screenshot runs must never land on onboarding — previously done by nilling the state
        // in ScreenshotMode.buildAppState.
        // A screenshot run lands on onboarding only when it is asked for by name; every other
        // target must never see it (#102).
        if ScreenshotMode.targetScreen == .onboarding {
            let model = OnboardingViewModel()
            model.currentPage = max(0, min(model.totalPages - 1, ScreenshotMode.page))
            return model
        }
        guard !ScreenshotMode.isEnabled else { return nil }
        return defaults.bool(forKey: seenKey) ? nil : OnboardingViewModel()
    }

    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: seenKey)
    }

    func nextPage() {
        if currentPage < totalPages - 1 {
            currentPage += 1
        }
    }

    func setPage(_ page: Int) {
        currentPage = page
    }

    func getStartedTapped() {
        onGetStarted()
    }
}
