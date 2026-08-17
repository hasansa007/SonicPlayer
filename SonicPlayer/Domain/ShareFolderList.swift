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

    /// Every folder the picker can offer, derived from the library tree the app already holds.
    ///
    /// **Built from `MoveDestinations`, not from a filesystem walk — and the first version walked.**
    /// That version cost four separate defects, all of which this deletes:
    ///
    /// - it recursed `Documents/` **synchronously on the main actor**, on both `.active` and
    ///   `.background`, ahead of the drain — consuming the suspension window ADR 0003 measured as
    ///   too short to finish work in, for every user including those who never share anything;
    /// - it followed symlinks, so a link pointing at an ancestor looped forever and hung the app;
    /// - it passed `.skipsPackageDescendants` to `contentsOfDirectory`, where that flag does
    ///   nothing — it is honoured only by `FileManager.enumerator` — so a `.bundle`'s internals
    ///   were offered as share destinations;
    /// - it sorted alphabetically while the app's own Move screen sorts newest-first, so two
    ///   screens showed the same folders in different orders while each cited the other for
    ///   consistency.
    ///
    /// `home.libraryTree` is a complete tree, refreshed on the same `.active` transition, whose
    /// folder ids **are** `url.absoluteString`. `MoveDestinations.all` already flattens it root-first
    /// with this separator and this root title, because it answers this exact question for the Move
    /// screen. Reusing it means the two screens cannot drift apart, which is what "read as one idea"
    /// was supposed to mean.
    ///
    /// The only thing left to derive is the relative path, because the extension resolves against
    /// its own idea of `Documents/` and must never be handed an absolute one.
    static func folders(under documentsDirectory: URL, items: [DialContent.Item]) -> [ShareFolder] {
        let root = documentsDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"

        return MoveDestinations.all(in: items).compactMap { destination in
            guard let id = destination.id else {
                return ShareFolder(path: destination.path, relativePath: "")   // the library root
            }
            // The id is a URL string; anything that does not resolve under Documents/ is dropped
            // rather than turned into a path that climbs out of it — `ImportFilter`'s guard.
            guard
                let url = URL(string: id)?.standardizedFileURL.resolvingSymlinksInPath(),
                url.path.hasPrefix(prefix)
            else { return nil }

            return ShareFolder(
                path: destination.path,
                relativePath: String(url.path.dropFirst(prefix.count))
            )
        }
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
