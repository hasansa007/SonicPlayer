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
