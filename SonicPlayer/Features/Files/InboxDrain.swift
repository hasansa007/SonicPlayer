import Foundation

/// Files what the share extension queued (#112) — the I/O half of the share import.
///
/// Not in `Domain/`: this is enumerate, move, delete. The decisions it needs — which directories are
/// committed batches, where a manifest points, whether a destination escapes `Documents/` — live in
/// `ShareInbox` and `InboxManifestCodec`, where they are testable without a filesystem. Same split
/// as `ImportFilter` / `OpenInImport`, for the same reason.
///
/// **Idempotent by construction, because it has to be.** It runs on both `.active` and
/// `.background`, so two runs can follow each other with nothing in between; the app can be killed
/// with half a batch moved; and the user can share again while it is working. What makes that safe
/// is that a batch is only ever *visible* once the extension has renamed it into place, and each
/// file is removed from the queue as it lands. A second run over the same batch sees whatever is
/// left and finishes it.
enum InboxDrain {

    /// What one drain did. Slice 4's exception screen is what eventually renders `pending`.
    struct Result: Equatable, Sendable {
        var imported: [URL] = []
        var pending: [Pending] = []

        var isEmpty: Bool { imported.isEmpty && pending.isEmpty }

        /// **Discriminated, because a flat `[String]` mixed two unrecognisable things.** The first
        /// version appended a batch directory's raw `UUID().uuidString` into the same array as
        /// filenames, so slice 4's screen would have shown the user `A1B2C3D4-…-9F0A` in a list
        /// otherwise made of their own recordings — a string identifying nothing they could act on,
        /// with no way for the screen to tell the two apart and format them differently.
        enum Pending: Equatable, Sendable {
            /// Left in the queue because the library does not accept it. Not a failure: the file is
            /// intact and the user decides. Slice 4 is where they decide.
            case notAudio(fileName: String)
            /// The move threw — no space, unreadable. Retried on the next phase change.
            case failed(fileName: String)
            /// The batch directory itself could not be listed. Named by its id because there is
            /// nothing better to say; the screen should present this as "a shared batch" rather
            /// than showing the id.
            case unreadableBatch(id: String)
            /// The extension was killed before it could commit this batch, and the app reclaimed it
            /// after `ShareInbox.partialBatchLifetime`. The file is gone; the user shared it and got
            /// nothing, so saying so is the only honest option left.
            case abandoned(fileName: String)
            /// Shared, but the extension could not take it — no audio type identifier among the
            /// attachment's registered types. It was never in the queue, so there is nothing to
            /// retry; the user simply needs to be told it did not come across.
            ///
            /// `nil` when the attachment had no name to offer. **The extension deliberately does not
            /// invent one**: a placeholder there would be an English string shipping from a target
            /// with no string catalogue. Naming the unnamed belongs to the screen that renders this.
            case notAccepted(fileName: String?)
        }
    }

