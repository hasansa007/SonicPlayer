import Foundation

/// Every folder a recording can be filed into, flattened to one list (#6).
///
/// **Flattened rather than browsed.** Filing something means walking a tree you are not reading,
/// and every level you descend is a chance to lose track of what you were moving. One list of full
/// paths is one turn and one press however deep the destination is — and it makes "is this already
/// where it lives" answerable at a glance, which a browse cannot.
///
/// The library root leads, because "out of every folder" is a destination too and the only one a
/// nested list has nowhere to put.
enum MoveDestinations {

    struct Destination: Equatable {
        /// `nil` is the library root.
        var id: String?
        /// `Lectures` at the top level, `البدعة › Lectures` below it — the whole path, because two
        /// folders may share a name and the leaf alone would offer the same row twice.
        var path: String
    }

    static let rootTitle = "Library"
    static let separator = " › "

    /// **The moving item's own folder is included and its own self is not.** Filing something where
    /// it already lives is a no-op the guard below refuses; filing it *into itself* is the one that
    /// would lose it, so a folder is never offered as a destination inside its own subtree.
    static func all(in items: [DialContent.Item], excluding itemID: String? = nil) -> [Destination] {
        [Destination(id: nil, path: rootTitle)] + walk(items, prefix: [], excluding: itemID)
    }

    private static func walk(
        _ items: [DialContent.Item], prefix: [String], excluding itemID: String?
    ) -> [Destination] {
        items.flatMap { item -> [Destination] in
            guard let children = item.children, item.id != itemID else { return [] }
            let path = prefix + [item.title]
            return [Destination(id: item.id, path: path.joined(separator: separator))]
                + walk(children, prefix: path, excluding: itemID)
        }
    }
}
