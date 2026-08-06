import Observation
import SwiftUI
import UIKit

/// Replaces `SettingsFeature` — the first reducer converted in the TCA → MVVM migration (#13).
///
/// Deliberately the first: zero dependencies, zero effects, every former action a synchronous
/// mutation. Whatever goes wrong in the view-rewiring pattern goes wrong here, where nothing
/// else can be blamed.
///
/// The view model lives outside the store, owned by `AppView` as `@State`, because `AppFeature`
/// is still a reducer and a reference type cannot sit in its value-type `State`. The two changes
/// that must reach the player travel through closures the composition root wires up — the same
/// shape `willRemoveItems` uses in #22, and the one #19 generalises.
@MainActor
@Observable
final class SettingsViewModel {

    var defaultPlaybackSpeed: PlaybackSpeed
    var defaultSkipDuration: SkipDuration
    var colorScheme: AppColorScheme
    var showAbout = false
    var showHelp = false

    /// Replaces `AppFeature`'s `.settings(.setDefaultPlaybackSpeed)` → `.player(...)` tap.
    var onDefaultPlaybackSpeedChanged: (PlaybackSpeed) -> Void = { _ in }
    /// Replaces `AppFeature`'s `.settings(.setDefaultSkipDuration)` → `.player(...)` tap.
    var onDefaultSkipDurationChanged: (SkipDuration) -> Void = { _ in }

    init() {
        defaultPlaybackSpeed = UserDefaults.standard.savedPlaybackSpeed
        defaultSkipDuration = UserDefaults.standard.savedSkipDuration
        colorScheme = UserDefaults.standard.savedColorScheme
    }

    func setDefaultPlaybackSpeed(_ speed: PlaybackSpeed) {
        defaultPlaybackSpeed = speed
        UserDefaults.standard.savedPlaybackSpeed = speed
        onDefaultPlaybackSpeedChanged(speed)
    }

    func setDefaultSkipDuration(_ duration: SkipDuration) {
        defaultSkipDuration = duration
        UserDefaults.standard.savedSkipDuration = duration
        onDefaultSkipDurationChanged(duration)
    }

    func setColorScheme(_ scheme: AppColorScheme) {
        colorScheme = scheme
        UserDefaults.standard.savedColorScheme = scheme
    }

    func showAboutTapped() { showAbout = true }
    func dismissAbout() { showAbout = false }

    func showHelpTapped() { showHelp = true }
    func dismissHelp() { showHelp = false }

    func requestFeatureTapped() {
        guard let url = URL(string: "mailto:hasansa007@gmail.com?subject=Feature%20Request") else {
            return
        }
        UIApplication.shared.open(url)
    }
}
