import AVFoundation
import CryptoKit
import Foundation

struct FileManagerClient: Sendable {
    var listItems: @Sendable (URL?) async throws -> [FileSystemItem]
    var createCollection: @Sendable (String, URL?) async throws -> Void
    var createCollectionForImport: @Sendable () async throws -> URL
    var deleteItem: @Sendable (URL) async throws -> Void
    var moveItem: @Sendable (URL, URL) async throws -> Void
    var renameItem: @Sendable (URL, String) async throws -> Void
    var importFile: @Sendable (URL, URL?) async throws -> Void
    var getMetadata: @Sendable (URL) async throws -> AudioFile
    /// Empties iOS's hand-off directory. See `ImportFilter.stagingDirectoryName` (#41).
    ///
    /// Synchronous on purpose — the only member here that does I/O without being `async`. Its
    /// caller runs at `scenePhase == .background`, where an `async` hop is not merely slower: it
    /// does not reliably run at all. Measured 2026-08-08: the app suspends before the continuation
    /// is scheduled, and the work lands on the *next foreground* instead, which is exactly when an
    /// `.onOpenURL` import may be in flight over the same directory.
    var drainStagingDirectory: @Sendable () throws -> Void
    var documentsDirectory: @Sendable () -> URL = { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    /// The share extension's App Group container, or nil when the entitlement is absent (#112).
    ///
    /// **Here rather than as a closure on `AppViewModel`, and that placement was a review finding.**
    /// The first version reached `FileManager.containerURL` directly from the view model, which
    /// meant the only way to stop a test draining the *real* container into the *real* Documents
    /// directory was to remember to override a bespoke seam — and the pre-existing suite did not.
    /// The unit-test bundle is hosted by the app, which carries the entitlement, so that lookup
    /// succeeded and any test calling `scenePhaseChanged` moved whatever a developer had actually
    /// shared. Routing it through the client makes `.test` safe by construction instead.
    ///
    /// CLAUDE.md's layering table already said so: a Client is warranted when code touches a system
    /// framework or the filesystem.
    var shareInboxContainer: @Sendable () -> URL? = { nil }
}

extension FileManagerClient {
    static let live: FileManagerClient = {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let shareInboxContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ShareInbox.appGroupIdentifier
        )

        @Sendable func stableAudioID(for url: URL) -> UUID {
            let path = url.standardizedFileURL.path
            let digest = SHA256.hash(data: Data(path.utf8))
            let bytes = Array(digest.prefix(16)).map { UInt8($0) }
            return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        }

        let getMetadata: @Sendable (URL) async throws -> AudioFile = { url in
            // Get duration with fallback to AVAudioPlayer
            var duration: TimeInterval = 0
            do {
                let asset = AVURLAsset(url: url)
                duration = try await asset.load(.duration).seconds
            } catch {
                // Fallback: try AVAudioPlayer which is more forgiving for MP3s
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    duration = player.duration
                }
            }

            let resources = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let fileSize = Int64(resources.fileSize ?? 0)
            let creationDate = resources.creationDate ?? Date()

            let format: AudioFormat
            switch url.pathExtension.lowercased() {
            case "mp3": format = .mp3
            case "m4a": format = .m4a
            case "wav": format = .wav
            case "aac": format = .aac
            case "flac": format = .flac
            case "aiff": format = .aiff
            case "m4b": format = .m4b
            case "mp4": format = .mp4
            default: format = .mp3
            }

            let title = url.deletingPathExtension().lastPathComponent

            return AudioFile(
                id: stableAudioID(for: url),
                url: url,
                title: title,
                duration: duration,
                fileSize: fileSize,
                format: format,
                creationDate: creationDate
            )
        }

        return Self(
            listItems: { directoryURL in
                let rootPath = documentsDirectory.resolvingSymlinksInPath()
                let targetPath = (directoryURL ?? rootPath).resolvingSymlinksInPath()
                
                // Security check to ensure we don't go above documents
                guard targetPath.path.hasPrefix(rootPath.path) else {
                    throw FileError.outsideLibrary(attempted: targetPath, root: rootPath)
                }

                let audioExtensions = ["mp3", "m4a", "wav", "aac", "flac", "aiff", "m4b", "mp4", "opus", "ogg"]
                
                // `Documents/Inbox` is iOS's hand-off queue, not a collection the user made — and
                // it is not hidden, so `.skipsHiddenFiles` does not exclude it. Before #41 it
                // surfaced on Home as a collection nobody created. (#41)
                let contents = try FileManager.default.contentsOfDirectory(
                    at: targetPath,
                    includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                ).filter { !ImportFilter.isStagingDirectory($0, under: documentsDirectory) }

                return try await withThrowingTaskGroup(of: FileSystemItem?.self) { group in
                    for url in contents {
                        group.addTask {
                            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey])
                            let isDirectory = resourceValues?.isDirectory ?? false
                            let creationDate = resourceValues?.creationDate ?? Date()
                            
                            if isDirectory {
                                // Count audio files recursively (includes nested folders)
                                func countAudioFiles(in directory: URL) -> Int {
                                    let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
                                    var count = 0
                                    for item in items {
                                        let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                                        if isDir {
                                            count += countAudioFiles(in: item)
                                        } else if audioExtensions.contains(item.pathExtension.lowercased()) {
                                            count += 1
                                        }
                                    }
                                    return count
                                }
                                let audioCount = countAudioFiles(in: url)
                                let subContents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
                                let subfolderCount = subContents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }.count
                                
                                return .folder(CollectionItem(
                                    id: url,
                                    url: url,
                                    name: url.lastPathComponent,
                                    creationDate: creationDate,
                                    itemCount: audioCount,
                                    subfolderCount: subfolderCount,
                                    totalDuration: 0
                                ))
                            } else {
                                if audioExtensions.contains(url.pathExtension.lowercased()) {
                                    return .file(try await getMetadata(url))
                                }
                            }
                            return nil
                        }
                    }

