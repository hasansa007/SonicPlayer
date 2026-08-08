import Foundation

/// Which files an import will accept, and where each one lands.
///
/// Extracted from the recursive-import effect (#18), which was the largest single effect in the
/// app at ~130 lines and had no test because every line of it was tangled with security-scoped
/// URLs and `FileManager`. These two decisions are the part that can be stated without any I/O,
/// and they are the part that silently drops a user's files when wrong.
enum ImportFilter {

    /// Unchanged from the inline set. `mp4` is here because `.m4b`/`.mp4` audiobooks are common;
    /// video with the same extension is accepted and then fails later at playback, which is
    /// pre-existing behaviour and not this slice's to change.
    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "wav", "aac", "flac", "aiff", "m4b", "mp4", "opus", "ogg"
    ]

    static func isAudio(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - iOS's staging directory (#41)

    /// The name iOS uses for the hand-off directory it creates inside `Documents`.
    ///
    /// Despite `LSSupportsOpeningDocumentsInPlace`, a file opened from outside a file provider is
    /// copied into `Documents/Inbox/` before `.onOpenURL` fires. That directory is the system's,
    /// not the user's: it is a queue the app is expected to **drain**, and #41 is what happens when
    /// it is not. A staged copy left behind makes iOS dedupe the *next* hand-off of the same file
    /// to `Track-1.mp3`, and that rename is what defeated `OpenInImport`'s already-imported guard.
    ///
    /// Not configurable — it is iOS's name, on every version this app supports.
    static let stagingDirectoryName = "Inbox"

    static func stagingDirectory(under documentsDirectory: URL) -> URL {
        documentsDirectory.appendingPathComponent(stagingDirectoryName)
    }

    /// True when `url` IS the staging directory — the question the browser asks, because iOS's
    /// queue is not a collection the user made.
    ///
    /// Both sides are resolved: `documentsDirectory()` and a handed-over URL routinely disagree
    /// on `/var` vs `/private/var`, and a comparison across that difference answers "no" to every
    /// question here without ever failing.
    static func isStagingDirectory(_ url: URL, under documentsDirectory: URL) -> Bool {
        url.resolvingSymlinksInPath() == stagingDirectory(under: documentsDirectory).resolvingSymlinksInPath()
    }

    /// True when `url` is a file iOS staged for us — and therefore ours to consume rather than
    /// copy. A URL outside it is the user's own file, opened in place, and moving it would take it
    /// out of their iCloud Drive.
    ///
    /// Delegates the prefix test to `PathMatching` rather than repeating it: the trailing-separator
    /// subtlety there (`/Music/Rock` must not match `/Music/Rocks`) is exactly as load-bearing
    /// here, where a false positive means moving a file the app does not own. The parameter is
    /// named for its first caller, not for this one.
    static func isStaged(_ url: URL, under documentsDirectory: URL) -> Bool {
        PathMatching.isAffected(
            trackURL: url.resolvingSymlinksInPath(),
            byItemAt: stagingDirectory(under: documentsDirectory).resolvingSymlinksInPath()
        )
    }

    // MARK: - Folder import

    /// The subdirectory a file inside an imported folder should land in, relative to the import
    /// root — or nil when it belongs at the root itself.
    ///
    /// Preserves the original's string-prefix arithmetic exactly, including that it compares
    /// `sourceRoot.path + "/"` rather than path components. Passing a URL that is not under
    /// `sourceRoot` returns nil rather than producing a path that escapes the destination.
    static func relativeDirectory(of fileURL: URL, under sourceRoot: URL) -> String? {
        let prefix = sourceRoot.path + "/"
        guard fileURL.path.hasPrefix(prefix) else { return nil }

        let relativePath = String(fileURL.path.dropFirst(prefix.count))
        let relativeDir = (relativePath as NSString).deletingLastPathComponent
        return (relativeDir.isEmpty || relativeDir == ".") ? nil : relativeDir
    }
}
