import SwiftUI
import UIKit

struct FileItemRow<LeadingAccessory: View, TrailingAccessory: View>: View {
    let title: String
    let subtitle: String
    let artwork: UIImage?
    let colors: [Color]
    let fallbackSystemImage: String
    let showsChevron: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 12) {

            iconView

            detailsView

            Spacer()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: colors.isEmpty ? Color.sonicTealColors : colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            }
        }
        .frame(width: 56, height: 56)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.3), lineWidth: 1)
        }
        .shadow(color: (colors.first ?? .clear).opacity(0.3), radius: 4, x: 0, y: 2)
    }

    private var detailsView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(2)
                .truncationMode(.middle)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

extension FileItemRow where LeadingAccessory == EmptyView, TrailingAccessory == EmptyView {
    init(
        title: String,
        subtitle: String,
        artwork: UIImage?,
        colors: [Color],
        fallbackSystemImage: String,
        showsChevron: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.colors = colors
        self.fallbackSystemImage = fallbackSystemImage
        self.showsChevron = showsChevron
        self.onTap = onTap
    }
}
