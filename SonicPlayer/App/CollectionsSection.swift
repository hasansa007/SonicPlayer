import ComposableArchitecture
import SwiftUI

// MARK: - Home Collections Section

extension AppView {

    static let collectionGradients: [[Color]] = [
        [Color(hex: "1a3a5a"), Color(hex: "1B5B7E")],   // dark teal
        [Color(hex: "2a4a3a"), Color(hex: "1a6b4a")],    // dark green
        [Color(hex: "2e2a50"), Color(hex: "4a3a6e")],    // dark purple
        [Color(hex: "4a2a3a"), Color(hex: "6e3a4a")],    // dark rose
        [Color(hex: "4a3a1a"), Color(hex: "6e5a2a")],    // dark amber
    ]

    static let collectionIcons: [String] = [
        "waveform", "music.note.list", "mic.fill", "headphones", "square.stack.3d.up"
    ]

    @ViewBuilder
    var collectionsSection: some View {
        let collectionCards = store.filesRoot.filteredCollectionCards
        let maxVisible = horizontalSizeClass == .regular ? 4 : 2
        if !collectionCards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Collections")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(collectionCards.prefix(maxVisible).enumerated()), id: \.element.id) { index, card in
                            collectionCardView(folder: card.folder, index: index) {
                                store.send(.filesRoot(.collectionCards(.element(id: card.id, action: .tapped))))
                            } onMove: {
                                store.send(.filesRoot(.collectionCards(.element(id: card.id, action: .moveTapped))))
                            } onRename: {
                                store.send(.filesRoot(.collectionCards(.element(id: card.id, action: .renameTapped))))
                            } onDelete: {
                                store.send(.filesRoot(.collectionCards(.element(id: card.id, action: .deleteTapped))))
                            }
                        }

                        // "View All" dashed card
                        Button {
                            store.send(.viewAllCollectionsTapped)
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.title2)
                                    .foregroundColor(.sonicPrimary)

                                Text("View All")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.sonicPrimary)
                            }
                            .frame(width: 120, height: 120)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.sonicPrimary.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(Color.sonicPrimary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    func collectionCardView(folder: CollectionItem, index: Int, onTap: @escaping () -> Void, onMove: @escaping () -> Void, onRename: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
        let colors = Self.collectionGradients[index % Self.collectionGradients.count]
        let icon = Self.collectionIcons[index % Self.collectionIcons.count]

        return Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: icon)
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.2))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 5)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                VStack(alignment: .leading, spacing: 0) {
                    Text(folder.name)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.caption2)
                        Text("\(folder.itemCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: Capsule())
                }
                .padding(14)
            }
            .frame(width: 220, height: 120)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onMove) { Label("Move", systemImage: "folder") }
            Button(action: onRename) { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }
}
