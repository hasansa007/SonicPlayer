import Foundation

/// Turns the documents directory into the nested list the dial browses (#6).
///
/// **The dial had no folders at all, and the app had folders all along.** `Add to playlist` moved
/// recordings into directories, the Files sheet created and browsed them, and the dial's library
/// was a flat recursive sweep — so every recording appeared at the top level and the folder it had
/// been filed into was invisible from the screen that filed it. Filing something and then not being
/// able to see where it went is worse than not being able to file it.
///
/// **Folders and playlists are the same thing here**, and that is a decision rather than an
/// accident: a playlist that is a directory can be made in Files, survives a reinstall from a
/// backup, and needs no second store to fall out of step with the disk.
///
/// Not in `Domain/`, for the reason `OpenInImport` is not: this is a walk over the filesystem with
/// no decision left once the I/O is taken out. What it produces is the input to decisions the
/// navigator makes.
enum LibraryTree {

    /// The whole library, folders first and newest first within each kind.
    ///
    /// **No deduplication by filename**, unlike the flat sweep this sits beside. That sweep folds
    /// two recordings with the same name into one because a flat list has nowhere to say they came
    /// from different places. Here there is somewhere: they are in different folders, which is the
    /// entire point, and hiding one would make a folder look empty when it is not.
    static func load(fileManager: FileManagerClient) async throws -> [DialContent.Item] {
        try await items(in: nil, fileManager: fileManager)
    }

    private static func items(
        in directory: URL?, fileManager: FileManagerClient
    ) async throws -> [DialContent.Item] {
        let contents = try await fileManager.listItems(directory)

        var folders: [(DialContent.Item, Date)] = []
        var files: [(DialContent.Item, Date)] = []

        for entry in contents {
            switch entry {
            case let .folder(folder):
                let children = try await items(in: folder.url, fileManager: fileManager)
                folders.append((
                    DialContent.Item(
                        // The URL, matching what a file row uses, so one id space covers both and
                        // a route holding one can be resolved without knowing which kind it is.
                        id: folder.url.absoluteString,
                        title: folder.name,
                        duration: 0,
                        subtitle: subtitle(for: children),
                        children: children
                    ),
                    folder.creationDate
                ))

            case let .file(file):
                files.append((
                    DialContent.Item(
                        id: file.url.absoluteString,
                        title: file.title,
                        duration: file.duration,
                        subtitle: nil,
                        children: nil
                    ),
                    file.creationDate
                ))
            }
        }

        // Folders first. They are containers rather than content, and a list that mixes them by
        // date makes the turn to reach one unpredictable.
        let sortedFolders: [DialContent.Item] = folders.sorted { $0.1 > $1.1 }.map(\.0)
        let sortedFiles: [DialContent.Item] = files.sorted { $0.1 > $1.1 }.map(\.0)
        return sortedFolders + sortedFiles
    }

    /// `3 recordings`, `2 folders · 1 recording`, or `Empty` — what is inside, in the row's second
    /// line, because the trailing column only has room for a number.
    private static func subtitle(for children: [DialContent.Item]) -> String {
        let folders = children.count(where: \.isFolder)
        let files = children.count - folders

        var parts: [String] = []
        if folders > 0 { parts.append("\(folders) folder\(folders == 1 ? "" : "s")") }
        if files > 0 { parts.append("\(files) recording\(files == 1 ? "" : "s")") }
        return parts.isEmpty ? "Empty" : parts.joined(separator: " · ")
    }
}
