import SwiftUI

struct EmptyStateView: View {
    let icon: String
    // `LocalizedStringKey`, not `String` (#47). `Text(someString)` binds to the `StringProtocol`
    // overload, which does **not** localize — so every empty state in the app rendered its
    // English source text in all nine languages, even though the strings were sitting in
    // `Localizable.xcstrings` the whole time. Every caller passes a literal, and
    // `LocalizedStringKey` is `ExpressibleByStringLiteral`, so none of them had to change.
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    let iconStyle: AnyShapeStyle
    let iconSize: CGFloat
    let spacing: CGFloat

    init(
        icon: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        iconStyle: AnyShapeStyle,
        iconSize: CGFloat = 72,
        spacing: CGFloat = 20
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.iconStyle = iconStyle
        self.iconSize = iconSize
        self.spacing = spacing
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: spacing) {
                Image(systemName: icon)
                    .font(.system(size: iconSize))
                    .foregroundStyle(iconStyle)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicTextPrimary)

                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundColor(.sonicTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .position(
                x: proxy.size.width / 2,
                y: (proxy.size.height - proxy.safeAreaInsets.bottom + proxy.safeAreaInsets.top) / 2
            )
        }
    }
}
