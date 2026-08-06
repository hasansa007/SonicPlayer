import SwiftUI

/// Shared media file row used on Home (Recent Media) and Collections view.
struct MediaFileRowView: View {
    let file: AudioFile
    var showsCollectionName: Bool = true
    var isSelecting: Bool = false
    var isSelected: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isSelected ? .sonicPrimary : .sonicTextMuted)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient.sonicGradient)
                        .frame(width: 40, height: 40)

                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.title)
                        .font(.body)
                        .foregroundColor(.sonicTextPrimary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(file.durationFormatted)
                        Text("·")
                        Text(file.creationDate, style: .date)
                        if showsCollectionName, let collectionName = Self.collectionName(for: file) {
                            Text("·")
                            HStack(spacing: 2) {
                                Image(systemName: "folder.fill")
                                    .font(.caption2)
                                Text(collectionName)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.sonicTextSecondary)
                }

                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func collectionName(for file: AudioFile) -> String? {
        let parent = file.url.deletingLastPathComponent()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if parent == documents { return nil }
        return parent.lastPathComponent
    }
}
