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
/// worth extracting: #41 added two branches, and the decision behind both (*is this file one iOS
/// staged for us?*) went to `ImportFilter` rather than staying inline. What is left is the I/O.
enum OpenInImport {

    /// Moves or copies `url` into `documentsDirectory` and returns the URL that now holds the audio.
    ///
    /// An identical file already present is treated as already imported and returned untouched, so
    /// opening the same file twice plays the existing copy instead of making another.
    ///
    /// **#41 narrowed "already imported" from the name to the bytes.** The old test was the
    /// filename alone, which was wrong in both directions: a *different* file that happened to
    /// share a name was swallowed — the user opened one thing and heard another — and the same file
    /// re-opened was missed entirely, because iOS had renamed it in the staging directory before
    /// the app ever saw it. A file that shares a name but not its contents now imports alongside as
    /// `Track 2.m4a`, via the same `UniqueNameResolver` the rest of the app names files with.
    ///
    /// **#41 — a file iOS staged for us is CONSUMED, not copied.** The name guard below only ever
    /// fired when the hand-off kept its original name, and on a device it does not: iOS stages into
    /// `Documents/Inbox/` and dedupes that name itself, so a second open arrives as `Track-1.mp3`,
    /// misses the guard, and lands as a second copy. Draining the staging directory removes the
    /// *cause* of the rename rather than trying to undo it — no suffix arithmetic, and no risk of
    /// treating a user's genuine `Track-1.mp3` as a duplicate of `Track.mp3`.
    ///
    /// The move is conditional for a reason that is not cosmetic: `LSSupportsOpeningDocumentsInPlace`
    /// is `true`, so `url` is **sometimes** the user's own file in iCloud Drive or on a USB drive.
    /// Moving that would take it out of their storage. Only what is inside our own staging
    /// directory is ours to consume.
    ///
    /// Throws whatever `moveItem`/`copyItem` throws. The caller is expected to surface it.
    /// - Parameter consume: whether `url` is ours to **move** rather than copy. `nil` — the default,
    ///   and every caller before #112 — asks `ImportFilter.isStaged`, which is the right question
    ///   for a hand-off from iOS: it lands in `Documents/Inbox` and anything outside that is the
    ///   user's own file. The share queue lives in the **App Group container**, so that test says
    ///   "not ours" about files that are entirely ours; `InboxDrain` passes `true` instead.
    ///
    ///   Passed explicitly rather than widening `isStaged` to know about a second directory,
    ///   because the two queues answer to different owners: iOS fills one, our own extension fills
    ///   the other, and only the second is safe to consume unconditionally.
    static func run(url: URL, into documentsDirectory: URL, consume: Bool? = nil) throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let isStaged = consume ?? ImportFilter.isStaged(url, under: documentsDirectory)
        let sameName = documentsDirectory.appendingPathComponent(url.lastPathComponent)

        // **Identity is the bytes, not the name.** This is the only test for "already imported",
        // and it replaces a name-only check that was wrong in both directions: it treated a
        // *different* file sharing a name as a duplicate — playing the older one and, once this
        // branch started deleting, destroying the newer one — and it never fired for the same file
        // re-opened, because iOS had renamed it in the staging directory first.
        //
        // `contentsEqual` returns false when nothing is there, so this one call covers the empty
        // slot too, and it does not read anything in that case.
        if FileManager.default.contentsEqual(atPath: url.path, andPath: sameName.path) {
            // A staged copy still has to go: leaving it is what makes iOS rename the next
            // hand-off. Deliberately not fatal — failing to tidy our own queue must not stop a file
            // the user can already play from opening. The cost of the `try?` is one duplicate next
            // time, and never a lost file, because this branch only runs when an identical copy is
            // already on disk.
            if isStaged { try? FileManager.default.removeItem(at: url) }
            return sameName
        }

        // Either the slot is free or something genuinely different holds it. `resolve` returns
        // `sameName` in the first case and `Track 2.m4a` in the second, so a file that merely
        // shares a name with an import gets its own copy rather than being swallowed by it.
        let destination = UniqueNameResolver.resolve(
            baseName: url.deletingPathExtension().lastPathComponent,
            ext: url.pathExtension,
            in: documentsDirectory
        )

        if isStaged {
            try FileManager.default.moveItem(at: url, to: destination)
        } else {
            try FileManager.default.copyItem(at: url, to: destination)
        }
        return destination
    }
}
