import ComposableArchitecture
import SwiftUI
import UIKit // Assuming UIImage is used

struct FileItemRowView: View {
    let store: StoreOf<FileRowFeature>
    let isSelectionMode: Bool

    var body: some View {
        FileItemRow(
            title: store.file.title,
            subtitle: subtitleText,
            artwork: store.artwork,
            colors: store.colors,
            fallbackSystemImage: "waveform",
            showsChevron: false,
            onTap: { if !isSelectionMode { store.send(.tapped) } }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(store.isSelected ? Color.sonicPurple : Color.clear, lineWidth: 2)
        )
        .onAppear {
            store.send(.onAppear)
        }
    }
    
    private var selectionIndicator: some View {
        Image(systemName: store.isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundColor(store.isSelected ? .sonicPurple : .gray)
            .font(.title3)
    }

    private var subtitleText: String {
        var parts: [String] = []
        if let date = store.creationDate {
            parts.append(date.formatted(date: Date.FormatStyle.DateStyle.numeric, time: Date.FormatStyle.TimeStyle.shortened))
        } else {
            parts.append("Unknown Date")
        }
        let fileSize = store.file.fileSizeFormatted
        parts.append(fileSize)
        
        return parts.joined(separator: " • ")
    }
}
