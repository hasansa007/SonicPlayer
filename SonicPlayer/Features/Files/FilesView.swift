import ComposableArchitecture
import SwiftUI

// Assuming FolderCardView.swift and FileItemRowView.swift are separate files in the same module
// If they are in different modules, explicit import statements for those modules would be needed.

struct FilesView: View {
    @Bindable var store: StoreOf<FilesFeature>
    @State private var showingDocumentPicker = false
    @State private var shareItem: ShareItem?
    @State private var isSelecting = false
    @State private var selectedFileIds: Set<UUID> = []

    var body: some View {
        ZStack {
            Color.sonicBackground.ignoresSafeArea()

            if shouldShowLoader {
                loadingView
            } else if store.items.isEmpty {
                emptyStateView
            } else {
                filesList
            }
        }
        .navigationTitle(store.currentDirectory?.lastPathComponent ?? "Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            toolbarContent
        }
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
            get: { store.isCreatingFolder },
            set: { if !$0 { store.send(.cancelNameInput) } }
        )) {
            TextField("Name", text: Binding(
                get: { store.inputText },
                set: { store.send(.setInputText($0)) }
            ))
            Button("Create") {
                store.send(.confirmNameInput)
            }
            Button("Cancel", role: .cancel) {
                store.send(.cancelNameInput)
            }
        }
        .alert("Rename", isPresented: Binding(
            get: { store.renamingItem != nil },
            set: { if !$0 { store.send(.cancelNameInput) } }
        )) {
            TextField("Name", text: Binding(
                get: { store.inputText },
                set: { store.send(.setInputText($0)) }
            ))
            Button("Rename") {
                store.send(.confirmNameInput)
            }
            Button("Cancel", role: .cancel) {
                store.send(.cancelNameInput)
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker(
                // Use `.item` so folders are selectable in the Files picker.
                contentTypes: [.item, .folder],
                asCopy: false,
                allowsMultipleSelection: true
            ) { urls in
                store.send(.importFiles(urls))
            }
        }
        .sheet(isPresented: Binding(
            get: { store.isShowingFolderPicker },
            set: { if !$0 { store.send(.cancelMove) } }
        )) {
            FolderPickerView(store: store)
        }
        .sheet(item: $store.scope(state: \.editAudio, action: \.editAudio)) { editStore in
            EditRecordingView(store: editStore)
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .onAppear {
            store.send(.onAppear)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.sonicPurple)
            Text("Loading...")
                .font(.subheadline)
                .foregroundColor(.sonicTextSecondary)
        }
    }

    private var emptyStateView: some View {
        EmptyStateView(
            icon: "folder.badge.questionmark",
            title: "Collection is Empty",
            iconStyle: AnyShapeStyle(LinearGradient.sonicGradient),
            iconSize: 64,
            spacing: 24
        )
    }
    
    // Helper to determine if we should show the full screen loader
    private var shouldShowLoader: Bool {
        store.isLoading && store.items.isEmpty
    }

    private var filesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                // Folders Section
                if !store.filteredFolderCards.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                            ForEach(store.scope(state: \.filteredFolderCards, action: \.folderCards)) { cardStore in
                                FolderCardView(store: cardStore)
                                    .contextMenu {
                                        Button {
                                            shareItem = ShareItem(url: cardStore.folder.url)
                                        } label: {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                        Button {
                                            cardStore.send(.moveTapped)
                                        } label: {
                                            Label("Move", systemImage: "folder")
                                        }
                                        Button {
                                            cardStore.send(.renameTapped)
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            cardStore.send(.deleteTapped)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                // Play All button (when folder has files)
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
                    .padding(.horizontal)
                }

                // Files Section
                if !store.filteredFileRows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        LazyVStack(spacing: 8) {
                            ForEach(store.scope(state: \.filteredFileRows, action: \.fileRows)) { rowStore in
                                HStack(spacing: 8) {
                                    if isSelecting {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                if selectedFileIds.contains(rowStore.id) {
                                                    selectedFileIds.remove(rowStore.id)
                                                } else {
                                                    selectedFileIds.insert(rowStore.id)
                                                }
                                            }
                                        } label: {
                                            Image(systemName: selectedFileIds.contains(rowStore.id) ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .foregroundColor(selectedFileIds.contains(rowStore.id) ? .sonicPrimary : .sonicTextMuted)
                                        }
                                    }

                                    FileItemRowView(store: rowStore, isSelectionMode: isSelecting)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isSelecting {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            if selectedFileIds.contains(rowStore.id) {
                                                selectedFileIds.remove(rowStore.id)
                                            } else {
                                                selectedFileIds.insert(rowStore.id)
                                            }
                                        }
                                    }
                                }
                                .contextMenu {
                                    if !isSelecting {
                                        Button {
                                            shareItem = ShareItem(url: rowStore.file.url)
                                        } label: {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                        Button {
                                            rowStore.send(.moveTapped)
                                        } label: {
                                            Label("Move", systemImage: "folder")
                                        }
                                        Button {
                                            rowStore.send(.renameTapped)
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            rowStore.send(.deleteTapped)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
            .padding(.bottom, 80) // Add bottom padding for Mini Player
        }
        .refreshable {
            await store.send(.refreshFiles).finish()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if isSelecting {
                HStack(spacing: 16) {
                    if !selectedFileIds.isEmpty {
                        Menu {
                            Button {
                                selectFilesInStore()
                                store.send(.moveSelectedTapped)
                                clearSelection()
                            } label: {
                                Label("Move", systemImage: "folder")
                            }

                            if selectedFileIds.count == 1 {
                                Button {
                                    if let id = selectedFileIds.first {
                                        store.send(.fileRows(.element(id: id, action: .renameTapped)))
                                    }
                                    clearSelection()
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                            }

                            Button(role: .destructive) {
                                selectFilesInStore()
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
                HStack(spacing: 16) {
                    if !store.filteredFileRows.isEmpty {
                        Button("Select") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelecting = true
                            }
                        }
                        .foregroundColor(.sonicPrimary)
                    }

                    Menu {
                        Button {
                            showingDocumentPicker = true
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            store.send(.createFolderTapped)
                        } label: {
                            Label("New Collection", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.sonicPrimary)
                    }
                }
            }
        }
    }

    private func selectFilesInStore() {
        store.send(.clearSelection)
        for id in selectedFileIds {
            if let row = store.fileRows[id: id] {
                store.send(.toggleSelection(.file(row.file)))
            }
        }
    }

    private func clearSelection() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelecting = false
            selectedFileIds.removeAll()
        }
    }

}

// MARK: - Document Picker

import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let asCopy: Bool
    let allowsMultipleSelection: Bool
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: asCopy)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // User cancelled, nothing to do
        }
    }
}
