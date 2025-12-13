import SwiftUI

// MARK: - Gradients

extension LinearGradient {
    static func sonic(colors: [Color]) -> LinearGradient {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    func sonicGradientForeground(colors: [Color]) -> some View {
        self.foregroundStyle(LinearGradient.sonic(colors: colors))
    }
    
    func sonicGradientBackground(colors: [Color], opacity: Double = 1.0, cornerRadius: CGFloat = 12) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(LinearGradient.sonic(colors: colors.map { $0.opacity(opacity) }))
        }
    }
    
    func sonicGradientStroke(colors: [Color], opacity: Double = 1.0, lineWidth: CGFloat = 1, cornerRadius: CGFloat = 12) -> some View {
        self.overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(LinearGradient.sonic(colors: colors.map { $0.opacity(opacity) }), lineWidth: lineWidth)
        }
    }
}

// MARK: - Button Styles

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
