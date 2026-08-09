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
    var colorScheme: AppColorScheme
    var showAbout = false
    var showHelp = false

    /// Replaces `AppFeature`'s `.settings(.setDefaultPlaybackSpeed)` → `.player(...)` tap.
    ///
    /// **The only preference that still travels this way.** Skip duration used to have a twin here;
    /// the dial has no skip control — its horizontal nudges step *tracks* — so the setting was
    /// choosing the size of a button nothing presses. `PlayerViewModel` keeps its `skipDuration`
    /// at the stored default for the remote-command centre, which does still offer ±15s.
    var onDefaultPlaybackSpeedChanged: (PlaybackSpeed) -> Void = { _ in }

    init() {
        defaultPlaybackSpeed = UserDefaults.standard.savedPlaybackSpeed
        colorScheme = UserDefaults.standard.savedColorScheme
    }

    func setDefaultPlaybackSpeed(_ speed: PlaybackSpeed) {
        defaultPlaybackSpeed = speed
        UserDefaults.standard.savedPlaybackSpeed = speed
        onDefaultPlaybackSpeedChanged(speed)
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

    /// Opens SonicPlayer's own page in iOS Settings, where the system's per-app **Preferred
    /// Language** control lives.
    ///
    /// The app cannot do this itself and never could (#68). `Text` resolves through `Bundle.main`,
    /// which fixes its localization when the process starts — so the picker this replaces mirrored
    /// the layout instantly and translated nothing until the next launch. iOS offers the control
    /// because the bundle ships nine `.lproj` localizations; it restarts the app, so strings,
    /// locale and layout direction change together instead of disagreeing.
    func openSystemLanguageSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
