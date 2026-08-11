import Foundation
import SwiftUI

/// Settings persistence and the theme enum.
///
/// These lived in `SettingsFeature.swift` but were never part of the reducer — `PlayerFeature`
/// reads `savedPlaybackSpeed` / `savedSkipDuration` on init, and `AppColorScheme` is used by the
/// onboarding theme picker and the root view. Split out so deleting the reducer does not take
/// them with it.

// MARK: - UserDefaults

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

// MARK: - Theme

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
