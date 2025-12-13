import ComposableArchitecture
import SwiftUI

// Assuming FolderCardView.swift and FileItemRow.swift are separate files in the same module
// If they are in different modules, explicit import statements for those modules would be needed.

struct FilesView: View {
    @Bindable var store: StoreOf<FilesFeature>
    @State private var showingDocumentPicker = false

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
        .toolbar {
            if store.isSelectionMode {
                ToolbarItem(placement: .bottomBar) {
                    bottomToolbarContent
                }
            }
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
        .alert("New Folder", isPresented: Binding(
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
            DocumentPicker { urls in
                store.send(.importFiles(urls))
            }
        }
        .sheet(isPresented: Binding(
            get: { store.isShowingFolderPicker },
            set: { if !$0 { store.send(.cancelMove) } }
        )) {
            FolderPickerView(store: store)
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
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 64))
                .foregroundStyle(LinearGradient.sonicGradientPurple)
            
            Text("Folder is Empty")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.sonicTextPrimary)
        }
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
                                    // Add visual selection state if needed
                                    .opacity(cardStore.isSelected ? 0.7 : 1.0)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.sonicPurple, lineWidth: cardStore.isSelected ? 3 : 0)
                                    )
                                    .contextMenu {
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
                
                // Files Section
                if !store.filteredFileRows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        LazyVStack(spacing: 8) {
                            ForEach(store.scope(state: \.filteredFileRows, action: \.fileRows)) { rowStore in
                                FileItemRow(store: rowStore, isSelectionMode: store.isSelectionMode)
                                .contextMenu {
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
            if store.isSelectionMode {
                Button("Done") {
                    store.send(.toggleSelectionMode)
                }
            } else {
                optionsMenu
            }
        }
    }
    
    private var optionsMenu: some View {
        Menu {
            Button {
                showingDocumentPicker = true
            } label: {
                Label("Import Files", systemImage: "square.and.arrow.down")
            }

            Button {
                store.send(.createFolderTapped)
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }

            Divider()

            Menu("Sort By") {
                Picker("Sort By", selection: $store.sortOption.sending(\.setSortOption)) {
                    Text("Name").tag(FilesFeature.SortOption.name)
                    Text("Date").tag(FilesFeature.SortOption.date)
                    Text("Size").tag(FilesFeature.SortOption.size)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundColor(.sonicPrimaryDark)
        }
    }
    
    @ViewBuilder
    private var bottomToolbarContent: some View {
        HStack {
            Button(role: .destructive) {
                store.send(.deleteSelectedTapped)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(store.selectedItems.isEmpty)
            
            Spacer()
            
            Text("\(store.selectedItems.count) selected")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button {
                store.send(.moveSelectedTapped)
            } label: {
                Label("Move", systemImage: "folder")
            }
            .disabled(store.selectedItems.isEmpty)
        }
    }
}

// MARK: - Document Picker

import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Support multiple audio formats
        let types: [UTType] = [
            .mp3,
            .mpeg4Audio,  // m4a
            .wav,
            .audio  // Fallback for other audio types
        ].compactMap { $0 }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
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
