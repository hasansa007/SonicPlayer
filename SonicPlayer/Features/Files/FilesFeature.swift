import ComposableArchitecture
import Foundation

@Reducer
struct FilesFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var id: URL? { currentDirectory }
        var currentDirectory: URL? // nil is root
        var items: [FileSystemItem] = []
        
        // Child States
        var folderCards: IdentifiedArrayOf<FolderCardFeature.State> = []
        var fileRows: IdentifiedArrayOf<FileRowFeature.State> = []
        var folderPicker: IdentifiedArrayOf<FolderPickerFeature.State> = []

        var isLoading = false
        var searchText = ""
        var isSelectionMode = false
        var selectedItems: Set<FileSystemItem> = []
        @Presents var alert: AlertState<Action.Alert>?
        @Presents var editAudio: EditRecordingFeature.State?

        // Input State
        var isCreatingFolder = false
        var renamingItem: FileSystemItem?
        var inputText = ""

        // Move State
        var itemsToMove: Set<FileSystemItem> = []
        var availableFolders: [Folder] = []
        var isShowingFolderPicker = false
        
        var documentsDirectoryURL: URL?
        var lastOpenedFileURL: URL?

        var filteredItems: [FileSystemItem] {
            let sortedItems: [FileSystemItem] = items
            
            if searchText.isEmpty {
                return sortedItems
            }
            return sortedItems.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        var filteredFolderCards: IdentifiedArrayOf<FolderCardFeature.State> {
            let filteredIDs = Set(filteredItems.compactMap { item -> String? in
                if case let .folder(f) = item { return f.id.absoluteString }
                return nil
            })
            return folderCards.filter { filteredIDs.contains($0.id.absoluteString) }
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
        
        case folderCards(IdentifiedActionOf<FolderCardFeature>)
        case fileRows(IdentifiedActionOf<FileRowFeature>)
        case folderPicker(IdentifiedActionOf<FolderPickerFeature>)
        
        case folderTapped(Folder)
        case fileTapped(AudioFile)
        case setSearchText(String)

        // Selection & Mode
        case toggleSelectionMode
        case toggleSelection(FileSystemItem)
        case selectAll
        case clearSelection

        // Operations
        case createFolderTapped
        case renameItemTapped(FileSystemItem)
        case setInputText(String)
        case confirmNameInput
        case cancelNameInput
        case importFiles([URL])

        case deleteSelectedTapped
        case moveItemTapped(FileSystemItem)
        case moveSelectedTapped
        case loadFoldersForMove
        case foldersForMoveLoaded([Folder])
        case selectDestinationFolder(Folder?)
        case createFolderInPicker(String)
        case cancelMove
        case alert(PresentationAction<Alert>)
        case editAudio(PresentationAction<EditRecordingFeature.Action>)

        enum Alert: Equatable {
            case confirmDelete
        }
    }

    @Dependency(\.fileManager) var fileManager

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear, .refreshFiles:
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
                
                // Populate folderCards
                let folders = items.compactMap { item -> Folder? in
                    if case let .folder(f) = item { return f }
                    return nil
                }
                
                var newFolderCards: IdentifiedArrayOf<FolderCardFeature.State> = []
                for folder in folders {
                    if let existing = state.folderCards[id: folder.id] {
                        var updated = existing
                        if updated.folder != folder {
                             newFolderCards.append(FolderCardFeature.State(folder: folder))
                        } else {
                            updated.isSelected = state.selectedItems.contains(.folder(folder))
                            newFolderCards.append(updated)
                        }
                    } else {
                        newFolderCards.append(FolderCardFeature.State(
                            folder: folder,
                            isSelected: state.selectedItems.contains(.folder(folder))
                        ))
                    }
                }
                state.folderCards = newFolderCards

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
                
            case let .folderCards(.element(id: id, action: .tapped)):
                if let folder = state.folderCards[id: id]?.folder {
                    if state.isSelectionMode {
                        return .send(.toggleSelection(.folder(folder)))
                    } else {
                        return .send(.folderTapped(folder))
                    }
                }
                return .none
                
            case let .folderCards(.element(id: id, action: .moveTapped)):
                 if let folder = state.folderCards[id: id]?.folder {
                     return .send(.moveItemTapped(.folder(folder)))
                 }
                 return .none

            case let .folderCards(.element(id: id, action: .renameTapped)):
                 if let folder = state.folderCards[id: id]?.folder {
                     return .send(.renameItemTapped(.folder(folder)))
                 }
                 return .none

            case let .folderCards(.element(id: id, action: .deleteTapped)):
                 if let folder = state.folderCards[id: id]?.folder {
                     state.selectedItems = [.folder(folder)]
                     return .send(.deleteSelectedTapped)
                 }
                 return .none
                 
            case let .folderCards(.element(id: id, action: .toggleSelection)):
                if let folder = state.folderCards[id: id]?.folder {
                    return .send(.toggleSelection(.folder(folder)))
                }
                return .none
                
            case let .fileRows(.element(id: id, action: .tapped)):
                if let file = state.fileRows[id: id]?.file {
                    if state.isSelectionMode {
                        return .send(.toggleSelection(.file(file)))
                    } else {
                        state.lastOpenedFileURL = file.url
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
                    state.editAudio = EditRecordingFeature.State(recording: file)
                }
                return .none

            case let .fileRows(.element(id: id, action: .toggleSelection)):
                if let file = state.fileRows[id: id]?.file {
                    return .send(.toggleSelection(.file(file)))
                }
                return .none

            case .folderCards, .fileRows:
                return .none

            case .folderTapped:
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
                // Update isSelected in folderCards and fileRows
                for id in state.folderCards.ids {
                    state.folderCards[id: id]?.isSelected = false
                }
                for id in state.fileRows.ids {
                    state.fileRows[id: id]?.isSelected = false
                }
                return .none
                
            case let .toggleSelection(item):
                if state.selectedItems.contains(item) {
                    state.selectedItems.remove(item)
                    if case let .folder(folder) = item {
                        state.folderCards[id: folder.id]?.isSelected = false
                    } else if case let .file(file) = item {
                        state.fileRows[id: file.id]?.isSelected = false
                    }
                } else {
                    state.selectedItems.insert(item)
                    if case let .folder(folder) = item {
                        state.folderCards[id: folder.id]?.isSelected = true
                    } else if case let .file(file) = item {
                        state.fileRows[id: file.id]?.isSelected = true
                    }
                }
                return .none
                
            case .selectAll:
                state.selectedItems = Set(state.filteredItems)
                for item in state.filteredItems {
                    if case let .folder(folder) = item {
                        state.folderCards[id: folder.id]?.isSelected = true
                    } else if case let .file(file) = item {
                        state.fileRows[id: file.id]?.isSelected = true
                    }
                }
                return .none
                
            case .clearSelection:
                state.selectedItems.removeAll()
                for id in state.folderCards.ids {
                    state.folderCards[id: id]?.isSelected = false
                }
                for id in state.fileRows.ids {
                    state.fileRows[id: id]?.isSelected = false
                }
                return .none
                
            case .createFolderTapped:
                state.isCreatingFolder = true
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
                if state.isCreatingFolder {
                    let name = state.inputText.isEmpty ? "New Folder" : state.inputText
                    let directory = state.currentDirectory
                    state.isCreatingFolder = false
                    return .run { send in
                        try await fileManager.createFolder(name, directory)
                        await send(.refreshFiles)
                    }
                } else if let item = state.renamingItem {
                    let name = state.inputText
                    state.renamingItem = nil
                    return .run { send in
                        try await fileManager.renameItem(item.url, name)
                        await send(.refreshFiles)
                    }
                }
                return .none
                
            case .cancelNameInput:
                state.isCreatingFolder = false
                state.renamingItem = nil
                return .none

            case let .importFiles(urls):
                let directory = state.currentDirectory
                return .run { send in
                    let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "aiff", "m4b", "mp4"]
                    let containsFolder = urls.contains { url in
                        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    }

                    func createUniqueFolder(named name: String, in parent: URL) throws -> URL {
                        var finalName = name
                        var folderURL = parent.appendingPathComponent(finalName, isDirectory: true)
                        var counter = 2

                        while FileManager.default.fileExists(atPath: folderURL.path) {
                            finalName = "\(name) \(counter)"
                            folderURL = parent.appendingPathComponent(finalName, isDirectory: true)
                            counter += 1
                        }

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
                            targetDirectory = try await fileManager.createFolderForImport()
                            print("📁 Created import folder: \(targetDirectory?.path ?? "nil")")
                        } catch {
                            print("❌ Failed to create import folder: \(error.localizedDescription)")
                            // Fall back to importing to root
                        }
                    }

                    for (index, url) in urls.enumerated() {
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
                    TextState("Delete \(state.selectedItems.count) items?")
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
                return .run { send in
                    for item in itemsToDelete {
                        try? await fileManager.deleteItem(item.url)
                    }
                    await send(.refreshFiles)
                }

            case .alert:
                return .none

            case .editAudio:
                return .none

            case let .moveItemTapped(item):
                state.itemsToMove = [item]
                return .send(.loadFoldersForMove)

            case .moveSelectedTapped:
                state.itemsToMove = state.selectedItems
                return .send(.loadFoldersForMove)

            case .loadFoldersForMove:
                state.isShowingFolderPicker = true
                return .run { send in
                    // Load all folders recursively
                    let allFolders = try await loadAllFolders(from: nil, fileManager: fileManager)
                    await send(.foldersForMoveLoaded(allFolders))
                }

            case let .foldersForMoveLoaded(folders):
                state.availableFolders = folders
                var rows = [FolderPickerFeature.State(folder: nil)] // Root
                rows.append(contentsOf: folders.map {
                    FolderPickerFeature.State(folder: $0, folderPath: folderPath(for: $0))
                })
                state.folderPicker = IdentifiedArray(uniqueElements: rows)
                return .none

            case let .selectDestinationFolder(folder):
                let itemsToMove = state.itemsToMove
                let destination = folder?.url ?? fileManager.documentsDirectory()

                // Check if any items are already at the destination
                let itemsAlreadyAtDestination = itemsToMove.filter { item in
                    item.url.deletingLastPathComponent() == destination
                }

                // If all items are already at destination, just dismiss
                if itemsAlreadyAtDestination.count == itemsToMove.count {
                    state.itemsToMove.removeAll()
                    state.availableFolders.removeAll()
                    state.folderPicker.removeAll()
                    state.isShowingFolderPicker = false
                    state.selectedItems.removeAll()
                    state.isSelectionMode = false
                    return .none
                }

                // Filter out items already at destination
                let itemsToActuallyMove = itemsToMove.subtracting(itemsAlreadyAtDestination)

                state.itemsToMove.removeAll()
                state.availableFolders.removeAll()
                state.folderPicker.removeAll()
                state.isShowingFolderPicker = false
                state.selectedItems.removeAll()
                state.isSelectionMode = false

                return .run { send in
                    for item in itemsToActuallyMove {
                        do {
                            try await fileManager.moveItem(item.url, destination)
                        } catch {
                            print("Failed to move \(item.name): \(error.localizedDescription)")
                        }
                    }
                    await send(.refreshFiles)
                }

            case let .createFolderInPicker(name):
                let directory = state.currentDirectory
                return .run { send in
                    try await fileManager.createFolder(name, directory)
                    // Reload folders list after creation
                    await send(.loadFoldersForMove)
                }

            case .cancelMove:
                state.itemsToMove.removeAll()
                state.availableFolders.removeAll()
                state.folderPicker.removeAll()
                state.isShowingFolderPicker = false
                return .none
                
            case let .folderPicker(.element(id: id, action: .tapped)):
                let folder = state.folderPicker[id: id]?.folder
                return .send(.selectDestinationFolder(folder))

            case .folderPicker:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
        .ifLet(\.$editAudio, action: \.editAudio) {
            EditRecordingFeature()
        }
        .forEach(\.folderCards, action: \.folderCards) {
            FolderCardFeature()
        }
        .forEach(\.fileRows, action: \.fileRows) {
            FileRowFeature()
        }
        .forEach(\.folderPicker, action: \.folderPicker) {
            FolderPickerFeature()
        }
    }
    
    private func folderPath(for folder: Folder) -> String {
        let components = folder.url.pathComponents
        if let docsIndex = components.lastIndex(of: "Documents") {
            let relevantComponents = Array(components.dropFirst(docsIndex + 1))
            return relevantComponents.dropLast().joined(separator: " / ")
        }
        return ""
    }
}

// Helper function to load all folders recursively
private func loadAllFolders(from directory: URL?, fileManager: FileManagerClient) async throws -> [Folder] {
    let items = try await fileManager.listItems(directory)
    var folders: [Folder] = []

    for item in items {
        if case .folder(let folder) = item {
            folders.append(folder)
            // Recursively load subfolders
            let subfolders = try await loadAllFolders(from: folder.url, fileManager: fileManager)
            folders.append(contentsOf: subfolders)
        }
    }

    return folders
}
