import ComposableArchitecture
import SwiftUI

struct AllCollectionsView: View {
    @Bindable var store: StoreOf<AppFeature>
    @State private var isSelecting = false
    @State private var selectedIds: Set<URL> = []

    private static let gradients: [[Color]] = [
        [Color(hex: "1a3a5a"), Color(hex: "1B5B7E")],
        [Color(hex: "2a4a3a"), Color(hex: "1a6b4a")],
        [Color(hex: "2e2a50"), Color(hex: "4a3a6e")],
        [Color(hex: "4a2a3a"), Color(hex: "6e3a4a")],
        [Color(hex: "4a3a1a"), Color(hex: "6e5a2a")],
    ]

    private static let icons: [String] = [
        "waveform", "music.note.list", "mic.fill", "headphones", "square.stack.3d.up"
    ]

    var body: some View {
        NavigationStack(path: $store.scope(state: \.allFoldersPath, action: \.allFoldersPath)) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Array(store.filesRoot.filteredFolderCards.enumerated()), id: \.element.id) { index, card in
                        collectionCard(folder: card.folder, index: index, cardId: card.id)
                    }
                }
                .padding()
            }
            .background(Color.sonicBackground.ignoresSafeArea())
            .navigationTitle("All Collections")
            .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSelecting {
                    HStack(spacing: 16) {
                        if !selectedIds.isEmpty {
                            Menu {
                                Button {
                                    selectFoldersInStore()
                                    store.send(.filesRoot(.moveSelectedTapped))
                                    clearSelection()
                                } label: {
                                    Label("Move", systemImage: "folder")
                                }

                                if selectedIds.count == 1 {
                                    Button {
                                        if let firstId = selectedIds.first {
                                            store.send(.filesRoot(.folderCards(.element(id: firstId, action: .renameTapped))))
                                        }
                                        clearSelection()
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                }

                                Button(role: .destructive) {
                                    selectFoldersInStore()
                                    store.send(.filesRoot(.deleteSelectedTapped))
                                    clearSelection()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundColor(.sonicPrimary)
                            }
                        }

                        Button("Done") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelecting = false
                                selectedIds.removeAll()
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicPrimary)
                    }
                } else {
                    Button("Select") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSelecting = true
                        }
                    }
                    .foregroundColor(.sonicPrimary)
                }
            }
        }
        .alert("New Collection", isPresented: Binding(
            get: { store.filesRoot.isCreatingFolder },
            set: { if !$0 { store.send(.filesRoot(.cancelNameInput)) } }
        )) {
            TextField("Name", text: Binding(
                get: { store.filesRoot.inputText },
                set: { store.send(.filesRoot(.setInputText($0))) }
            ))
            Button("Create") { store.send(.filesRoot(.confirmNameInput)) }
            Button("Cancel", role: .cancel) { store.send(.filesRoot(.cancelNameInput)) }
        }
        .alert("Rename", isPresented: Binding(
            get: { store.filesRoot.renamingItem != nil },
            set: { if !$0 { store.send(.filesRoot(.cancelNameInput)) } }
        )) {
            TextField("Name", text: Binding(
                get: { store.filesRoot.inputText },
                set: { store.send(.filesRoot(.setInputText($0))) }
            ))
            Button("Rename") { store.send(.filesRoot(.confirmNameInput)) }
            Button("Cancel", role: .cancel) { store.send(.filesRoot(.cancelNameInput)) }
        }
        .alert($store.scope(state: \.filesRoot.alert, action: \.filesRoot.alert))
        .sheet(isPresented: Binding(
            get: { store.filesRoot.isShowingFolderPicker },
            set: { if !$0 { store.send(.filesRoot(.cancelMove)) } }
        )) {
            FolderPickerView(store: store.scope(state: \.filesRoot, action: \.filesRoot))
        }
        } destination: { filesStore in
            FilesView(store: filesStore)
        }
    }

    // MARK: - Card

    func collectionCard(folder: Folder, index: Int, cardId: URL) -> some View {
        let colors = Self.gradients[index % Self.gradients.count]
        let icon = Self.icons[index % Self.icons.count]
        let isSelected = selectedIds.contains(cardId)

        return Button {
            if isSelecting {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isSelected {
                        selectedIds.remove(cardId)
                    } else {
                        selectedIds.insert(cardId)
                    }
                }
            } else {
                store.send(.filesRoot(.folderCards(.element(id: cardId, action: .tapped))))
            }
        } label: {
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

                // Selection indicator
                if isSelecting {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                        }
                    }
                    .padding(10)
                }
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isSelecting {
                Button {
                    store.send(.filesRoot(.folderCards(.element(id: cardId, action: .moveTapped))))
                } label: { Label("Move", systemImage: "folder") }
                Button {
                    store.send(.filesRoot(.folderCards(.element(id: cardId, action: .renameTapped))))
                } label: { Label("Rename", systemImage: "pencil") }
                Button(role: .destructive) {
                    store.send(.filesRoot(.folderCards(.element(id: cardId, action: .deleteTapped))))
                } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private func selectFoldersInStore() {
        store.send(.filesRoot(.clearSelection))
        for id in selectedIds {
            if let card = store.filesRoot.folderCards[id: id] {
                store.send(.filesRoot(.toggleSelection(.folder(card.folder))))
            }
        }
    }

    private func clearSelection() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelecting = false
            selectedIds.removeAll()
        }
    }
}
