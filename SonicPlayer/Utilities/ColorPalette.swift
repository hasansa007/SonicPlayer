import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

extension Color {
    // Helper for dynamic colors
    static func dynamic(light: String, dark: String) -> Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    // Logo colors - Teal theme
    static let sonicPrimary = Color(hex: "2B9EB3")
    static let sonicPrimaryDark = Color(hex: "1B5B7E")
    static let sonicPrimaryLight = Color(hex: "4DB8CC")

    // Neutral colors
    static let sonicBackground = dynamic(light: "F8FAFB", dark: "000000")
    static let sonicSurface = dynamic(light: "FFFFFF", dark: "1C1C1E")
    static let sonicTextPrimary = dynamic(light: "1A2332", dark: "FFFFFF")
    static let sonicTextSecondary = dynamic(light: "5F6B7A", dark: "98989D")
    static let sonicTextMuted = dynamic(light: "9BA5B4", dark: "636366")
    static let sonicBorder = dynamic(light: "E5E9EF", dark: "38383A")

    static let sonicPurple = Color(hex: "764ba2")
    static let sonicPurpleDark = Color(hex: "667eea")
    static let sonicPurpleLight = Color(hex: "8E54E9")
    static let sonicOrange = Color(hex: "f5576c")
    static let sonicOrangeDark = Color(hex: "f093fb")
    static let sonicOrangeLight = Color(hex: "FF7E5F")
    static let sonicGreen = Color(hex: "43e97b")
    static let sonicGreenDark = Color(hex: "38f9d7")
    static let sonicGreenLight = Color(hex: "2AF598")
    static let sonicBlue = Color(hex: "00f2fe")
    static let sonicBlueDark = Color(hex: "4facfe")
    static let sonicBlueLight = Color(hex: "00C6FF")

    // Gradient Color Sets
    static let sonicTealColors = [sonicPrimaryDark, sonicPrimaryLight]
    static let sonicPurpleColors = [sonicPurpleDark, sonicPurpleLight]
    static let sonicOrangeColors = [sonicOrangeDark, sonicOrangeLight]
    static let sonicGreenColors = [sonicGreenDark, sonicGreenLight]
    static let sonicBlueColors = [sonicBlueDark, sonicBlueLight]

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension LinearGradient {
    static let sonicGradient = LinearGradient(
        colors: Color.sonicTealColors,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let sonicGradientLight = LinearGradient(
        colors: [
            Color.sonicPrimaryDark.opacity(0.05),
            Color.sonicPrimary.opacity(0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

}
