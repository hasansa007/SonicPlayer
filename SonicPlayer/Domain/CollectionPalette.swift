import Foundation

/// Which of the collection card looks a folder gets (#48).
///
/// `CollectionsView` held two `private static let` arrays and indexed both by the folder's
/// **position in the filtered list**. That is the bug this extraction exists to fix: position is
/// not a property of the folder. Typing in the search box recoloured every card that survived the
/// filter, and deleting the first folder recoloured all the rest.
///
/// The slot is now a function of the folder's name, so a card looks the same whatever else is on
/// screen. Foundation only — the actual colours and glyphs stay in the view layer, because they
/// are presentation and this is the decision.
enum CollectionPalette {

    /// How many looks there are. The view supplies the gradients and glyphs; this only has to
    /// agree with it on the count.
    static let gradientCount = 5
    static let iconCount = 5

    /// A stable slot in `0..<gradientCount` for a folder.
    ///
    /// `position` is accepted and deliberately ignored for the colour choice — it stays in the
    /// signature so the call site reads as "this folder, at this index" and a future ordering
    /// rule has somewhere to go. It is used only to break the tie for an unnamed folder.
    static func slot(forName name: String, at position: Int) -> Int {
        guard !name.isEmpty else {
            return abs(position) % gradientCount
        }
        return stableHash(name) % gradientCount
    }

    /// FNV-1a, not `Hasher`.
    ///
    /// Swift's `hashValue` is seeded per process, so the same folder would get a different colour
    /// on every launch — the screen would look subtly different each time the app was opened, in
    /// a way no test running in one process could ever catch.
    private static func stableHash(_ string: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01b3
        }
        // Fold to a positive Int — the top bit would make `%` negative on a 64-bit platform.
        return Int(hash & 0x7FFF_FFFF)
    }
}