    /// Drains every committed batch into `documentsDirectory`.
    ///
    /// Never throws. A batch that cannot be read is left in place for the next run rather than
    /// deleted — the files in it are the user's, and the cost of trying again is nothing.
    @discardableResult
    /// **No `fileManager:` parameter, and its absence is deliberate.** An earlier version took one
    /// and threaded it to `contentsOfDirectory`, `createDirectory` and `removeItem` — while every
    /// actual move went through `OpenInImport`, whose `contentsEqual`, `moveItem`, `copyItem` and
    /// `UniqueNameResolver` probe all use `FileManager.default` unconditionally. Passing a
    /// substitute produced a half-substituted drain reading and writing through two different
    /// objects, and no test ever passed one. A seam that only works for a third of the calls is
    /// worse than no seam: it advertises a substitutability that is not there.
    static func run(container: URL, into documentsDirectory: URL) -> Result {
        let fileManager = FileManager.default
        var result = Result()
        let inbox = ShareInbox.inbox(inContainer: container)

        guard let names = try? fileManager.contentsOfDirectory(atPath: inbox.path) else {
            return result   // No inbox yet is the normal state before the first share.
        }

        for batchName in ShareInbox.committedBatches(in: names) {
            let batch = inbox.appendingPathComponent(batchName)

            // **A batch is a directory. A stray file is not an unreadable batch.**
            // `committedBatches` filters by name, so anything non-dot-prefixed in the inbox root
            // reached `drain`, failed `contentsOfDirectory`, and was reported as
            // `.unreadableBatch` — on every scene phase change, forever, with nothing able to
            // clear it. Slice 4 would show a row naming a file the user never shared and offering
            // no action. Skipping is right: we did not put it there and it is not ours to delete.
            guard (try? batch.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            drain(batch: batch, into: documentsDirectory, fileManager: fileManager, into: &result)
        }

        reapAbandonedPartials(in: inbox, names: names, fileManager: fileManager, into: &result)
        return result
    }

    /// Removes `.partial-` batches old enough that the extension that made them is long gone.
    ///
    /// **Nothing else ever would.** `isCommittedBatch` refuses dot-prefixed names by design, so a
    /// batch the extension was killed halfway through writing is invisible to the drain and holds
    /// its audio forever — a leak bounded only by deleting the app.
    ///
    /// The age test is `ShareInbox.isAbandonedPartial`, deliberately generous: the app cannot ask
    /// whether the extension is still alive, so reclaiming too eagerly destroys a share in flight.
    /// Reported as pending rather than silently, because the user did share those files and got
    /// nothing — that is exactly what slice 4's screen is for.
    /// The most recent modification anywhere in `directory` — the directory itself or any entry.
    ///
    /// **The directory's own timestamp is not enough, and the first version relied on it.** A
    /// directory's mtime advances when an entry is *added*, so a batch receiving one large file
    /// looks untouched for as long as that copy takes. Taking the newest of the directory and its
    /// contents covers the multi-file case and the mid-copy case.
    ///
    /// **It does not cover everything, and the gap is worth stating.** While
    /// `loadFileRepresentation` downloads the *first* attachment from iCloud, nothing has been
    /// written into the batch at all — there is no signal to read, and a download longer than
    /// `partialBatchLifetime` can still be reaped out from under a live extension. Closing that
    /// needs the extension to touch a heartbeat file while it works, which is an extension change
    /// and is deferred rather than guessed at here.
    private static func newestTouch(in directory: URL, fileManager: FileManager) -> Date? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let own = try? directory.resourceValues(forKeys: keys).contentModificationDate
        let children = ((try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys)
        )) ?? []).compactMap { try? $0.resourceValues(forKeys: keys).contentModificationDate }
        return ([own].compactMap { $0 } + children).max()
    }

    private static func reapAbandonedPartials(
        in inbox: URL, names: [String], fileManager: FileManager, into result: inout Result
    ) {
        let now = Date()
        for name in names {
            let directory = inbox.appendingPathComponent(name)
            guard
                let touched = newestTouch(in: directory, fileManager: fileManager),
                ShareInbox.isAbandonedPartial(name, age: now.timeIntervalSince(touched))
            else { continue }

            let lost = ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [])
                .filter { $0 != ShareInbox.manifestFileName }
            guard (try? fileManager.removeItem(at: directory)) != nil else { continue }
            result.pending.append(contentsOf: lost.map { .abandoned(fileName: $0) })
        }
    }

    private static func drain(
        batch: URL, into documentsDirectory: URL, fileManager: FileManager, into result: inout Result
    ) {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: batch.path) else {
            result.pending.append(.unreadableBatch(id: batch.lastPathComponent))
            return
        }

        let manifestData = try? Data(
            contentsOf: batch.appendingPathComponent(ShareInbox.manifestFileName)
        )
        let manifest = InboxManifestCodec.decode(manifestData)
        let destination = InboxManifestCodec.resolvedDestination(manifest, under: documentsDirectory)
        result.pending.append(
            contentsOf: (manifest.rejected ?? []).map { .notAccepted(fileName: $0.isEmpty ? nil : $0) }
        )
        // Slice 2 always resolves to the root, but creating the directory is what makes slice 3 a
        // manifest change rather than a code change.
        try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        var emptied = true
        for entry in entries where entry != ShareInbox.manifestFileName {
            let file = batch.appendingPathComponent(entry)

            // The extension already filtered by extension, so this is belt and braces — but it is
            // the app's own guard and costs nothing. Anything else is left in place rather than
            // deleted; a file we do not understand is not a file we should destroy.
            guard ImportFilter.isAudio(file) else {
                result.pending.append(.notAudio(fileName: entry))
                emptied = false
                continue
            }

            do {
                // `consume: true` — this queue is ours, so move rather than copy. Without it
                // `ImportFilter.isStaged` would answer "not ours" about the App Group container and
                // leave a duplicate behind for every import.
                let written = try OpenInImport.run(url: file, into: destination, consume: true)
                result.imported.append(written)
            } catch {
                result.pending.append(.failed(fileName: entry))
                emptied = false
            }
        }

        // Only tear the batch down once its audio is gone. A batch still holding a failed file
        // survives to the next run; the manifest alone is not worth keeping.
        if emptied {
            try? fileManager.removeItem(at: batch)
        }
    }
}
