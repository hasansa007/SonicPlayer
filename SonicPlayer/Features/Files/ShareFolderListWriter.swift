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
    /// - Returns: whether it wrote. **Returned rather than inferred from the file**, because the
    ///   first test of the skip asserted on modification dates and could not distinguish "not
    ///   rewritten" from "never written" — `attributesOfItem` throws when the file is absent, and a
    ///   thrown error and a failed expectation look identical in the results.
    @discardableResult
    static func publish(documentsDirectory: URL, container: URL) -> Bool {
        let fileManager = FileManager.default
        let folders = ShareFolderList.folders(
            under: documentsDirectory,
            directories: directories(under: documentsDirectory, fileManager: fileManager)
        )
        guard let data = try? ShareFolderList.encode(folders) else { return false }

        let destination = container.appendingPathComponent(ShareFolderList.fileName)

        // **Skip the write when nothing changed, which is almost every time.** This runs on every
        // scene phase; the folder tree changes maybe once a week. An atomic write creates a temp
        // file and renames it in the shared container, so writing unconditionally meant four of
        // those per app switch for identical bytes.
        if let existing = try? Data(contentsOf: destination), existing == data { return false }
        // Atomic, because the extension may be reading it at this moment — a share can start while
        // the app is foregrounding. A torn read would show half a list or none.
        // The container may not exist on a build without the entitlement, and `write` would fail
        // silently. Creating it is cheap and makes the return value mean what it says.
        try? fileManager.createDirectory(at: container, withIntermediateDirectories: true)
        do {
            try data.write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Every directory under `documentsDirectory`, at any depth.
    ///
    /// Skips iOS's staging directory for the reason `FileManagerClient.listItems` does: it is a
    /// queue the system owns, not a collection the user made, and offering it as a destination
    /// would invite filing into something the app empties on `.background` (#41, ADR 0003).
    ///
    /// Hidden directories are skipped too — `.partial-` batches do not live here, but `.Trash` and
    /// friends do turn up, and none of them are places a person files a lecture.
    private static func directories(under documentsDirectory: URL, fileManager: FileManager) -> [URL] {
        // **Descends directories instead of enumerating everything.** `FileManager.enumerator`
        // visits every *file* too, with a `resourceValues` call each — so a library of five
        // thousand recordings paid five thousand stats to find a handful of folders, on the main
        // actor, inside the same background window ADR 0003 measured as too short to finish work in.
        // Directories are typically a rounding error next to files, and `contentsOfDirectory` lets
        // the recursion see only them.
        var found: [URL] = []
        var queue = [documentsDirectory]

        while let directory = queue.popLast() {
            let children = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )) ?? []

            for url in children {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                else { continue }
                // iOS owns the staging directory — it is a queue the app empties on `.background`,
                // not a collection the user made, so offering it as a destination would invite
                // filing into something that gets deleted (#41, ADR 0003).
                guard !ImportFilter.isStagingDirectory(url, under: documentsDirectory) else {
                    continue
                }
                found.append(url)
                queue.append(url)
            }
        }
        return found
    }
}
