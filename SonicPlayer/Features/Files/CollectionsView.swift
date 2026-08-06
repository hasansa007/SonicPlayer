import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct CollectionsView: View {
    @Bindable var store: StoreOf<CollectionsFeature>
    @State private var isSelecting = false
    @State private var selectedCollectionIds: Set<URL> = []
    @State private var selectedFileIds: Set<UUID> = []
    @State private var shareItem: ShareItem?
    @State private var showingDocumentPicker = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
        ZStack {
            Color.sonicBackground.ignoresSafeArea()

            if store.isLoading && store.items.isEmpty {
                ProgressView().tint(.sonicPrimary)
            } else if store.items.isEmpty {
                EmptyStateView(
                    icon: "folder.badge.questionmark",
                    title: "Collection is Empty",
                    iconStyle: AnyShapeStyle(LinearGradient.sonicGradient),
                    iconSize: 64,
                    spacing: 24
                )
            } else {
                contentList
            }
        }
        .toolbar { toolbarContent }
        .searchable(
            text: Binding(
                get: { store.searchText },
                set: { store.send(.setSearchText($0)) }
            ),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search files..."
        )
        .alert($store.scope(state: \.alert, action: \.alert))
        .alert("New Collection", isPresented: Binding(
            get: { store.isCreatingCollection },
            set: { if !$0 { store.send(.cancelNameInput) } }
        )) {
            TextField("Name", text: Binding(
                get: { store.inputText },
                set: { store.send(.setInputText($0)) }
            ))
            Button("Create") { store.send(.confirmNameInput) }
            Button("Cancel", role: .cancel) { store.send(.cancelNameInput) }
        }
        .alert("Rename", isPresented: Binding(
            get: { store.renamingItem != nil },
            set: { if !$0 { store.send(.cancelNameInput) } }
        )) {
            TextField("Name", text: Binding(
                get: { store.inputText },
                set: { store.send(.setInputText($0)) }
            ))
            Button("Rename") { store.send(.confirmNameInput) }
            Button("Cancel", role: .cancel) { store.send(.cancelNameInput) }
        }
        .sheet(isPresented: Binding(
            get: { store.isShowingCollectionPicker },
            set: { if !$0 { store.send(.cancelMove) } }
        )) {
            InAppCollectionPicker(
                collections: store.availableCollections,
                onPick: { url in store.send(.moveToDestination(url)) },
                onCancel: { store.send(.cancelMove) }
            )
        }
        .sheet(item: $store.scope(state: \.editAudio, action: \.editAudio)) { editStore in
            EditRecordingView(store: editStore)
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker(
                contentTypes: [.item, .folder],
                asCopy: false,
                allowsMultipleSelection: true
            ) { urls in
                store.send(.importFiles(urls))
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .onAppear {
            store.send(.onAppear)
        }
    }

    // MARK: - Content List

    private var contentList: some View {
        List {
            // Collections Grid
            if !store.filteredCollectionCards.isEmpty {
                Section {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: horizontalSizeClass == .regular ? 4 : 2),
                        spacing: 12
                    ) {
                        ForEach(Array(store.filteredCollectionCards.enumerated()), id: \.element.id) { index, card in
                            collectionCard(folder: card.folder, index: index, cardId: card.id)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Play All button
            if !store.filteredFileRows.isEmpty && store.currentDirectory != nil {
                Button {
                    store.send(.playAllTapped)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                        Text("Play All")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.sonicPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.sonicPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Files Section
            if !store.filteredFileRows.isEmpty {
                HStack {
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "hand.draw")
                            .font(.caption2)
                        Text("Swipe for actions")
                            .font(.caption2)
                    }
                    .foregroundColor(.sonicTextMuted)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                ForEach(store.scope(state: \.filteredFileRows, action: \.fileRows)) { rowStore in
                    MediaFileRowView(
                        file: rowStore.file,
                        showsCollectionName: false,
                        isSelecting: isSelecting,
                        isSelected: selectedFileIds.contains(rowStore.file.id),
                        onTap: {
                            if isSelecting {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if selectedFileIds.contains(rowStore.file.id) {
                                        selectedFileIds.remove(rowStore.file.id)
                                    } else {
                                        selectedFileIds.insert(rowStore.file.id)
                                    }
                                }
                            } else {
                                rowStore.send(.tapped)
                            }
                        }
                    )
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                rowStore.send(.deleteTapped)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                rowStore.send(.renameTapped)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.sonicPrimary)
                            Button {
                                rowStore.send(.moveTapped)
                            } label: {
                                Label("Move", systemImage: "folder")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                rowStore.send(.editTapped)
                            } label: {
                                Label("Edit", systemImage: "waveform.and.magnifyingglass")
                            }
                            .tint(.blue)
                            Button {
                                shareItem = ShareItem(url: rowStore.file.url)
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .tint(.gray)
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.sonicBackground)
        .refreshable {
            await store.send(.refreshFiles).finish()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if isSelecting {
                HStack(spacing: 16) {
                    if !selectedCollectionIds.isEmpty || !selectedFileIds.isEmpty {
                        Menu {
                            Button {
                                selectItemsInStore()
                                store.send(.moveSelectedTapped)
                                clearSelection()
                            } label: {
                                Label("Move", systemImage: "folder")
                            }

                            if selectedCollectionIds.count + selectedFileIds.count == 1 {
                                Button {
                                    if let id = selectedCollectionIds.first {
                                        store.send(.collectionCards(.element(id: id, action: .renameTapped)))
                                    } else if let id = selectedFileIds.first {
                                        store.send(.fileRows(.element(id: id, action: .renameTapped)))
                                    }
                                    clearSelection()
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                            }

                            Button(role: .destructive) {
                                selectItemsInStore()
                                store.send(.deleteSelectedTapped)
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
                        clearSelection()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.sonicPrimary)
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        showingDocumentPicker = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundColor(.sonicPrimary)
                    }

                    Divider().frame(height: 20)

                    Button {
                        store.send(.moveSelectedTapped)
                    } label: {
                        Image(systemName: "folder.badge.arrow.up")
                            .foregroundColor(.sonicPrimary)
                    }

                    Button {
                        store.send(.createCollectionTapped)
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .foregroundColor(.sonicPrimary)
                    }

                    Divider().frame(height: 20)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSelecting = true
                        }
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.sonicPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Collection Card

    func collectionCard(folder: CollectionItem, index: Int, cardId: URL) -> some View {
        let colors = Self.gradients[index % Self.gradients.count]
        let icon = Self.icons[index % Self.icons.count]
        let isSelected = selectedCollectionIds.contains(cardId)

        return Button {
            if isSelecting {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isSelected {
                        selectedCollectionIds.remove(cardId)
                    } else {
                        selectedCollectionIds.insert(cardId)
                    }
                }
            } else {
                store.send(.collectionCards(.element(id: cardId, action: .tapped)))
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
                    store.send(.collectionCards(.element(id: cardId, action: .moveTapped)))
                } label: { Label("Move", systemImage: "folder") }
                Button {
                    store.send(.collectionCards(.element(id: cardId, action: .renameTapped)))
                } label: { Label("Rename", systemImage: "pencil") }
                Button(role: .destructive) {
                    store.send(.collectionCards(.element(id: cardId, action: .deleteTapped)))
                } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    // MARK: - Helpers

    private func selectItemsInStore() {
        store.send(.clearSelection)
        for id in selectedCollectionIds {
            if let card = store.collectionCards[id: id] {
                store.send(.toggleSelection(.folder(card.folder)))
            }
        }
        for id in selectedFileIds {
            if let row = store.fileRows[id: id] {
                store.send(.toggleSelection(.file(row.file)))
            }
        }
    }

    private func clearSelection() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelecting = false
            selectedCollectionIds.removeAll()
            selectedFileIds.removeAll()
        }
    }
}

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType] = [.item, .folder]
    var asCopy: Bool = false
    var allowsMultipleSelection: Bool = true
    var directoryURL: URL? = nil
    let onPick: ([URL]) -> Void
    var onCancel: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: asCopy)
        picker.allowsMultipleSelection = allowsMultipleSelection
        if let directoryURL { picker.directoryURL = directoryURL }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: (() -> Void)?

        init(onPick: @escaping ([URL]) -> Void, onCancel: (() -> Void)?) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel?()
        }
    }
}
