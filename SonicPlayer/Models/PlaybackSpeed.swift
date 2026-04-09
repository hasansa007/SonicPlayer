import Foundation

enum PlaybackSpeed: Float, CaseIterable, Identifiable, Codable {
    case half = 0.5
    case threeQuarters = 0.75
    case normal = 1.0
    case oneAndQuarter = 1.25
    case oneAndHalf = 1.5
    case oneAndThreeQuarters = 1.75
    case double = 2.0

    var id: Float { rawValue }

    var displayText: String {
        if self == .normal {
            return "1.0×"
        }
        return String(format: "%.2f×", rawValue)
    }
}

enum SkipDuration: TimeInterval, CaseIterable, Identifiable, Codable {
    case fifteen = 15
    case thirty = 30
    case sixty = 60

    var id: TimeInterval { rawValue }

    var displayText: String {
        "\(Int(rawValue))s"
    }
}

enum RepeatMode: String, CaseIterable, Codable {
    case off, one, all

    var icon: String {
        switch self {
        case .off: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }
    }
}

extension UserDefaults {
    var savedRepeatMode: RepeatMode {
        get {
            if let rawValue = string(forKey: "repeatMode") {
                return RepeatMode(rawValue: rawValue) ?? .off
            }
            return .off
        }
        set { set(newValue.rawValue, forKey: "repeatMode") }
    }
    var savedShuffleEnabled: Bool {
        get { bool(forKey: "shuffleEnabled") }
        set { set(newValue, forKey: "shuffleEnabled") }
    }
}
