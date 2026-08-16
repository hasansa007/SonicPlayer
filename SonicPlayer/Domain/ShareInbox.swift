import Foundation

/// The layout of the queue the share extension writes and the app drains (#112).
///
/// **This is a contract between two processes, and only one of them can see this file.**
/// `SonicPlayerShare` is a separate target with no access to the app's sources, so it declares the
/// same values in `SonicPlayerShare/ShareInboxLayout.swift`. That duplication is deliberate — a
/// synchronized file group excludes files, it does not share them — and it is **checked rather than
/// trusted**: `ShareInboxLayoutAgreementTests` reads the extension's source and both entitlements
/// files and fails if any literal drifts. Change a value here and that test tells you the other
/// half needs the same edit, which is the whole reason it exists.
///
/// Pure path arithmetic and predicates, no I/O — the same split as `ImportFilter`, so the rules that
/// decide whether a batch is safe to consume are testable without a filesystem.
enum ShareInbox {

    /// Must equal the `com.apple.security.application-groups` entry in **both** entitlements files.
    /// The app and the extension are separate processes with separate containers; this identifier
    /// is the only thing they share.
    static let appGroupIdentifier = "group.com.hasan.sonicplayer"

    /// The queue directory inside the group container.
    ///
    /// Named `Inbox` for the same reason iOS's is: it is a queue the owner **drains**, not storage.
    /// It is not the same directory — iOS's lives in `Documents/` and is covered by `ImportFilter`
    /// — but it has identical semantics, which is why `OpenInImport.run` can serve both.
    static let inboxDirectoryName = "Inbox"

    /// Records where a batch's files should land. Absent or corrupt means the library root.
    static let manifestFileName = "manifest.json"

    /// Marks a batch the extension is still writing.
    ///
    /// **The dot is load-bearing.** A batch under construction must be invisible to a drain that
    /// runs while the extension is still copying — which can happen, because the user can share
    /// into a foregrounded app. The extension writes into `.partial-<id>` and then *renames* the
    /// directory to `<id>`; a rename within one filesystem is atomic, so a batch is either wholly
    /// visible or not visible at all. There is no half-committed state to reason about, and so no
    /// lock, no marker file and no retry.
    static let partialPrefix = "."

    static func inbox(inContainer container: URL) -> URL {
        container.appendingPathComponent(inboxDirectoryName)
    }

    static func partialBatchName(id: String) -> String {
        "\(partialPrefix)partial-\(id)"
    }

    /// True when a directory name is a batch the extension has finished writing.
    ///
    /// Everything dot-prefixed is refused, which covers `.partial-*` and, for free, the `.DS_Store`
    /// and similar debris that turns up in any directory a human has opened. A drain that tried to
    /// import `.DS_Store` would produce a failure row for a file nobody shared.
    static func isCommittedBatch(_ name: String) -> Bool {
        !name.hasPrefix(partialPrefix) && !name.isEmpty
    }

    /// The committed batches among `names`, oldest first by the caller's ordering.
    ///
    /// Order matters only for predictability — two batches never contend for the same destination
    /// name, because `UniqueNameResolver` runs per file — but a stable order makes the drain's
    /// behaviour reproducible in a test.
    static func committedBatches(in names: [String]) -> [String] {
        names.filter(isCommittedBatch).sorted()
    }
}
