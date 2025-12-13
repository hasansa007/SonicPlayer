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
