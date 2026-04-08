import AVFoundation
import ComposableArchitecture
import CryptoKit
import Foundation

@DependencyClient
struct FileManagerClient {
    var listItems: @Sendable (URL?) async throws -> [FileSystemItem]
    var createFolder: @Sendable (String, URL?) async throws -> Void
    var createFolderForImport: @Sendable () async throws -> URL
    var deleteItem: @Sendable (URL) async throws -> Void
    var moveItem: @Sendable (URL, URL) async throws -> Void
    var renameItem: @Sendable (URL, String) async throws -> Void
    var importFile: @Sendable (URL, URL?) async throws -> Void
    var getMetadata: @Sendable (URL) async throws -> AudioFile
    var documentsDirectory: @Sendable () -> URL = { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
}

extension FileManagerClient: DependencyKey {
    static let liveValue: FileManagerClient = {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

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
                    throw NSError(domain: "FileManagerClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Access Denied: \(targetPath.path) is not in \(rootPath.path)"])
                }

                let audioExtensions = ["mp3", "m4a", "wav", "aac", "flac", "aiff", "m4b", "mp4", "opus", "ogg"]
                
                let contents = try FileManager.default.contentsOfDirectory(
                    at: targetPath,
                    includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
                
                return try await withThrowingTaskGroup(of: FileSystemItem?.self) { group in
                    for url in contents {
                        group.addTask {
                            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey])
                            let isDirectory = resourceValues?.isDirectory ?? false
                            let creationDate = resourceValues?.creationDate ?? Date()
                            
                            if isDirectory {
                                // Calculate stats for the folder (shallow)
                                let subContents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
                                let audioCount = subContents.filter { audioExtensions.contains($0.pathExtension.lowercased()) }.count
                                let subfolderCount = subContents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }.count
                                
                                return .folder(Folder(
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
            createFolder: { name, parentURL in
                let targetPath = parentURL ?? documentsDirectory

                var finalName = name
                var newFolderURL = targetPath.appendingPathComponent(finalName)
                var counter = 2

                while FileManager.default.fileExists(atPath: newFolderURL.path) {
                    finalName = "\(name) \(counter)"
                    newFolderURL = targetPath.appendingPathComponent(finalName)
                    counter += 1
                }

                try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: false)
            },
            createFolderForImport: {
                var newFolderName = "New Folder"
                var counter = 1
                var proposedFolderURL = documentsDirectory.appendingPathComponent(newFolderName)

                while FileManager.default.fileExists(atPath: proposedFolderURL.path) {
                    counter += 1
                    newFolderName = "New Folder \(counter)"
                    proposedFolderURL = documentsDirectory.appendingPathComponent(newFolderName)
                }

                try FileManager.default.createDirectory(at: proposedFolderURL, withIntermediateDirectories: false)
                return proposedFolderURL
            },
            deleteItem: { url in
                try FileManager.default.removeItem(at: url)
            },
            moveItem: { from, toDirectory in
                // toDirectory is the destination folder, we need to append the filename
                let fileName = from.lastPathComponent
                let destination = toDirectory.appendingPathComponent(fileName)

                // Handle duplicate names
                var finalDestination = destination
                var counter = 2
                let nameWithoutExtension = from.deletingPathExtension().lastPathComponent
                let fileExtension = from.pathExtension

                while FileManager.default.fileExists(atPath: finalDestination.path) {
                    let newName = fileExtension.isEmpty ? "\(nameWithoutExtension) \(counter)" : "\(nameWithoutExtension) \(counter).\(fileExtension)"
                    finalDestination = toDirectory.appendingPathComponent(newName)
                    counter += 1
                }

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
                    throw NSError(domain: "FileManagerClient", code: 3, userInfo: [NSLocalizedDescriptionKey: "Source file not readable: \(sourceURL.lastPathComponent)"])
                }

                let fileName = sourceURL.lastPathComponent
                var destinationURL = finalDestinationDirectory.appendingPathComponent(fileName)

                // Handle duplicate names
                var counter = 2
                let nameWithoutExtension = sourceURL.deletingPathExtension().lastPathComponent
                let fileExtension = sourceURL.pathExtension

                while FileManager.default.fileExists(atPath: destinationURL.path) {
                    let newName = fileExtension.isEmpty ? "\(nameWithoutExtension) \(counter)" : "\(nameWithoutExtension) \(counter).\(fileExtension)"
                    destinationURL = finalDestinationDirectory.appendingPathComponent(newName)
                    counter += 1
                }

                // Use Data read/write instead of copyItem to avoid corruption
                do {
                    let fileData = try Data(contentsOf: sourceURL)
                    try fileData.write(to: destinationURL, options: .atomic)
                } catch {
                    throw NSError(domain: "FileManagerClient", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to import \(fileName): \(error.localizedDescription)"])
                }

                // Validate the imported file can be read as audio
                do {
                    _ = try AVAudioPlayer(contentsOf: destinationURL)
                } catch {
                    // File is corrupted, delete it and throw error
                    try? FileManager.default.removeItem(at: destinationURL)
                    throw NSError(domain: "FileManagerClient", code: 5, userInfo: [NSLocalizedDescriptionKey: "Imported file is corrupted or invalid: \(fileName)"])
                }
            },
            getMetadata: getMetadata,
            documentsDirectory: { documentsDirectory }
        )
    }()

    static let testValue = Self(
        listItems: { _ in [] },
        createFolder: { _, _ in },
        createFolderForImport: { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] },
        deleteItem: { _ in },
        moveItem: { _, _ in },
        renameItem: { _, _ in },
        importFile: { _, _ in },
        getMetadata: { url in
            AudioFile(
                url: url,
                title: "Test",
                duration: 0,
                fileSize: 0,
                format: .mp3,
                creationDate: Date()
            )
        },
        documentsDirectory: { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    )
}

extension DependencyValues {
    var fileManager: FileManagerClient {
        get { self[FileManagerClient.self] }
        set { self[FileManagerClient.self] = newValue }
    }
}
