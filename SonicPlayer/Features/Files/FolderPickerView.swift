import ComposableArchitecture
import SwiftUI

// MARK: - Folder Picker

struct FolderPickerView: View {
    @Bindable var store: StoreOf<FilesFeature>

    @State private var isShowingCreateFolder = false
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    Text("Select destination folder")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // Rows (including Root)
                    ForEach(store.scope(state: \.folderPicker, action: \.folderPicker)) { rowStore in
                        FolderPickerRow(store: rowStore)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Color.sonicBackground.ignoresSafeArea())
            .navigationTitle("Move To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        store.send(.cancelMove)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newFolderName = ""
                        isShowingCreateFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .foregroundColor(.sonicPurple)
                    }
                }
            }
            .alert("New Folder", isPresented: $isShowingCreateFolder) {
                TextField("Name", text: $newFolderName)
                Button("Create") {
                    let name = newFolderName.isEmpty ? "New Folder" : newFolderName
                    store.send(.createFolderInPicker(name))
                }
                Button("Cancel", role: .cancel) {
                    newFolderName = ""
                }
            } message: {
                Text("Create a new folder in \(store.currentDirectory?.lastPathComponent ?? "SonicPlayer")")
            }
        }
    }
}

// MARK: - Folder Picker Row

struct FolderPickerRow: View {
    let store: StoreOf<FolderPickerFeature>

    @State private var isPressed = false

    var body: some View {
        Button {
            store.send(.tapped)
        } label: {
            HStack(spacing: 12) {
                // Folder icon/artwork
                if store.isRoot {
                    // Root folder with gradient
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient.sonicGradientPurple)

                        Image(systemName: "house.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    }
                    .frame(width: 56, height: 56)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    }
                    .shadow(color: .sonicPurple.opacity(0.3), radius: 4, x: 0, y: 2)
                } else {
                    // Folder with dynamic gradient and artwork
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
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            LinearGradient(
                                                colors: [.clear, .black.opacity(0.3)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                }
                        } else {
                            Image(systemName: "folder.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
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

                // Folder info
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.isRoot ? "Root/" : store.folder?.name ?? "")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    if !store.isRoot && !store.folderPath.isEmpty {
                        Text(store.folderPath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .onAppear {
            store.send(.onAppear)
        }
    }
}
