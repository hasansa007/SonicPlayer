import Foundation

/// Resolves a non-colliding destination URL by appending " 2", " 3", … to a base name.
///
/// This replaces seven near-identical inline implementations that had drifted apart:
///
/// | Call site | Behaviour before extraction |
/// |---|---|
/// | `FileManagerClient.createCollection` | folder, no extension |
/// | `FileManagerClient.createCollectionForImport` | folder, counter pre-incremented from 1 (same output) |
/// | `FileManagerClient.moveItem` | file, extension-aware |
/// | `FileManagerClient.importFile` | file, extension-aware |
/// | `CollectionsFeature.createUniqueFolder` | folder, no extension |
/// | `CollectionsFeature.moveToDestination` | file, plus a `counter > 100` bail-out |
/// | `RecordingFeature.saveRecording` | file, plus `candidate != originalURL` |
///
/// The two genuine differences — self-exclusion and the iteration cap — are now explicit
/// parameters rather than accidents of which copy you happened to be reading.
///
/// `exists` is injected so this type never touches the filesystem and stays testable.
enum UniqueNameResolver {

    /// - Parameters:
    ///   - baseName: name without its extension.
    ///   - ext: file extension without the dot. Empty for folders.
    ///   - directory: where the item will live.
    ///   - excluded: a URL that does not count as a collision. Used when saving a file over
    ///     itself, where colliding with your own current path should keep the name.
    ///   - limit: maximum number of candidates to try. On reaching it the last candidate is
    ///     returned **even though it collides** — preserving `moveToDestination`'s existing
    ///     `counter > 100` bail-out. Callers that never had a cap pass `nil`.
    ///   - exists: collision predicate.
    static func resolve(
        baseName: String,
        ext: String = "",
        in directory: URL,
        excluding excluded: URL? = nil,
        limit: Int? = nil,
        exists: (URL) -> Bool
    ) -> URL {
        var candidate = url(baseName: baseName, ext: ext, in: directory)
        var counter = 2

        while exists(candidate), candidate != excluded {
            if let limit, counter > limit { break }
            candidate = url(baseName: "\(baseName) \(counter)", ext: ext, in: directory)
            counter += 1
        }

        return candidate
    }

    /// Convenience over the real filesystem.
    static func resolve(
        baseName: String,
        ext: String = "",
        in directory: URL,
        excluding excluded: URL? = nil,
        limit: Int? = nil
    ) -> URL {
        resolve(baseName: baseName, ext: ext, in: directory, excluding: excluded, limit: limit) {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    private static func url(baseName: String, ext: String, in directory: URL) -> URL {
        ext.isEmpty
            ? directory.appendingPathComponent(baseName)
            : directory.appendingPathComponent("\(baseName).\(ext)")
    }
}
