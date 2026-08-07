import Foundation

/// The import half of "open this in Sonic Player" — the `.onOpenURL` entry point.
///
/// It exists as a type rather than as an effect body because of #33. The previous version copied
/// the file to a path it had **computed**, then resolved the track to play from that computed path
/// rather than from what it had actually written, and swallowed every failure with `try?`.
/// Returning the written URL is the whole point: the caller can no longer guess wrong, and a
/// failure to write has somewhere to go.
///
/// Not in `Domain/`: this is almost entirely I/O — security-scoped access and a copy — which is
/// the same reason the recursive folder import is not there either. There is no decision here
/// worth extracting; the one conditional is a single line.
enum OpenInImport {

    /// Copies `url` into `documentsDirectory` and returns the URL that now holds the audio.
    ///
    /// A name already present is treated as already imported and returned untouched, so opening
    /// the same file twice plays the existing copy instead of making another. That is the
    /// pre-existing behaviour and #33 does not change it — only the fact that the returned URL is
    /// now observed rather than re-derived by the caller.
    ///
    /// Throws whatever `copyItem` throws. The caller is expected to surface it.
    static func run(url: URL, into documentsDirectory: URL) throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let destination = documentsDirectory.appendingPathComponent(url.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return destination }

        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}
