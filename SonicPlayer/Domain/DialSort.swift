import Foundation

/// The order the library lists its contents in, and the cycle a press walks through (#6).
///
/// **Newest-first is the only order the library has ever had**, because it is the right one for a
/// recorder: the take you just made is the one you want. It is the wrong one for a folder of
/// lectures numbered 1 to 6, which is what the library turned out to also be — those read top to
/// bottom in the order they were named, and newest-first shows them upside down.
///
/// **One control, three states, cycling** — the same shape as the settings rows, and for the same
/// reason: a wheel and a button cannot offer a picker without inventing a screen, and three values
/// are faster to cycle than to choose from.
enum DialSort: String, CaseIterable, Sendable {
    /// What the host hands over, which `LibraryTree` already orders newest-first.
    case newest
    case nameAscending
    case nameDescending

    var title: String {
        switch self {
        case .newest: "Newest first"
        case .nameAscending: "Sorted A to Z"
        case .nameDescending: "Sorted Z to A"
        }
    }

    /// What the hub says when the wheel is on the Sort chip: **the order a press will produce**,
    /// not the one it is in. The chip already shows the current order; the button has to say what
    /// it does.
    var hubLabel: String {
        switch self {
        case .newest: "NEWEST"
        case .nameAscending: "A → Z"
        case .nameDescending: "Z → A"
        }
    }

    var hint: String {
        switch self {
        case .newest: "by newest"
        case .nameAscending: "A to Z"
        case .nameDescending: "Z to A"
        }
    }

    var next: DialSort {
        switch self {
        case .newest: .nameAscending
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
