import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String?
    let iconStyle: AnyShapeStyle
    let iconSize: CGFloat
    let spacing: CGFloat

    init(
        icon: String,
        title: String,
        message: String? = nil,
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
