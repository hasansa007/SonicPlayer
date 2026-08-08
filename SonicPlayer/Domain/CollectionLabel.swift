import Foundation

/// The collection a file belongs to, as a label (#48).
///
/// Lifted out of `MediaFileRowView.collectionName(for:)`, which was a `private static func` on a
/// view that called `FileManager.default.urls(for: .documentDirectory, …)` to find out where the
/// root was. Same shape as the probe #44 took out of `restoreSession`: a decision the app makes
/// once per row, wrapped in an I/O call no test could reach and no caller could substitute.
///
/// `Domain/`, because once the documents URL is handed in there is no I/O left — only the
/// question "is this file's parent the root, or is it a collection?".
enum CollectionLabel {

    /// The name of the folder a file sits in, or `nil` when it sits in the root.
    ///
    /// Both URLs are standardised before comparison. On device the documents directory resolves
    /// under `/var/mobile/…` while a URL that has been through a security-scoped bookmark or
    /// `standardizedFileURL` can arrive as `/private/var/mobile/…` — the same directory by two
    /// names. Comparing them raw makes the root look like a collection, and every file in it gets
    /// labelled "Documents".
    static func name(for file: URL, documentsURL: URL) -> String? {
        let parent = file.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let root = documentsURL.standardizedFileURL.resolvingSymlinksInPath()

        // Compared as `path`, not as `URL`. `deletingLastPathComponent()` returns a URL with a
        // trailing slash — it knows the result is a directory — while a URL built from a plain
        // string does not. `/Docs/` and `/Docs` are then unequal as URLs and equal as paths, and
        // it is the second answer that is true. Getting this wrong labels every file in the root
        // with the name of the root folder itself.
        guard parent.path != root.path else { return nil }
        return parent.lastPathComponent
    }
}