                    var items: [FileSystemItem] = []
                    for try await item in group {
                        if let item = item {
                            items.append(item)
                        }
                    }
                    // Sort folders first, then files
                    return items.sorted {
                        switch ($0, $1) {
                        case (.folder, .file): return true
                        case (.file, .folder): return false
                        case (.folder(let f1), .folder(let f2)): return f1.name < f2.name
                        case (.file(let f1), .file(let f2)): return f1.title < f2.title
                        }
                    }
                }
            },
            createCollection: { name, parentURL in
                let targetPath = parentURL ?? documentsDirectory

                let newCollectionURL = UniqueNameResolver.resolve(baseName: name, in: targetPath)
                try FileManager.default.createDirectory(at: newCollectionURL, withIntermediateDirectories: false)
            },
            createCollectionForImport: {
                let proposedCollectionURL = UniqueNameResolver.resolve(
                    baseName: "New Collection", in: documentsDirectory
                )
                try FileManager.default.createDirectory(at: proposedCollectionURL, withIntermediateDirectories: false)
                return proposedCollectionURL
            },
            deleteItem: { url in
                try FileManager.default.removeItem(at: url)
            },
            moveItem: { from, toDirectory in
                // toDirectory is the destination folder; the filename is appended, deduped
                let finalDestination = UniqueNameResolver.resolve(
                    baseName: from.deletingPathExtension().lastPathComponent,
                    ext: from.pathExtension,
                    in: toDirectory
                )

                try FileManager.default.moveItem(at: from, to: finalDestination)
            },
            renameItem: { url, newName in
                let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
                try FileManager.default.moveItem(at: url, to: newURL)
            },
            importFile: { sourceURL, destinationDirectory in
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let finalDestinationDirectory = destinationDirectory ?? documentsDirectory

                // Start accessing security-scoped resource
                let needsAccess = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if needsAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }

                // Verify source file is readable
                guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
                    throw FileError.unreadableSource(sourceURL)
                }

                let fileName = sourceURL.lastPathComponent

                // **Already here? Then stop.** See `ImportDedupe` — the resolver below cannot
                // answer this, because avoiding a collision is the opposite of noticing one.
                let sourceSize = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path))
                    .flatMap { $0[.size] as? NSNumber }?.int64Value
                if let sourceSize {
                    let siblings = (try? FileManager.default.contentsOfDirectory(
                        at: finalDestinationDirectory,
                        includingPropertiesForKeys: [.fileSizeKey],
                        options: [.skipsHiddenFiles]
                    )) ?? []
                    let existing = siblings.compactMap { url -> ImportDedupe.Existing? in
                        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                        else { return nil }
                        return ImportDedupe.Existing(name: url.lastPathComponent, size: Int64(size))
                    }
                    if ImportDedupe.isAlreadyPresent(
                        name: fileName, size: sourceSize, in: existing
                    ) {
                        return
                    }
                }

                let destinationURL = UniqueNameResolver.resolve(
                    baseName: sourceURL.deletingPathExtension().lastPathComponent,
                    ext: sourceURL.pathExtension,
                    in: finalDestinationDirectory
                )

                // Use Data read/write instead of copyItem to avoid corruption
                do {
                    let fileData = try Data(contentsOf: sourceURL)
                    try fileData.write(to: destinationURL, options: .atomic)
                } catch {
                    throw FileError.importFailed(name: fileName, underlying: error)
                }

                // Validate the imported file can be read as audio
                do {
                    _ = try AVAudioPlayer(contentsOf: destinationURL)
                } catch {
                    // File is corrupted, delete it and throw error
                    try? FileManager.default.removeItem(at: destinationURL)
                    throw FileError.corruptImport(name: fileName)
                }
            },
            getMetadata: getMetadata,
            // Deletes contents, not the directory: iOS owns `Inbox` and recreates it on the next
            // hand-off, so removing it is a fight with the system for no gain. Everything in here
            // is a copy iOS made — the user's original is wherever they keep it — which is what
            // makes a delete the right operation and not a destructive one. (#41)
            drainStagingDirectory: {
                let staging = ImportFilter.stagingDirectory(under: documentsDirectory)
                guard FileManager.default.fileExists(atPath: staging.path) else { return }
                for item in try FileManager.default.contentsOfDirectory(
                    at: staging, includingPropertiesForKeys: nil
                ) {
                    try FileManager.default.removeItem(at: item)
                }
            },
            documentsDirectory: { documentsDirectory },
            // Resolved once, not per call. `containerURL` is a synchronous cross-process lookup and
            // the value is fixed for the process lifetime; the drain runs on every scene phase
            // change, so re-asking was several IPCs per app switch on the main actor.
            shareInboxContainer: { shareInboxContainer }
        )
    }()
}

