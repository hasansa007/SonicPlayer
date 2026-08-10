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
/// - a per-file failure is counted and the import continues
///
/// **One behaviour is deliberately not preserved.** Importing loose files into the root used to
/// create a collection to hold them, named uniquely from "New Collection" — so every import made
/// another one, and a library that had been imported into five times held five numbered folders
/// nobody chose. Nothing asserted it: `.test` returns the documents directory for
/// `createCollectionForImport`, so no test could tell the difference. Files land where they are
/// sent now, and filing them is `Add to playlist`'s job.
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

        // **Loose files land in the root, not in a collection minted for them.**
        //
        // This used to call `createCollectionForImport()`, which resolves a *unique* name from
        // "New Collection" and creates it — so every import made a fresh folder. Import twice and
        // the library holds `New Collection` and `New Collection 2`; import ten times and it holds
        // ten, each with whatever happened to be selected that minute. Nothing was duplicated but
        // the folders, and the files scattered across numbered boxes nobody chose.
        //
        // An imported *folder* still brings its own, which is why `containsFolder` mattered and no
        // longer needs to: neither branch invents a directory now. Filing is `Add to playlist`'s
        // job, done deliberately and once, rather than a side effect of every import.
        let targetDirectory = directory

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
