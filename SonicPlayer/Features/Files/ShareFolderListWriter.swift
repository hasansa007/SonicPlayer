import Foundation

/// Publishes the library's folder list for the share extension (#112 slice 3) — the I/O half.
///
/// The extension cannot see `Documents/`, which is what keeps it unable to damage the library, so
/// the app writes down what folders exist and the picker reads that. The arithmetic — relative
/// paths, display paths, ordering — is `ShareFolderList`, testable without a filesystem.
enum ShareFolderListWriter {

    /// Walks `documentsDirectory` and writes the list into the group container.
    ///
    /// **Called on scene phase, beside the drain**, because the alternative was making every
    /// rename, delete, create and move remember to republish. That obligation is exactly what
    /// `CollectionsViewModel.onWillRemoveItems` exists to avoid, and a forgotten call site would
    /// show a folder that no longer exists — silently, in a screen the app never sees.
    ///
    /// The cost of that choice is staleness bounded by one app session: create a folder and share
    /// without ever foregrounding the app in between, and the new folder is not offered. The file
    /// still lands, at the root, and the folder is offered next time.
    ///
    /// Never throws. A list that cannot be written leaves the previous one in place, and the picker
    /// degrades to the root — the same direction every other decision in this feature takes.
    /// **No `fileManager:` parameter**, for the reason `InboxDrain.run` records: an earlier version
    /// threaded one into the enumeration while the write went through Foundation directly, and no
    /// caller ever passed a substitute. A seam that works for part of the calls advertises a
    /// substitutability that is not there.
    /// - Returns: what it did. **An enum, not a Bool, and the Bool was already the second attempt.**
    ///   The first version compared file modification dates and could not tell "skipped" from "never
    ///   wrote"; the Bool that replaced it collapsed *unchanged*, *encode failed* and *write failed*
    ///   into one `false` — the same ambiguity, one layer along, and a test asserting `!publish(...)`
    ///   passed green whether the file was healthy or had never been written at all.
    @discardableResult
    static func publish(
        documentsDirectory: URL, container: URL, items: [DialContent.Item]
    ) -> Outcome {
        let fileManager = FileManager.default
        let folders = ShareFolderList.folders(under: documentsDirectory, items: items)
        guard let data = try? ShareFolderList.encode(folders) else { return .failed }

        let destination = container.appendingPathComponent(ShareFolderList.fileName)

        // Skip the write when nothing changed, which is almost every time: this runs on every scene
        // phase and the folder tree changes maybe once a week. An atomic write creates a temp file
        // and renames it in the shared container, so writing unconditionally meant several of those
        // per app switch for identical bytes.
        if let existing = try? Data(contentsOf: destination), existing == data { return .unchanged }

        try? fileManager.createDirectory(at: container, withIntermediateDirectories: true)
        do {
            try data.write(to: destination, options: .atomic)
            return .wrote
        } catch {
            return .failed
        }
    }

    enum Outcome: Equatable, Sendable {
        case wrote
        case unchanged
        /// Encoding or writing failed. The previous list stays in place and the picker degrades to
        /// the root — the same direction every other decision in this feature takes.
        case failed
    }
}
