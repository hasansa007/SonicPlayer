import Foundation

/// One destination the share picker can offer (#112 slice 3).
struct ShareFolder: Codable, Equatable, Sendable {

    /// What the picker draws: `Lectures`, or `البدعة › Lectures` below it.
    ///
    /// The whole path, not the leaf, for `MoveDestinations`' reason — two folders may share a name
    /// and the leaf alone would offer the same row twice with no way to tell them apart.
    var path: String

    /// What goes in the manifest: `البدعة/Lectures`, relative to `Documents/`.
    ///
    /// **Relative, because the extension has no business knowing the app's container path** — it is
    /// not stable across installs, and the app resolves this against its own `Documents/` at drain
    /// time. `InboxManifestCodec.resolvedDestination` is what refuses anything that escapes.
    var relativePath: String
}

/// The folder list the app publishes for the share extension to read (#112 slice 3).
///
/// **Published rather than queried, because the extension cannot see `Documents/`.** That blindness
/// is the property that makes the extension safe — it cannot damage a library it cannot reach — so
/// the picker is fed a list instead. The extension reads names and writes a choice; the app still
/// does every piece of filing.
///
/// Pure path arithmetic. The walk that produces the URLs is I/O and lives in
/// `Features/Files/ShareFolderListWriter`, the same split as `ImportFilter` / `OpenInImport`.
enum ShareFolderList {

    /// Named for what it is, in the group container beside `Inbox/`.
    static let fileName = "folders.json"

    /// The display and structural conventions are **`MoveDestinations`'**, deliberately.
    ///
    /// The app already decided flat-over-browsed for exactly this question, with a rationale worth
    /// not re-litigating: *"filing something means walking a tree you are not reading, and every
    /// level you descend is a chance to lose track of what you were moving."* A share sheet is a
    /// worse place to browse than the app is, not a better one. Sharing the separator and the root
    /// title means the two screens read as one idea rather than two.
    static let rootTitle = MoveDestinations.rootTitle
    static let separator = MoveDestinations.separator

    /// Every folder under `documentsDirectory`, flattened, root first.
    ///
    /// Takes the directory URLs rather than finding them, so the arithmetic — which is where the
    /// escaping and the ordering live — is testable without a filesystem.
    ///
    /// A URL that is not under `documentsDirectory` is dropped rather than producing a path that
    /// climbs out of it, which is the same guard `ImportFilter.relativeDirectory` applies.
    static func folders(under documentsDirectory: URL, directories: [URL]) -> [ShareFolder] {
        let root = documentsDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"

        let nested = directories
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
            .compactMap { url -> ShareFolder? in
                guard url.path.hasPrefix(prefix) else { return nil }
                let relative = String(url.path.dropFirst(prefix.count))
                guard !relative.isEmpty else { return nil }
                return ShareFolder(
                    path: relative.split(separator: "/").joined(separator: separator),
                    relativePath: relative
                )
            }
            // Sorted by the on-disk path so a parent always precedes its children, and so the list
            // is stable between writes — a picker whose rows move between shares is its own bug.
            .sorted { $0.relativePath < $1.relativePath }

        return [ShareFolder(path: rootTitle, relativePath: "")] + nested
    }

    static func encode(_ folders: [ShareFolder]) throws -> Data {
        try JSONEncoder().encode(folders)
    }

    /// **Never throws, and always offers somewhere.** Missing, truncated or corrupt all decode to
    /// the library root alone.
    ///
    /// The list is a convenience the app publishes; the *files* are the user's. Refusing to show a
    /// picker because a cache is unreadable would block a share over a stale JSON file, which is the
    /// wrong trade in the same direction `InboxManifestCodec.decode` already refuses to make. A
    /// root-only picker is degraded and still completes the job.
    ///
    /// This is also the fresh-install case, and it is the common one rather than an edge: the app
    /// has never run, so nothing has published a list, and the very first share still has to work.
    static func decode(_ data: Data?) -> [ShareFolder] {
        guard let data, let folders = try? JSONDecoder().decode([ShareFolder].self, from: data),
            !folders.isEmpty
        else {
            return [ShareFolder(path: rootTitle, relativePath: "")]
        }
        return folders
    }
}
