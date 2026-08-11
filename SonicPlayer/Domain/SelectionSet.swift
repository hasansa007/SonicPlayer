import Foundation

/// The file browser's selection rules: which items the search box leaves visible, and what
/// tapping an item, select-all, or clear does to the selected set.
///
/// Extracted from four sites in `CollectionsFeature`. The `collectionCards` / `fileRows`
/// `isSelected` mirroring that sits alongside them at each site is row-reducer state, which #18
/// deletes rather than ports — so it is deliberately left at the call sites.
enum SelectionSet {

    /// The visible list: everything when the query is empty, case-insensitive and locale-aware
    /// substring matching otherwise.
    ///
    /// Not diacritic-insensitive — `localizedCaseInsensitiveContains` folds case but not accents,
    /// so "cafe" does not match "café". Preserved as it was.
    static func matching(_ items: [FileSystemItem], searchText: String) -> [FileSystemItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    /// Tapping an item selects it, or deselects it when it is already selected.
    static func toggling(
        _ item: FileSystemItem,
        in selection: Set<FileSystemItem>
    ) -> Set<FileSystemItem> {
        var next = selection
        if next.contains(item) {
            next.remove(item)
        } else {
            next.insert(item)
        }
        return next
    }

    /// Select-all selects what is **visible**, not everything loaded.
    ///
    /// This is the one genuinely non-obvious rule here: it *replaces* the selection rather than
    /// adding to it, so with a query active it selects the matches and silently drops anything
    /// selected outside them.
    static func selectingAll(
        _ items: [FileSystemItem],
        searchText: String
    ) -> Set<FileSystemItem> {
        Set(matching(items, searchText: searchText))
    }
}
