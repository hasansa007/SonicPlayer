import SwiftUI

struct FolderCard: View {
    let folder: Folder
    let artwork: UIImage?
    let colors: [Color]
    let onAppear: () -> Void
    var width: CGFloat = 160
    var fallbackColors: [Color]? = nil

    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Artwork/Thumbnail
            ZStack {
                // Dynamic gradient background
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: colors.isEmpty ? (fallbackColors ?? Color.sonicTealColors) : colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(1, contentMode: .fit)

                // Artwork or icon
                if let artwork = artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: width)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.sonicPrimary.opacity(0.15))
                        }
                } else {
                    VStack {
                        Image(systemName: folder.subfolderCount > 0 ? "rectangle.stack.fill" : "music.note.list")
                            .font(.system(size: 44))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }

                // Overlay border
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: colors.first?.opacity(0.4) ?? .clear, radius: 12, x: 0, y: 6)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)

            // Title
            Text(folder.name)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Stats
            HStack(spacing: 4) {
                if folder.subfolderCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "folder.fill")
                            .font(.caption2)
                        Text("\(folder.subfolderCount)")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }

                if folder.subfolderCount > 0 && folder.itemCount > 0 {
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if folder.itemCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "music.note")
                            .font(.caption2)
                        Text("\(folder.itemCount)")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .onAppear {
            onAppear()
        }
    }
}
