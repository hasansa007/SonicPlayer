import Foundation

/// What a share batch records about itself (#112).
///
/// Slice 2 writes only a destination, and always the library root, because the folder picker is
/// slice 3. The type exists now rather than later so the on-disk shape is fixed before anything
/// ships: a batch written by an old extension must still be drainable by a new app, and the
/// cheapest way to guarantee that is to have the field there from the first release.
struct InboxManifest: Codable, Equatable, Sendable {

    /// Where the batch's files should land, relative to `Documents/`. `nil` is the library root.
    ///
    /// A *relative* path, not a URL, because the app's container path is not stable across installs
    /// and the extension has no business knowing it. The app resolves it against its own
    /// `Documents/` at drain time.
    var destination: String?

    /// Attachments the extension was handed and could not take.
    ///
    /// **Written by the extension so the app can say what happened, because the extension cannot.**
    /// The activation rule fires when *any* attachment is audio, so a mixed share hands over
    /// everything; anything without an audio type identifier is dropped at copy time. The extension
    /// then calls `completeRequest`, which tells the host app the share succeeded — and a host that
    /// believes a file was taken may offer to delete its own copy. Recording the names here is what
    /// turns a silent drop into something the app can surface.
    var rejected: [String]?

    init(destination: String? = nil, rejected: [String]? = nil) {
        self.destination = destination
        self.rejected = rejected
    }
}

/// Reading and writing `manifest.json`.
///
/// Separate from the type for the same reason `SessionCodec` is separate from `PlaybackSession`:
/// the decoding *policy* is the interesting part, and it is worth testing without a filesystem.
enum InboxManifestCodec {

    static func encode(_ manifest: InboxManifest) throws -> Data {
        try JSONEncoder().encode(manifest)
    }

    /// **Never throws, and never loses a batch.** Missing, truncated or corrupt all decode to the
    /// library root.
    ///
    /// The alternative — treating an unreadable manifest as an unreadable batch — discards audio
    /// the user explicitly shared, to protect a preference about *where it goes*. Those are not
    /// comparable losses. Landing the files at the root is recoverable in three taps; a batch
    /// silently skipped is not recoverable at all, because nothing tells the user it happened.
    ///
    /// This is the same judgement `SessionRestorePolicy` makes about a corrupt `session.json`:
    /// degrade to the safe default rather than refuse to proceed.
    static func decode(_ data: Data?) -> InboxManifest {
        guard let data, let manifest = try? JSONDecoder().decode(InboxManifest.self, from: data) else {
            return InboxManifest(destination: nil)
        }
        return manifest
    }

    /// The destination resolved against a documents directory, with the traversal guard.
    ///
    /// **A manifest is written by another process, so its contents are input, not fact.** The
    /// extension is ours today; a destination of `../../../../tmp/evil` would still resolve outside
    /// `Documents/` if this handed it straight to `appendingPathComponent`. Anything that does not
    /// land under `documentsDirectory` falls back to the root rather than being honoured or
    /// refused — same reasoning as `decode` above.
    static func resolvedDestination(
        _ manifest: InboxManifest, under documentsDirectory: URL
    ) -> URL {
        guard let destination = manifest.destination, !destination.isEmpty else {
            return documentsDirectory
        }
        let candidate = documentsDirectory.appendingPathComponent(destination)

        // **Normalise to compare, return unnormalised.** The check has to resolve symlinks and
        // `..` segments or it cannot see an escape; the *return* must not, because every other
        // branch here returns `documentsDirectory` as given. An earlier version resolved only on
        // the success path, so callers received `/private/var/…` or `/var/…` depending on which
        // branch fired — the kind of difference that costs an afternoon when a path comparison
        // downstream starts answering "no" to everything (#41 lost one to exactly this).
        //
        // `PathMatching.isAffected` already tests equality as its first clause; an explicit
        // `candidate == root ||` in front of it read as two cases while handling one.
        guard PathMatching.isAffected(
            trackURL: candidate.standardizedFileURL.resolvingSymlinksInPath(),
            byItemAt: documentsDirectory.standardizedFileURL.resolvingSymlinksInPath()
        ) else {
            return documentsDirectory
        }
        return candidate
    }
}
