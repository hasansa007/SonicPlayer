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
            // **Sorted by path COMPONENTS, compared the way a reader would.**
            //
            // Two things were wrong with sorting the raw path string. Every character below `/`
            // (0x2F) sorts before it — space, hyphen, dot — so `Lectures`, `Lectures 2024` and
            // `Lectures/Week 1` came out in that order, putting an unrelated sibling between a
            // parent and its own child. The flat list stops reading as a tree exactly where it
            // matters most.
            //
            // And `<` on String compares unicode scalars, not language. This app ships nine
            // locales and its author files things in Arabic; ordering those by scalar value is the
            // kind of thing that looks fine to whoever wrote it and wrong to whoever uses it.
            // `localizedStandardCompare` is what Finder uses, and it also gets `Lecture 2` before
            // `Lecture 10`.
            .sorted { left, right in
                let a = left.relativePath.split(separator: "/")
                let b = right.relativePath.split(separator: "/")
                for (x, y) in zip(a, b) where x != y {
                    return String(x).localizedStandardCompare(String(y)) == .orderedAscending
                }
                return a.count < b.count
            }

        return [ShareFolder(path: rootTitle, relativePath: "")] + nested
    }

    /// **Encode only — there is deliberately no `decode` here.**
    ///
    /// The app writes this file and never reads it; the only reader is the extension, in its own
    /// target, with its own `loadFolders`. A `decode` on this side would be code that ships nowhere,
    /// and a test of it would prove nothing about the behaviour a user meets — the two would be free
    /// to drift, which is precisely how the root title came to be spelled two different ways.
    ///
    /// The extension's fallback policy — missing, truncated, corrupt and empty all mean the library
    /// root alone — is asserted by `ShareInboxLayoutAgreementTests`, which reads its source.
    static func encode(_ folders: [ShareFolder]) throws -> Data {
        try JSONEncoder().encode(folders)
    }
}
