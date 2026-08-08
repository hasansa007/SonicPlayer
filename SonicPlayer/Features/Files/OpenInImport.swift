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
    /// A name already present is treated as already imported and returned untouched, so opening
    /// the same file twice plays the existing copy instead of making another. That is the
    /// pre-existing behaviour and #33 does not change it — only the fact that the returned URL is
    /// now observed rather than re-derived by the caller.
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
    static func run(url: URL, into documentsDirectory: URL) throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let destination = documentsDirectory.appendingPathComponent(url.lastPathComponent)
        let isStaged = ImportFilter.isStaged(url, under: documentsDirectory)

        guard !FileManager.default.fileExists(atPath: destination.path) else {
            // Already imported — but a staged copy still has to go, because leaving it is what
            // makes iOS rename the next hand-off.
            //
            // **A shared name is not proof of identity, and the contents check is what stops this
            // being a delete of the user's file.** Two different files can arrive under one name —
            // a re-sent lecture, a second `recording.m4a` — and iOS does not rename the incoming
            // one, because by now the queue is empty and there is nothing to collide with. Without
            // the comparison this branch would destroy the file the user just asked to open and
            // then play the older one, silently. The read costs a pass over two files on the
            // duplicate-open path only, and it runs off the main actor.
            //
            // Deliberately not fatal: failing to tidy our own queue must not stop a file the user
            // can already play from opening. The cost of the `try?` is one duplicate next time.
            if isStaged, FileManager.default.contentsEqual(atPath: url.path, andPath: destination.path) {
                try? FileManager.default.removeItem(at: url)
            }
            return destination
        }

        if isStaged {
            try FileManager.default.moveItem(at: url, to: destination)
        } else {
            try FileManager.default.copyItem(at: url, to: destination)
        }
        return destination
    }
}
