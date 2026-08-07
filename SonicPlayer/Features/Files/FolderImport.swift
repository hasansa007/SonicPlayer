import Foundation

/// The recursive folder import, lifted out of `CollectionsFeature`'s largest effect (#18).
///
/// It is here rather than in `Domain/` because it is almost entirely I/O: security-scoped resource
/// access, directory enumeration and per-file copies. The parts of it that are *decisions* —
/// which extensions count as audio, and where a nested file lands relative to the import root —
/// live in `Domain/ImportFilter` and are tested there.
///
/// Behaviour is preserved exactly, including the quiet ones:
/// - a non-audio file is skipped, not reported
/// - importing loose files **into the root** creates a new collection to hold them, but importing
///   a folder does not
/// - a per-file failure is counted and the import continues
enum FolderImport {

    struct Result: Equatable {
        var succeeded = 0
        var failed = 0
    }

    @discardableResult
    static func run(
        urls: [URL],
        into directory: URL?,
        fileManager: FileManagerClient
    ) async -> Result {
        var result = Result()

        let containsFolder = urls.contains { url in
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        }

        // Loose files dropped on the root get a collection to live in; an imported folder already
        // brings its own, so it is left alone.
        var targetDirectory = directory
        if directory == nil, !containsFolder {
            targetDirectory = try? await fileManager.createCollectionForImport()
        }

        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            do {
                if isDirectory {
                    let nested = try await importFolder(url, into: targetDirectory, fileManager: fileManager)
                    result.succeeded += nested.succeeded
                    result.failed += nested.failed
                } else {
                    guard ImportFilter.isAudio(url) else { continue }
                    try await fileManager.importFile(url, targetDirectory)
                    result.succeeded += 1
                }
            } catch {
                result.failed += 1
            }
        }

        return result
    }

    private static func importFolder(
        _ folderURL: URL,
        into destinationDirectory: URL?,
        fileManager: FileManagerClient
    ) async throws -> Result {
        let needsAccess = folderURL.startAccessingSecurityScopedResource()
        defer { if needsAccess { folderURL.stopAccessingSecurityScopedResource() } }

        let parent = destinationDirectory ?? fileManager.documentsDirectory()
        let destinationRoot = UniqueNameResolver.resolve(
            baseName: folderURL.lastPathComponent, in: parent
        )
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: false)

        var result = Result()
        let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let next = enumerator?.nextObject() as? URL {
            let isDirectory = (try? next.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory { continue }
            guard ImportFilter.isAudio(next) else { continue }

            var targetDir = destinationRoot
            if let relativeDir = ImportFilter.relativeDirectory(of: next, under: folderURL) {
                targetDir = destinationRoot.appendingPathComponent(relativeDir, isDirectory: true)
                try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            }

            do {
                try await fileManager.importFile(next, targetDir)
                result.succeeded += 1
            } catch {
                result.failed += 1
            }
        }

        return result
    }
}
