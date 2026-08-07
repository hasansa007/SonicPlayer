import ComposableArchitecture
import Foundation

@Reducer
struct CollectionsFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var id: URL? { currentDirectory }
        var currentDirectory: URL? // nil is root
        var items: [FileSystemItem] = []
        
        // Child States
        var collectionCards: IdentifiedArrayOf<CollectionItemCardFeature.State> = []
        var fileRows: IdentifiedArrayOf<FileRowFeature.State> = []

        var isLoading = false
        var searchText = ""
        var isSelectionMode = false
        var selectedItems: Set<FileSystemItem> = []
        @Presents var alert: AlertState<Action.Alert>?
        /// The file the editor is open on, or nil. Holds the **value**, not the editor's state:
        /// `EditRecordingFeature` became a view model in #17, and a reducer's value-typed `State`
        /// cannot store a reference. The view builds the model. Slice 9 (#18) collapses this seam.
        var audioToEdit: AudioFile?

        // Input State
        var isCreatingCollection = false
        var renamingItem: FileSystemItem?
        var inputText = ""

        // Move State
        var itemsToMove: Set<FileSystemItem> = []
        var isShowingCollectionPicker = false
        var availableCollections: [CollectionItem] = []
        
        var documentsDirectoryURL: URL?

        /// The audio files in this directory, in display order. Extracted from four identical
        /// `compactMap` blocks in AppFeature that built the playback queue (#15).
        var audioFiles: [AudioFile] {
            items.compactMap { item in
                if case let .file(audioFile) = item { return audioFile }
                return nil
            }
        }

        var filteredItems: [FileSystemItem] {
            SelectionSet.matching(items, searchText: searchText)
        }
        
        var filteredCollectionCards: IdentifiedArrayOf<CollectionItemCardFeature.State> {
            let filteredIDs = Set(filteredItems.compactMap { item -> String? in
                if case let .folder(f) = item { return f.id.absoluteString }
                return nil
            })
            return collectionCards.filter { filteredIDs.contains($0.id.absoluteString) }
        }
        
        var filteredFileRows: IdentifiedArrayOf<FileRowFeature.State> {
            let filteredIDs = Set(filteredItems.compactMap { item -> UUID? in
                if case let .file(f) = item { return f.id }
                return nil
            })
            return fileRows.filter { filteredIDs.contains($0.id) }
        }
    }

    enum Action {
        case onAppear
        case refreshFiles
        case itemsLoaded([FileSystemItem])
        case loadFailed
        
        case collectionCards(IdentifiedActionOf<CollectionItemCardFeature>)
        case fileRows(IdentifiedActionOf<FileRowFeature>)
        
        case collectionTapped(CollectionItem)
        case fileTapped(AudioFile)
        case setSearchText(String)

        // Selection & Mode
        case toggleSelectionMode
        case toggleSelection(FileSystemItem)
        case selectAll
        case clearSelection

        // Operations
        case createCollectionTapped
        case renameItemTapped(FileSystemItem)
        case setInputText(String)
        case confirmNameInput
        case cancelNameInput
        case importFiles([URL])

        case deleteSelectedTapped
        case moveItemTapped(FileSystemItem)
        case moveSelectedTapped
        case loadCollectionsForPicker
        case collectionsLoaded([CollectionItem])
        case moveToDestination(URL)

        /// Announces the items an operation is about to remove from their current location —
        /// deleted outright, or moved elsewhere.
        ///
        /// This exists because a parent cannot read the answer out of state. A `Scope` child runs
        /// before the parent's `Reduce`, and both the delete and move handlers clear
        /// `selectedItems` / `itemsToMove` as they start, so by the time the parent looks the set
        /// is empty. Carrying the items in the action is the only way the parent can see them.
        /// See #22; this is the delegate shape #19 generalises.
        case willRemoveItems(Set<FileSystemItem>)
        case cancelMove
        case alert(PresentationAction<Alert>)
        case playAllTapped
        case editAudioDismissed

        enum Alert: Equatable {
            case confirmDelete
        }
    }

    @Dependency(\.fileManager) var fileManager

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear, .refreshFiles:
                // In screenshot mode, skip loading real files to preserve demo data
                if ScreenshotMode.isEnabled && !state.items.isEmpty {
                    return .none
                }
                state.isLoading = true
                state.documentsDirectoryURL = fileManager.documentsDirectory()
                return .run { [directory = state.currentDirectory] send in
                    do {
                        let items = try await fileManager.listItems(directory)
                        await send(.itemsLoaded(items))
                    } catch {
                        await send(.loadFailed)
                    }
                }

            case let .itemsLoaded(items):
                state.isLoading = false
                state.items = items
                
                // Populate collectionCards
                let folders = items.compactMap { item -> CollectionItem? in
                    if case let .folder(f) = item { return f }
                    return nil
                }
                
                var newCollectionCards: IdentifiedArrayOf<CollectionItemCardFeature.State> = []
                for folder in folders {
                    if let existing = state.collectionCards[id: folder.id] {
                        var updated = existing
                        if updated.folder != folder {
                             newCollectionCards.append(CollectionItemCardFeature.State(folder: folder))
                        } else {
                            updated.isSelected = state.selectedItems.contains(.folder(folder))
                            newCollectionCards.append(updated)
                        }
                    } else {
                        newCollectionCards.append(CollectionItemCardFeature.State(
                            folder: folder,
                            isSelected: state.selectedItems.contains(.folder(folder))
                        ))
                    }
                }
                state.collectionCards = newCollectionCards

                // Populate fileRows
                let files = items.compactMap { item -> AudioFile? in
                    if case let .file(f) = item { return f }
                    return nil
                }

                var newFileRows: IdentifiedArrayOf<FileRowFeature.State> = []
                for file in files {
                    if let existing = state.fileRows[id: file.id] {
                        var updated = existing
                        if updated.file != file {
                            newFileRows.append(FileRowFeature.State(file: file))
                        } else {
                            updated.isSelected = state.selectedItems.contains(.file(file))
                            newFileRows.append(updated)
                        }
                    } else {
                        newFileRows.append(FileRowFeature.State(
                            file: file,
                            isSelected: state.selectedItems.contains(.file(file))
                        ))
                    }
                }
                state.fileRows = newFileRows

                return .none

            case .loadFailed:
                state.isLoading = false
                return .none
                
            case let .collectionCards(.element(id: id, action: .tapped)):
                if let folder = state.collectionCards[id: id]?.folder {
                    if state.isSelectionMode {
                        return .send(.toggleSelection(.folder(folder)))
                    } else {
                        return .send(.collectionTapped(folder))
                    }
                }
                return .none
                
            case let .collectionCards(.element(id: id, action: .moveTapped)):
                 if let folder = state.collectionCards[id: id]?.folder {
                     return .send(.moveItemTapped(.folder(folder)))
                 }
                 return .none

            case let .collectionCards(.element(id: id, action: .renameTapped)):
                 if let folder = state.collectionCards[id: id]?.folder {
                     return .send(.renameItemTapped(.folder(folder)))
                 }
                 return .none

            case let .collectionCards(.element(id: id, action: .deleteTapped)):
                 if let folder = state.collectionCards[id: id]?.folder {
                     state.selectedItems = [.folder(folder)]
                     return .send(.deleteSelectedTapped)
                 }
                 return .none
                 
            case let .collectionCards(.element(id: id, action: .toggleSelection)):
                if let folder = state.collectionCards[id: id]?.folder {
                    return .send(.toggleSelection(.folder(folder)))
                }
                return .none
                
            case let .fileRows(.element(id: id, action: .tapped)):
                if let file = state.fileRows[id: id]?.file {
                    if state.isSelectionMode {
                        return .send(.toggleSelection(.file(file)))
                    } else {
                        return .send(.fileTapped(file))
                    }
                }
                return .none

            case let .fileRows(.element(id: id, action: .moveTapped)):
                if let file = state.fileRows[id: id]?.file {
                    return .send(.moveItemTapped(.file(file)))
                }
                return .none

            case let .fileRows(.element(id: id, action: .renameTapped)):
                if let file = state.fileRows[id: id]?.file {
                    return .send(.renameItemTapped(.file(file)))
                }
                return .none

            case let .fileRows(.element(id: id, action: .deleteTapped)):
                if let file = state.fileRows[id: id]?.file {
                    state.selectedItems = [.file(file)]
                    return .send(.deleteSelectedTapped)
                }
                return .none

            case let .fileRows(.element(id: id, action: .editTapped)):
                if let file = state.fileRows[id: id]?.file {
                    state.audioToEdit = file
                }
                return .none

            case let .fileRows(.element(id: id, action: .toggleSelection)):
                if let file = state.fileRows[id: id]?.file {
                    return .send(.toggleSelection(.file(file)))
                }
                return .none

            case .collectionCards, .fileRows:
                return .none

            case .playAllTapped:
                // Handled by parent — plays all files in current folder
                return .none

            case .collectionTapped:
                // Handled by parent
                return .none

            case .fileTapped:
                // Handled by parent
                return .none

            case let .setSearchText(text):
                state.searchText = text
                return .none
                
            case .toggleSelectionMode:
                state.isSelectionMode.toggle()
                state.selectedItems.removeAll()
                // Update isSelected in collectionCards and fileRows
                for id in state.collectionCards.ids {
                    state.collectionCards[id: id]?.isSelected = false
                }
                for id in state.fileRows.ids {
                    state.fileRows[id: id]?.isSelected = false
                }
                return .none
                
            case let .toggleSelection(item):
                state.selectedItems = SelectionSet.toggling(item, in: state.selectedItems)
                let isSelected = state.selectedItems.contains(item)
                if case let .folder(folder) = item {
                    state.collectionCards[id: folder.id]?.isSelected = isSelected
                } else if case let .file(file) = item {
                    state.fileRows[id: file.id]?.isSelected = isSelected
                }
                return .none

            case .selectAll:
                state.selectedItems = SelectionSet.selectingAll(state.items, searchText: state.searchText)
                for item in state.filteredItems {
                    if case let .folder(folder) = item {
                        state.collectionCards[id: folder.id]?.isSelected = true
                    } else if case let .file(file) = item {
                        state.fileRows[id: file.id]?.isSelected = true
                    }
                }
                return .none
                
            case .clearSelection:
                state.selectedItems.removeAll()
                for id in state.collectionCards.ids {
                    state.collectionCards[id: id]?.isSelected = false
                }
                for id in state.fileRows.ids {
                    state.fileRows[id: id]?.isSelected = false
                }
                return .none
                
            case .createCollectionTapped:
                state.isCreatingCollection = true
                state.inputText = ""
                return .none
                
            case let .renameItemTapped(item):
                state.renamingItem = item
                state.inputText = item.name
                return .none
                
            case let .setInputText(text):
                state.inputText = text
                return .none
                
            case .confirmNameInput:
                if state.isCreatingCollection {
                    let name = state.inputText.isEmpty ? "New Collection" : state.inputText
                    let directory = state.currentDirectory
                    state.isCreatingCollection = false
                    return .run { send in
                        try await fileManager.createCollection(name, directory)
                        await send(.refreshFiles)
                        // Navigate to the newly created folder
                        let parentURL = directory ?? fileManager.documentsDirectory()
                        let folderURL = parentURL.appendingPathComponent(name, isDirectory: true)
                        if FileManager.default.fileExists(atPath: folderURL.path) {
                            let creationDate = (try? folderURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                            let folder = CollectionItem(id: folderURL, url: folderURL, name: name, creationDate: creationDate)
                            await send(.collectionTapped(folder))
                        }
                    }
                } else if let item = state.renamingItem {
                    let input = state.inputText
                    let ext = item.url.pathExtension
                    let isFile: Bool = {
                        if case .file = item { return true }
                        return false
                    }()
                    let finalName: String
                    if isFile && !ext.isEmpty && !input.hasSuffix(".\(ext)") {
                        finalName = "\(input).\(ext)"
                    } else {
                        finalName = input
                    }
                    let itemURL = item.url
                    state.renamingItem = nil
                    return .run { send in
                        try await fileManager.renameItem(itemURL, finalName)
                        await send(.refreshFiles)
                    }
                }
                return .none
                
            case .cancelNameInput:
                state.isCreatingCollection = false
                state.renamingItem = nil
                return .none

            case let .importFiles(urls):
                let directory = state.currentDirectory
                return .run { send in
                    let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "aiff", "m4b", "mp4", "opus", "ogg"]
                    let containsFolder = urls.contains { url in
                        let accessing = url.startAccessingSecurityScopedResource()
                        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    }

                    func createUniqueFolder(named name: String, in parent: URL) throws -> URL {
                        let folderURL = UniqueNameResolver.resolve(baseName: name, in: parent)
                        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
                        return folderURL
                    }

                    func importFolder(_ folderURL: URL, into destinationDirectory: URL?) async throws -> (success: Int, failed: Int) {
                        let needsAccess = folderURL.startAccessingSecurityScopedResource()
                        defer {
                            if needsAccess {
                                folderURL.stopAccessingSecurityScopedResource()
                            }
                        }

                        let parent = destinationDirectory ?? fileManager.documentsDirectory()
                        let destinationRoot = try createUniqueFolder(named: folderURL.lastPathComponent, in: parent)

                        var success = 0
                        var failed = 0

                        let keys: [URLResourceKey] = [.isDirectoryKey]
                        let enumerator = FileManager.default.enumerator(
                            at: folderURL,
                            includingPropertiesForKeys: keys,
                            options: [.skipsHiddenFiles]
                        )

                        while let next = enumerator?.nextObject() as? URL {
                            let resourceValues = try? next.resourceValues(forKeys: [.isDirectoryKey])
                            if resourceValues?.isDirectory == true {
                                continue
                            }

                            let ext = next.pathExtension.lowercased()
                            guard audioExtensions.contains(ext) else { continue }

                            let relativePath = next.path
                                .replacingOccurrences(of: folderURL.path + "/", with: "")
                            let relativeDir = (relativePath as NSString).deletingLastPathComponent

                            var targetDir = destinationRoot
                            if !relativeDir.isEmpty && relativeDir != "." {
                                targetDir = destinationRoot.appendingPathComponent(relativeDir, isDirectory: true)
                                try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
                            }

                            do {
                                try await fileManager.importFile(next, targetDir)
                                success += 1
                            } catch {
                                failed += 1
                            }
                        }

                        return (success, failed)
                    }

                    print("📥 Starting import of \(urls.count) item(s)")
                    print("   Current directory: \(directory?.path ?? "root")")

                    var successCount = 0
                    var failCount = 0

                    // If importing to root, always create a new folder for the files
                    var targetDirectory = directory
                    if directory == nil, !containsFolder {
                        do {
                            targetDirectory = try await fileManager.createCollectionForImport()
                            print("📁 Created import folder: \(targetDirectory?.path ?? "nil")")
                        } catch {
                            print("❌ Failed to create import folder: \(error.localizedDescription)")
                            // Fall back to importing to root
                        }
                    }

                    for (index, url) in urls.enumerated() {
                        let accessing = url.startAccessingSecurityScopedResource()
                        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                        print("📄 Importing \(isDirectory ? "folder" : "file") \(index + 1)/\(urls.count): \(url.lastPathComponent)")
                        do {
                            if isDirectory {
                                let (success, failed) = try await importFolder(url, into: targetDirectory)
                                successCount += success
                                failCount += failed
                            } else {
                                let ext = url.pathExtension.lowercased()
                                guard audioExtensions.contains(ext) else {
                                    print("⏭️ Skipping non-audio file: \(url.lastPathComponent)")
                                    continue
                                }
                                try await fileManager.importFile(url, targetDirectory)
                                successCount += 1
                            }
                        } catch {
                            print("❌ Failed to import \(url.lastPathComponent): \(error.localizedDescription)")
                            failCount += 1
                        }
                    }

                    print("📊 Import complete: \(successCount) succeeded, \(failCount) failed")
                    print("🔄 Refreshing files...")

                    await send(.refreshFiles)

                    // Show feedback to user
                    if successCount > 0 && failCount == 0 {
                        print("✅ Successfully imported \(successCount) file(s)")
                    } else if successCount > 0 && failCount > 0 {
                        print("⚠️ Imported \(successCount) file(s), \(failCount) failed")
                    } else if failCount > 0 {
                        print("❌ Failed to import \(failCount) file(s)")
                    }
                }

            case .deleteSelectedTapped:
                state.alert = AlertState {
                    TextState("Delete \(state.selectedItems.count) \(state.selectedItems.count == 1 ? "item" : "items")?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDelete) {
                        TextState("Delete")
                    }
                    ButtonState(role: .cancel) {
                        TextState("Cancel")
                    }
                }
                return .none
                
            case .alert(.presented(.confirmDelete)):
                let itemsToDelete = state.selectedItems
                state.selectedItems.removeAll()
                state.isSelectionMode = false
                return .merge(
                    .send(.willRemoveItems(itemsToDelete)),
                    .run { send in
                        for item in itemsToDelete {
                            try? await fileManager.deleteItem(item.url)
                        }
                        await send(.refreshFiles)
                    }
                )

            case .alert:
                return .none

            case .editAudioDismissed:
                // Clearing only. The refresh stays where it was — AppFeature, for the root
                // browser — so the nested-stack path keeps behaving exactly as it did.
                state.audioToEdit = nil
                return .none

            case let .moveItemTapped(item):
                state.itemsToMove = [item]
                return .send(.loadCollectionsForPicker)

            case .moveSelectedTapped:
                state.itemsToMove = state.selectedItems
                return .send(.loadCollectionsForPicker)

            case .loadCollectionsForPicker:
                return .run { send in
                    let collections = await loadAllCollectionsRecursive()
                    await send(.collectionsLoaded(collections))
                }

            case let .collectionsLoaded(collections):
                state.availableCollections = collections
                state.isShowingCollectionPicker = true
                return .none

            case let .moveToDestination(destination):
                let itemsToMove = state.itemsToMove
                state.itemsToMove.removeAll()
                state.availableCollections.removeAll()
                state.isShowingCollectionPicker = false
                state.selectedItems.removeAll()
                state.isSelectionMode = false

                return .merge(
                    .send(.willRemoveItems(itemsToMove)),
                    .run { send in
                    for item in itemsToMove {
                        if item.url.deletingLastPathComponent().path == destination.path {
                            continue
                        }

                        // `limit: 100` preserves this site's pre-existing bail-out. On reaching it
                        // the returned URL still collides and the moveItem below throws — kept as
                        // it was rather than silently fixed. See UniqueNameResolverTests.
                        let targetURL = UniqueNameResolver.resolve(
                            baseName: item.url.deletingPathExtension().lastPathComponent,
                            ext: item.url.pathExtension,
                            in: destination,
                            limit: 100
                        )

                        do {
                            try FileManager.default.moveItem(at: item.url, to: targetURL)
                            print("✅ Moved \(item.name) → \(targetURL.path)")
                        } catch {
                            print("❌ Failed to move \(item.name): \(error.localizedDescription)")
                        }
                    }
                        await send(.refreshFiles)
                    }
                )

            case .willRemoveItems:
                return .none // Handled by parent — see #22

            case .cancelMove:
                state.itemsToMove.removeAll()
                state.availableCollections.removeAll()
                state.isShowingCollectionPicker = false
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
        .forEach(\.collectionCards, action: \.collectionCards) {
            CollectionItemCardFeature()
        }
        .forEach(\.fileRows, action: \.fileRows) {
            FileRowFeature()
        }
    }
}

// MARK: - Collection Discovery

/// Recursively walks Documents directory and returns every subfolder as a CollectionItem.
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
            let isDir = resourceValues?.isDirectory ?? false
            guard isDir else { continue }
            let creationDate = resourceValues?.creationDate ?? Date()
            result.append(CollectionItem(
                id: url,
                url: url,
                name: url.lastPathComponent,
                creationDate: creationDate
            ))
            walk(url)
        }
    }

    walk(documents)
    return result
}
