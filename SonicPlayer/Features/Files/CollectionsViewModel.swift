import Foundation
import Observation

/// Replaces `CollectionsFeature` (#18), one instance per navigation depth.
///
/// ## What went away rather than being ported
///
/// **`FileRowFeature` and `CollectionItemCardFeature` are deleted.** Both were ~90%
/// `return .none // Handled by parent`; their only real behaviour died in #10. They existed
/// because `IdentifiedArray` + `.forEach` needs per-row identity to route actions — a problem a
/// closure passed into `ForEach` does not have.
///
/// **The child-state reconciliation on reload went with them, and it turned out to preserve
/// nothing.** It looked like it was holding on to loaded artwork across a refresh. It was not:
/// `FileRowFeature.State` held `file`, `isSelected` and `creationDate` and never held artwork —
/// that lives in `ArtworkClient`'s own cache and always did. The only thing the reconciliation
/// actually carried was `isSelected`, which was itself a mirror of `selectedItems`. Two sources of
/// truth reconciled against each other; now there is one, and `isSelected(_:)` reads it.
///
/// ## Navigation
///
/// `StackState` is gone. Each depth is a `CollectionsViewModel` owned by its own screen as
/// `@State`, with its callbacks wired at construction. `AppFeature` used to reach into arbitrary
/// stack depth by element id to find out *which* folder's file list to play; it no longer has to,
/// because the depth that raised the event passes its own data out through the closure.
@MainActor
@Observable
final class CollectionsViewModel {

    let currentDirectory: URL?

    private(set) var items: [FileSystemItem] = []
    private(set) var isLoading = false
    var documentsDirectoryURL: URL?

    /// What went wrong, for the browser's error state (#48).
    ///
    /// Every failure on this screen used to be a `try?`. A listing that threw left the previous
    /// list on screen and said nothing — on a first load that is a permanently empty browser with
    /// no explanation. A delete that threw removed the item from the selection and left it on
    /// disk. A move that threw reached `print(_:)`, in a shipping app.
    ///
    /// Surfacing them changes no success path; it gives the failures somewhere to go.
    var operationError: String?

    /// Set only when the *listing* failed, which is the one failure that has to replace the
    /// content rather than sit over it — there is no content to sit over.
    private(set) var loadFailed = false

    var searchText = ""
    var isSelectionMode = false
    private(set) var selectedItems: Set<FileSystemItem> = []

    /// The file the editor is open on. A value, not a model — the sheet builds the model, so its
    /// lifetime follows the sheet's identity.
    var audioToEdit: AudioFile?

    // Name input
    var isCreatingCollection = false
    var renamingItem: FileSystemItem?
    var inputText = ""

    // Move
    private(set) var itemsToMove: Set<FileSystemItem> = []
    var isShowingCollectionPicker = false
    private(set) var availableCollections: [CollectionItem] = []

    /// Replaces `AlertState<Action.Alert>`. The other ~12 presentations in this screen were already
    /// hand-rolled bindings, so this brings the last one into line rather than introducing a style.
    var isConfirmingDelete = false
    var pendingDeleteCount: Int { selectedItems.count }

    // MARK: - Out-edges, wired at the composition root

    var onCollectionTapped: (CollectionItem) -> Void = { _ in }
    /// Carries the queue and source with it. That is what removes AppFeature's reach-by-stack-id:
    /// the depth that raised the tap is the only thing that knows its own file list.
    var onPlay: (AudioFile, [AudioFile], PlaylistSource?) -> Void = { _, _, _ in }
    /// See #22 — the items travel rather than being read back, because they are cleared before the
    /// removal completes.
    var onWillRemoveItems: (Set<FileSystemItem>) -> Void = { _ in }
    var onItemsLoaded: () -> Void = {}

    private var loadTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?

    private let fileManager: FileManagerClient

    init(currentDirectory: URL?, fileManager: FileManagerClient = .live) {
        self.currentDirectory = currentDirectory
        self.fileManager = fileManager
    }

    isolated deinit {
        loadTask?.cancel()
        workTask?.cancel()
    }

    // MARK: - Derived

    var audioFiles: [AudioFile] {
        items.compactMap { if case let .file(f) = $0 { return f }; return nil }
    }

    var filteredItems: [FileSystemItem] {
        SelectionSet.matching(items, searchText: searchText)
    }

    var filteredFolders: [CollectionItem] {
        filteredItems.compactMap { if case let .folder(f) = $0 { return f }; return nil }
    }

