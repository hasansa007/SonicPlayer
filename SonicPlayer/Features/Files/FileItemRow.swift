import ComposableArchitecture
import SwiftUI
import UIKit // Assuming UIImage is used

struct FileItemRow: View {
    let store: StoreOf<FileRowFeature>
    let isSelectionMode: Bool
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                selectionIndicator
            }

            iconView

            detailsView

            Spacer()

            if showChevron {
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
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(store.isSelected ? Color.sonicPurple : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .contentShape(Rectangle())
        .onTapGesture(perform: {
            store.send(.tapped)
        })
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
            if pressing {
                // onLongPressAction?() -> We don't have this anymore, maybe trigger context menu?
                // Context menu is on the view itself in the list.
            }
        }, perform: {})
        .onAppear {
            store.send(.onAppear)
        }
    }
    
    private var selectionIndicator: some View {
        Image(systemName: store.isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundColor(store.isSelected ? .sonicPurple : .gray)
            .font(.title3)
    }
    
    private var iconView: some View {
        // Audio file with album artwork
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: store.colors.isEmpty ? Color.sonicTealColors : store.colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let artwork = store.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "waveform")
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
        .shadow(color: (store.colors.first ?? .clear).opacity(0.3), radius: 4, x: 0, y: 2)
    }
    
    private var detailsView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(store.file.title)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(2)
                .truncationMode(.middle)

            HStack(spacing: 6) {
                if let date = store.creationDate {
                    // Corrected Date.FormatStyle usage with explicit enum cases
                    Text(date.formatted(date: Date.FormatStyle.DateStyle.numeric, time: Date.FormatStyle.TimeStyle.shortened))
                } else {
                    Text("Unknown Date")
                }

                if let fileSize = fileSizeText {
                    Text("•")
                    Text(fileSize)
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }
    
    private var fileSizeText: String? {
         return store.file.fileSizeFormatted
    }
    
    private var showChevron: Bool {
        return false // Files don't have chevrons usually
    }
}
