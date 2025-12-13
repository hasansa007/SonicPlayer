import ComposableArchitecture
import Foundation
import SwiftUI

// UserDefaults helpers
extension UserDefaults {
    var savedPlaybackSpeed: PlaybackSpeed {
        get {
            if let rawValue = value(forKey: "defaultPlaybackSpeed") as? Float {
                return PlaybackSpeed(rawValue: rawValue) ?? .normal
            }
            return .normal
        }
        set {
            set(newValue.rawValue, forKey: "defaultPlaybackSpeed")
        }
    }

    var savedSkipDuration: SkipDuration {
        get {
            if let rawValue = value(forKey: "defaultSkipDuration") as? TimeInterval {
                return SkipDuration(rawValue: rawValue) ?? .thirty
            }
            return .thirty
        }
        set {
            set(newValue.rawValue, forKey: "defaultSkipDuration")
        }
    }

    var savedColorScheme: AppColorScheme {
        get {
            if let rawValue = string(forKey: "colorScheme") {
                return AppColorScheme(rawValue: rawValue) ?? .system
            }
            return .system
        }
        set {
            set(newValue.rawValue, forKey: "colorScheme")
        }
    }
}

@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        var defaultPlaybackSpeed: PlaybackSpeed
        var defaultSkipDuration: SkipDuration
        var colorScheme: AppColorScheme
        var showAbout = false
        var showHelp = false

        init() {
            self.defaultPlaybackSpeed = UserDefaults.standard.savedPlaybackSpeed
            self.defaultSkipDuration = UserDefaults.standard.savedSkipDuration
            self.colorScheme = UserDefaults.standard.savedColorScheme
        }
    }

    enum Action {
        case setDefaultPlaybackSpeed(PlaybackSpeed)
        case setDefaultSkipDuration(SkipDuration)
        case setColorScheme(AppColorScheme)
        case showAboutTapped
        case showHelpTapped
        case requestFeatureTapped
        case dismissAbout
        case dismissHelp
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setDefaultPlaybackSpeed(speed):
                state.defaultPlaybackSpeed = speed
                UserDefaults.standard.savedPlaybackSpeed = speed
                return .none

            case let .setDefaultSkipDuration(duration):
                state.defaultSkipDuration = duration
                UserDefaults.standard.savedSkipDuration = duration
                return .none

            case let .setColorScheme(scheme):
                state.colorScheme = scheme
                UserDefaults.standard.savedColorScheme = scheme
                return .none

            case .showAboutTapped:
                state.showAbout = true
                return .none

            case .showHelpTapped:
                state.showHelp = true
                return .none
                
            case .requestFeatureTapped:
                // Placeholder for feature request logic (e.g., mailto)
                // TODO: Replace 'support@sonicplayer.app' with your actual support email
                if let url = URL(string: "mailto:support@sonicplayer.app?subject=Feature%20Request") {
                    UIApplication.shared.open(url)
                }
                return .none

            case .dismissAbout:
                state.showAbout = false
                return .none

            case .dismissHelp:
                state.showHelp = false
                return .none
            }
        }
    }
}

enum AppColorScheme: String, CaseIterable, Identifiable, Codable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}
