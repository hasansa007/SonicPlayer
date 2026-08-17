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
    static func publish(
        documentsDirectory: URL, container: URL, fileManager: FileManager = .default
    ) {
        let folders = ShareFolderList.folders(
            under: documentsDirectory,
            directories: directories(under: documentsDirectory, fileManager: fileManager)
        )
        guard let data = try? ShareFolderList.encode(folders) else { return }

        let destination = container.appendingPathComponent(ShareFolderList.fileName)
        // Atomic, because the extension may be reading it at this moment — a share can start while
        // the app is foregrounding. A torn read would show half a list or none.
        try? data.write(to: destination, options: .atomic)
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
        guard
            let walker = fileManager.enumerator(
                at: documentsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else { return [] }

        var found: [URL] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            if ImportFilter.isStagingDirectory(url, under: documentsDirectory) {
                walker.skipDescendants()
                continue
            }
            found.append(url)
        }
        return found
    }
}
