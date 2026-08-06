import Foundation

/// Decides whether the currently playing track is affected by an operation on a set of items.
///
/// Extracted from three byte-identical copies in `AppFeature` — the move, the root delete, and
/// the pushed-folder delete — each of which clears the playback session when it matches.
/// Getting this wrong is the worst regression available in this app: playback keeps running
/// against a file that has been moved or deleted.
enum PathMatching {

    /// True when `trackURL` is the item itself, or lives underneath it.
    ///
    /// The trailing separator matters: without it `/Music/Rock` would also match a track under
    /// `/Music/Rocks`, clearing the session for an unrelated folder.
    static func isAffected(trackURL: URL, byItemAt itemURL: URL) -> Bool {
        trackURL == itemURL || trackURL.path.hasPrefix(itemURL.path + "/")
    }

    /// True when any of `itemURLs` affects `trackURL`.
    static func isAffected(trackURL: URL, byAnyOf itemURLs: some Sequence<URL>) -> Bool {
        itemURLs.contains { isAffected(trackURL: trackURL, byItemAt: $0) }
    }
}