    var filteredFiles: [AudioFile] {
        filteredItems.compactMap { if case let .file(f) = $0 { return f }; return nil }
    }

    /// The single source of truth the deleted `isSelected` mirrors used to shadow.
    func isSelected(_ item: FileSystemItem) -> Bool {
        selectedItems.contains(item)
    }

    /// The playlist source for this depth. Root browses everything; a folder plays as that folder.
    var playlistSource: PlaylistSource? {
        currentDirectory.map { .folder($0) }
    }

    // MARK: - Loading

    func onAppear() { refreshFiles() }

    func refreshFiles() {
        // Screenshot mode seeds demo data; loading real files would wipe it.
        if ScreenshotMode.isEnabled && !items.isEmpty { return }

        isLoading = true
        documentsDirectoryURL = fileManager.documentsDirectory()

        loadTask?.cancel()
        loadTask = Task { [weak self, fileManager, currentDirectory] in
            do {
                let loaded = try await fileManager.listItems(currentDirectory)
                guard !Task.isCancelled else { return }
                self?.itemsLoaded(loaded)
            } catch {
                guard !Task.isCancelled else { return }
                self?.listingFailed(error)
            }
        }
    }

    /// The listing threw. Previously a `try?` swallowed it and left whatever was on screen —
    /// which on a first load is nothing at all, forever, with no way to tell an empty folder
    /// from a broken one (#48).
    private func listingFailed(_ error: any Error) {
        isLoading = false
        loadFailed = true
        operationError = error.localizedDescription
    }

    private func itemsLoaded(_ loaded: [FileSystemItem]) {
        isLoading = false
        loadFailed = false
        operationError = nil
        items = loaded
        onItemsLoaded()
    }

    /// Screenshot mode only. `items` is `private(set)` because every real write goes through
    /// `refreshFiles`; the demo data has no file system behind it and needs a way in.
    func seed(items seeded: [FileSystemItem]) {
        items = seeded
    }

    // MARK: - Taps

    func collectionTapped(_ folder: CollectionItem) {
        if isSelectionMode {
            toggleSelection(.folder(folder))
        } else {
            onCollectionTapped(folder)
        }
    }

    func fileTapped(_ file: AudioFile) {
        if isSelectionMode {
            toggleSelection(.file(file))
        } else {
            onPlay(file, audioFiles, playlistSource)
        }
    }

    func playAllTapped() {
        guard let first = audioFiles.first else { return }
        onPlay(first, audioFiles, playlistSource)
    }

    // MARK: - Selection

    func toggleSelectionMode() {
        isSelectionMode.toggle()
        selectedItems.removeAll()
    }

    func toggleSelection(_ item: FileSystemItem) {
        selectedItems = SelectionSet.toggling(item, in: selectedItems)
    }

    func selectAll() {
        selectedItems = SelectionSet.selectingAll(items, searchText: searchText)
    }

    func clearSelection() {
        selectedItems.removeAll()
    }

    /// Home's swipe actions drive the root browser without going through a row.
    func select(_ item: FileSystemItem) {
        selectedItems = [item]
    }

    // MARK: - Create / rename

    func createCollectionTapped() {
        isCreatingCollection = true
        inputText = ""
    }

    func renameItemTapped(_ item: FileSystemItem) {
        renamingItem = item
        inputText = item.name
    }

    func cancelNameInput() {
        isCreatingCollection = false
        renamingItem = nil
    }

    func confirmNameInput() {
        if isCreatingCollection {
            let name = inputText.isEmpty ? "New Collection" : inputText
            isCreatingCollection = false
            createCollection(named: name)
        } else if let item = renamingItem {
            renamingItem = nil
            rename(item, to: inputText)
        }
    }

