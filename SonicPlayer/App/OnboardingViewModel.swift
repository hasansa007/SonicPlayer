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

    private static let seenKey = "hasSeenOnboarding_v2"

    var currentPage = 0
    let totalPages = 5

    /// Set by the composition root: persists the flag and drops this view model.
    var onGetStarted: () -> Void = {}

    /// `nil` when onboarding has already been completed — the caller shows nothing.
    static func ifNeeded(defaults: UserDefaults = .standard) -> OnboardingViewModel? {
        // Screenshot runs must never land on onboarding — previously done by nilling the state
        // in ScreenshotMode.buildAppState.
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
