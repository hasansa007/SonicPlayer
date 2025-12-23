import ComposableArchitecture
import SwiftUI
import UIKit

// Assuming FolderCardView.swift and FileItemRow.swift are separate files in the same module
// If they are in different modules, explicit import statements for those modules would be needed.

struct FilesView: View {
    @Bindable var store: StoreOf<FilesFeature>
    @State private var showingDocumentPicker = false
    @State private var shareItem: ShareItem?

    var body: some View {
        ZStack(alignment: .bottom) {
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
                
                // Files Section
                if !store.filteredFileRows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        LazyVStack(spacing: 8) {
                            ForEach(store.scope(state: \.filteredFileRows, action: \.fileRows)) { rowStore in
                                FileItemRow(store: rowStore, isSelectionMode: false)
                                .contextMenu {
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
            optionsMenu
        }
    }
    
    private var optionsMenu: some View {
        Menu {
            // Import
            Button {
                showingDocumentPicker = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }

            // Create New Folder
            Button {
                store.send(.createFolderTapped)
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }

        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundColor(.sonicPrimaryDark)
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

struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
