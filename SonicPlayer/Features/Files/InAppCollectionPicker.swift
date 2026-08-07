import SwiftUI

/// In-app collection picker for "Move To" operations.
/// Lists all collections (folders) in the app's Documents directory.
struct InAppCollectionPicker: View {
    let collections: [CollectionItem]
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isCreatingCollection = false
    @State private var newCollectionName = ""
    @State private var createdCollections: [CollectionItem] = []

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private var allCollections: [CollectionItem] {
        collections + createdCollections
    }

    var body: some View {
        NavigationStack {
            List {
                // Root option
                Button {
                    onPick(documentsURL)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "house.fill")
                            .font(.title3)
                            .foregroundColor(.sonicPrimary)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Library Root")
                                .font(.body)
                                .foregroundColor(.sonicTextPrimary)
                            Text("Documents")
                                .font(.caption)
                                .foregroundColor(.sonicTextSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.sonicTextMuted)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)

                // All collections
                ForEach(allCollections, id: \.id) { collection in
                    Button {
                        onPick(collection.url)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .font(.title3)
                                .foregroundColor(.sonicPrimary)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(collection.name)
                                    .font(.body)
                                    .foregroundColor(.sonicTextPrimary)
                                    .lineLimit(1)
                                Text(relativePath(for: collection.url))
                                    .font(.caption)
                                    .foregroundColor(.sonicTextSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.sonicTextMuted)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.sonicBackground)
            .navigationTitle("Move To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.sonicPrimary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        newCollectionName = ""
                        isCreatingCollection = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .foregroundColor(.sonicPrimary)
                    }
                }
            }
            .interactiveDismissDisabled(true)
            .alert("New Collection", isPresented: $isCreatingCollection) {
                TextField("Name", text: $newCollectionName)
                Button("Create") {
                    createCollection()
                }
                Button("Cancel", role: .cancel) {
                    newCollectionName = ""
                }
            } message: {
                Text("Create a new collection in Library Root")
            }
        }
    }

    private func createCollection() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "New Collection" : trimmed
        var finalName = baseName
        var url = documentsURL.appendingPathComponent(finalName, isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            finalName = "\(baseName) \(counter)"
            url = documentsURL.appendingPathComponent(finalName, isDirectory: true)
            counter += 1
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            let newCollection = CollectionItem(
                id: url,
                url: url,
                name: finalName,
                creationDate: Date()
            )
            createdCollections.append(newCollection)
            newCollectionName = ""
        } catch {
            print("Failed to create collection: \(error.localizedDescription)")
        }
    }

    private func relativePath(for url: URL) -> String {
        let documentsPath = documentsURL.path
        let urlPath = url.path
        if urlPath.hasPrefix(documentsPath) {
            let relative = String(urlPath.dropFirst(documentsPath.count))
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        return url.lastPathComponent
    }
}
