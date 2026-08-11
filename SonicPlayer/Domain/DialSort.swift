import Foundation

/// The order the library lists its contents in, and the cycle a press walks through (#6).
///
/// **Newest-first is the only order the library has ever had**, because it is the right one for a
/// recorder: the take you just made is the one you want. It is the wrong one for a folder of
/// lectures numbered 1 to 6, which is what the library turned out to also be — those read top to
/// bottom in the order they were named, and newest-first shows them upside down.
///
/// **A picker without a screen, because the stick has four ways out.**
///
/// It was one chip that cycled, which is the shape the settings rows use — and cycling is what you
/// reach for when a control has one gesture. The stick has four, and they are idle while the wheel
/// rests on a chip, because the library's nudges act on the highlighted *file* and there is no file
/// under the highlight there. So the orders are a push each: `Newest` up, `Oldest` down, `A–Z` left,
/// `Z–A` right, chosen rather than stepped through.
///
/// The press still cycles. A finger tapping the chip has one gesture and nothing else to do with it.
enum DialSort: String, CaseIterable, Sendable {
    /// What the host hands over, which `LibraryTree` already orders newest-first.
    case newest
    case oldest
    case nameAscending
    case nameDescending

    var title: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .nameAscending: "Sorted A to Z"
        case .nameDescending: "Sorted Z to A"
        }
    }

    /// What the stick's nudge is called, and what it sends. Two words at most — see
    /// `DialScreen.Direction.label`.
    var name: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .nameAscending: "A–Z"
        case .nameDescending: "Z–A"
        }
    }

    var icon: DialScreen.Icon {
        switch self {
        case .newest: .sortNewest
        case .oldest: .sortOldest
        case .nameAscending: .sortAZ
        case .nameDescending: .sortZA
        }
    }

    /// The action id this order arrives as. Namespaced so the navigator can tell a sort nudge from
    /// every other verb without a list of four cases to keep in step with this enum.
    var actionID: String { "sort.\(rawValue)" }

    static func from(actionID: String) -> DialSort? {
        guard actionID.hasPrefix("sort.") else { return nil }
        return DialSort(rawValue: String(actionID.dropFirst("sort.".count)))
    }

    /// What the hub says when the wheel is on the Sort chip: **the order a press will produce**,
    /// not the one it is in. The chip already shows the current order; the button has to say what
    /// it does.
    var hubLabel: String {
        switch self {
        case .newest: "NEWEST"
        case .oldest: "OLDEST"
        case .nameAscending: "A → Z"
        case .nameDescending: "Z → A"
        }
    }

    var hint: String {
        switch self {
        case .newest: "by newest"
        case .oldest: "by oldest"
        case .nameAscending: "A to Z"
        case .nameDescending: "Z to A"
        }
    }

    var next: DialSort {
        switch self {
        case .newest: .oldest
        case .oldest: .nameAscending
        case .nameAscending: .nameDescending
        case .nameDescending: .newest
        }
    }

    /// Applied to one level's items, not to the tree — a folder is sorted when you are standing in
    /// it, by the same rule as the level above.
    ///
    /// **Folders stay first in every order.** They are the shelves, and a shelf sorted in among the
    /// files it contains is a list you have to read to navigate. Only what happens *within* each of
    /// the two groups changes.
    func applied(to items: [DialContent.Item]) -> [DialContent.Item] {
        guard self != .newest else { return items }

        let folders = items.filter(\.isFolder)
        let files = items.filter { !$0.isFolder }

        // **Oldest is newest reversed, not a second date comparison.** The host has already ordered
        // each group newest-first and this type is Foundation-only — it holds no dates and should
        // not learn to, because a second ordering rule is a second thing that can disagree with the
        // one `LibraryTree` applies.
        guard self != .oldest else { return folders.reversed() + files.reversed() }

        return byName(folders) + byName(files)
    }

    private func byName(_ items: [DialContent.Item]) -> [DialContent.Item] {
        items.sorted { left, right in
            // **`localizedStandardCompare`, not `<`.** Plain string ordering puts `Lecture 10`
            // before `Lecture 2`, and sorts every Arabic title into one lump after the Latin ones.
            // This is the comparison the Files app uses: digit runs compare numerically, and the
            // locale decides what alphabetical means.
            let order = left.title.localizedStandardCompare(right.title)
            return self == .nameAscending ? order == .orderedAscending : order == .orderedDescending
        }
    }
}
