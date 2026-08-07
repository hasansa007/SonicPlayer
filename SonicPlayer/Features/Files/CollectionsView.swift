import SwiftUI
import UniformTypeIdentifiers

/// One navigation depth of the file browser.
///
/// Owns its `CollectionsViewModel` as `@State` so the model's lifetime follows the screen's, and
/// takes its out-edges as closures wired by whoever pushed it. That is what replaced
/// `StackState` + `AppFeature` reaching into arbitrary stack depth by element id (#18): the depth
/// that raises an event is the only thing that knows its own file list, so it passes it out.
///
/// **Selection used to live in three places.** This view kept `isSelecting` /
/// `selectedCollectionIds` / `selectedFileIds`, the reducer kept `isSelectionMode` /
/// `selectedItems`, and each row reducer kept its own `isSelected` — with a `selectItemsInStore()`
/// translating between the first two on every action. The row mirrors went with the row reducers
/// and the local copies went with them; `viewModel.selectedItems` is now the only one.
struct CollectionsView: View {

    @Bindable private var viewModel: CollectionsViewModel
    @State private var shareItem: ShareItem?
    @State private var showingDocumentPicker = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(
        directory: URL?,
        fileManager: FileManagerClient = .live,
        onCollectionTapped: @escaping (CollectionItem) -> Void,
        onPlay: @escaping (AudioFile, [AudioFile], PlaylistSource?) -> Void,
        onWillRemoveItems: @escaping (Set<FileSystemItem>) -> Void = { _ in },
        onItemsLoaded: @escaping () -> Void = {}
    ) {
        let model = CollectionsViewModel(currentDirectory: directory, fileManager: fileManager)
        model.onCollectionTapped = onCollectionTapped
        model.onPlay = onPlay
        model.onWillRemoveItems = onWillRemoveItems
        model.onItemsLoaded = onItemsLoaded
        _viewModel = Bindable(wrappedValue: model)
    }

    /// For a model built and wired elsewhere — the root browser, which the composition root holds
    /// so Home's swipe actions can reach it.
    init(viewModel: CollectionsViewModel) {
        _viewModel = Bindable(wrappedValue: viewModel)
    }

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

            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView().tint(.sonicPrimary)
            } else if viewModel.items.isEmpty {
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
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search files..."
        )
        .alert("Delete \(viewModel.pendingDeleteCount) \(viewModel.pendingDeleteCount == 1 ? "item" : "items")?",
               isPresented: $viewModel.isConfirmingDelete) {
            Button("Delete", role: .destructive) { viewModel.confirmDelete() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Collection", isPresented: Binding(
            get: { viewModel.isCreatingCollection },
            set: { if !$0 { viewModel.cancelNameInput() } }
        )) {
            TextField("Name", text: $viewModel.inputText)
            Button("Create") { viewModel.confirmNameInput() }
            Button("Cancel", role: .cancel) { viewModel.cancelNameInput() }
        }
        .alert("Rename", isPresented: Binding(
            get: { viewModel.renamingItem != nil },
            set: { if !$0 { viewModel.cancelNameInput() } }
        )) {
            TextField("Name", text: $viewModel.inputText)
            Button("Rename") { viewModel.confirmNameInput() }
            Button("Cancel", role: .cancel) { viewModel.cancelNameInput() }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isShowingCollectionPicker },
            set: { if !$0 { viewModel.cancelMove() } }
        )) {
            InAppCollectionPicker(
                collections: viewModel.availableCollections,
                onPick: { viewModel.moveToDestination($0) },
                onCancel: { viewModel.cancelMove() }
            )
        }
        .sheet(item: $viewModel.audioToEdit) { file in
            EditRecordingView(recording: file) {
                viewModel.audioToEdit = nil
                viewModel.refreshFiles()
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker(
                contentTypes: [.item, .folder],
                asCopy: false,
                allowsMultipleSelection: true
            ) { urls in
                viewModel.importFiles(urls)
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .onAppear { viewModel.onAppear() }
    }

    // MARK: - Content List

    private var contentList: some View {
        List {
            if !viewModel.filteredFolders.isEmpty {
                Section {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                       count: horizontalSizeClass == .regular ? 4 : 2),
                        spacing: 12
                    ) {
                        ForEach(Array(viewModel.filteredFolders.enumerated()), id: \.element.id) { index, folder in
                            collectionCard(folder: folder, index: index)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if !viewModel.filteredFiles.isEmpty && viewModel.currentDirectory != nil {
                Button {
                    viewModel.playAllTapped()
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

            if !viewModel.filteredFiles.isEmpty {
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

                ForEach(viewModel.filteredFiles) { file in
                    fileRow(file)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.sonicBackground)
        .refreshable { viewModel.refreshFiles() }
    }

    private func fileRow(_ file: AudioFile) -> some View {
        MediaFileRowView(
            file: file,
            showsCollectionName: false,
            isSelecting: viewModel.isSelectionMode,
            isSelected: viewModel.isSelected(.file(file)),
            onTap: {
                if viewModel.isSelectionMode {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.toggleSelection(.file(file))
                    }
                } else {
                    viewModel.fileTapped(file)
                }
            }
        )
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                viewModel.select(.file(file))
                viewModel.deleteSelectedTapped()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                viewModel.renameItemTapped(.file(file))
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.sonicPrimary)
            Button {
                viewModel.moveItemTapped(.file(file))
            } label: {
                Label("Move", systemImage: "folder")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading) {
            Button {
                viewModel.audioToEdit = file
            } label: {
                Label("Edit", systemImage: "waveform.and.magnifyingglass")
            }
            .tint(.blue)
            Button {
                shareItem = ShareItem(url: file.url)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.gray)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if viewModel.isSelectionMode {
                HStack(spacing: 16) {
                    if !viewModel.selectedItems.isEmpty {
                        Menu {
                            Button {
                                viewModel.moveSelectedTapped()
                            } label: {
                                Label("Move", systemImage: "folder")
                            }

                            if viewModel.selectedItems.count == 1, let only = viewModel.selectedItems.first {
                                Button {
                                    viewModel.renameItemTapped(only)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                            }

                            Button(role: .destructive) {
                                viewModel.deleteSelectedTapped()
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
                            viewModel.toggleSelectionMode()
                        }
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
                        viewModel.moveSelectedTapped()
                    } label: {
                        Image(systemName: "folder.badge.arrow.up")
                            .foregroundColor(.sonicPrimary)
                    }

                    Button {
                        viewModel.createCollectionTapped()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .foregroundColor(.sonicPrimary)
                    }

                    Divider().frame(height: 20)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.toggleSelectionMode()
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

    func collectionCard(folder: CollectionItem, index: Int) -> some View {
        let colors = Self.gradients[index % Self.gradients.count]
        let icon = Self.icons[index % Self.icons.count]
        let isSelected = viewModel.isSelected(.folder(folder))
        let isSelecting = viewModel.isSelectionMode

        return Button {
            if isSelecting {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.toggleSelection(.folder(folder))
                }
            } else {
                viewModel.collectionTapped(folder)
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
                    viewModel.moveItemTapped(.folder(folder))
                } label: { Label("Move", systemImage: "folder") }
                Button {
                    viewModel.renameItemTapped(.folder(folder))
                } label: { Label("Rename", systemImage: "pencil") }
                Button(role: .destructive) {
                    viewModel.select(.folder(folder))
                    viewModel.deleteSelectedTapped()
                } label: { Label("Delete", systemImage: "trash") }
            }
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