    private func createCollection(named name: String) {
        workTask = Task { [weak self, fileManager, currentDirectory] in
            do {
                try await fileManager.createCollection(name, currentDirectory)
            } catch {
                self?.operationError = error.localizedDescription
                return
            }
            self?.refreshFiles()

            // Navigate straight into the folder just created.
            let parentURL = currentDirectory ?? fileManager.documentsDirectory()
            let folderURL = parentURL.appendingPathComponent(name, isDirectory: true)
            guard FileManager.default.fileExists(atPath: folderURL.path) else { return }
            let creationDate = (try? folderURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            self?.onCollectionTapped(CollectionItem(
                id: folderURL, url: folderURL, name: name, creationDate: creationDate
            ))
        }
    }

    private func rename(_ item: FileSystemItem, to input: String) {
        let ext = item.url.pathExtension
        let isFile: Bool = { if case .file = item { return true }; return false }()
        let finalName = (isFile && !ext.isEmpty && !input.hasSuffix(".\(ext)"))
            ? "\(input).\(ext)"
            : input
        let itemURL = item.url

        workTask = Task { [weak self, fileManager] in
            do {
                try await fileManager.renameItem(itemURL, finalName)
            } catch {
                self?.operationError = error.localizedDescription
                return
            }
            self?.refreshFiles()
        }
    }

    // MARK: - Delete

    func deleteSelectedTapped() {
        isConfirmingDelete = true
    }

    func confirmDelete() {
        let itemsToDelete = selectedItems
        selectedItems.removeAll()
        isSelectionMode = false
        isConfirmingDelete = false

        // Before the work starts, and carrying the items — they are already cleared above.
        onWillRemoveItems(itemsToDelete)

        workTask = Task { [weak self, fileManager] in
            // Each item is attempted even if an earlier one failed: the caller has already been
            // told all of them are going (`onWillRemoveItems` fires before this runs), so
            // abandoning the batch on the first error would leave the app disagreeing with disk
            // about several files instead of one.
            var failures: [String] = []
            for item in itemsToDelete {
                do {
                    try await fileManager.deleteItem(item.url)
                } catch {
                    failures.append(item.name)
                }
            }
            if !failures.isEmpty {
                self?.operationError = String(
                    localized: "Couldn't delete \(failures.count) of \(itemsToDelete.count) items"
                )
            }
            self?.refreshFiles()
        }
    }

    // MARK: - Move

    func moveItemTapped(_ item: FileSystemItem) {
        itemsToMove = [item]
        loadCollectionsForPicker()
    }

    func moveSelectedTapped() {
        itemsToMove = selectedItems
        loadCollectionsForPicker()
    }

    /// Home moves a file without a picker round trip through a row.
    func presentPicker(moving items: Set<FileSystemItem>) {
        itemsToMove = items
        loadCollectionsForPicker()
    }

    private func loadCollectionsForPicker() {
        workTask = Task { [weak self] in
            let collections = await loadAllCollectionsRecursive()
            self?.availableCollections = collections
            self?.isShowingCollectionPicker = true
        }
    }

    func cancelMove() {
        itemsToMove.removeAll()
        availableCollections.removeAll()
        isShowingCollectionPicker = false
    }

    func moveToDestination(_ destination: URL) {
        let moving = itemsToMove
        itemsToMove.removeAll()
        availableCollections.removeAll()
        isShowingCollectionPicker = false
        selectedItems.removeAll()
        isSelectionMode = false

        onWillRemoveItems(moving)

        workTask = Task { [weak self] in
            for item in moving where item.url.deletingLastPathComponent().path != destination.path {
                // `limit: 100` preserves this site's pre-existing bail-out. On reaching it the
                // returned URL still collides and the move below throws — kept as it was rather
                // than silently fixed. See UniqueNameResolverTests.
                let targetURL = UniqueNameResolver.resolve(
                    baseName: item.url.deletingPathExtension().lastPathComponent,
                    ext: item.url.pathExtension,
                    in: destination,
                    limit: 100
                )
                do {
                    try FileManager.default.moveItem(at: item.url, to: targetURL)
                } catch {
                    // Was `print(_:)`, which in a shipping build goes nowhere a user can see.
                    await MainActor.run { self?.operationError = error.localizedDescription }
                }
            }
            self?.refreshFiles()
        }
    }

    // MARK: - Import

    func importFiles(_ urls: [URL]) {
        workTask = Task { [weak self, fileManager, currentDirectory] in
            await FolderImport.run(urls: urls, into: currentDirectory, fileManager: fileManager)
            self?.refreshFiles()
        }
    }
}

// MARK: - Collection discovery

/// Every subfolder of Documents, recursively — the destinations offered by the move picker.
/// Moved here from `CollectionsFeature.swift` unchanged; it never referenced TCA.
func loadAllCollectionsRecursive() async -> [CollectionItem] {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    var result: [CollectionItem] = []

    func walk(_ dir: URL) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in contents {
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey])
            guard resourceValues?.isDirectory ?? false else { continue }
            result.append(CollectionItem(
                id: url,
                url: url,
                name: url.lastPathComponent,
                creationDate: resourceValues?.creationDate ?? Date()
            ))
            walk(url)
        }
    }

    walk(documents)
    return result
}
