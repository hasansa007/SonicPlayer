import Foundation
import Testing

@testable import SonicPlayer

/// The order the library lists things in (#6).
///
/// **Newest-first was the only order there had ever been**, which is right for a recorder and wrong
/// for the thing the library also turned out to be: a folder of lectures numbered 1 to 6 read
/// bottom to top, and the numbers went down the screen.
@Suite
struct DialSortTests {

    private static func named(_ titles: [String]) -> DialContent {
        var content = DialContent()
        content.recordings = titles.enumerated().map { index, title in
            DialContent.Item(id: "rec-\(index)", title: title, duration: 60)
        }
        return content
    }

    private static func inLibrary(_ titles: [String]) -> DialNavigator {
        var navigator = DialNavigator(content: named(titles), root: .library)
        _ = navigator.receive(.press)       // home → Listen → the library
        return navigator
    }

    private func titles(_ navigator: DialNavigator) -> [String] {
        navigator.currentItems.map(\.title)
    }

    @Test func theDefaultIsWhateverTheHostHandedOver() {
        let navigator = Self.inLibrary(["Gamma", "Alpha", "Beta"])

        #expect(navigator.level.sort == .newest)
        #expect(titles(navigator) == ["Gamma", "Alpha", "Beta"], "LibraryTree already orders these")
    }

    @Test func oneChipCyclesThroughAllThreeAndBack() {
        var navigator = Self.inLibrary(["Gamma", "Alpha", "Beta"])

        #expect(navigator.receive(.action("sort")) == [.feedback(.commit)])
        #expect(titles(navigator) == ["Alpha", "Beta", "Gamma"])

        _ = navigator.receive(.action("sort"))
        #expect(titles(navigator) == ["Gamma", "Beta", "Alpha"])

        _ = navigator.receive(.action("sort"))
        #expect(titles(navigator) == ["Gamma", "Alpha", "Beta"], "and round to the host's order")
    }

    /// **The reason this exists.** Plain `<` puts `Lecture 10` before `Lecture 2`, which is the
    /// wrong answer for exactly the library that most wants sorting — a numbered series.
    @Test func digitsCompareAsNumbersNotAsText() {
        var navigator = Self.inLibrary(["Lecture 10", "Lecture 2", "Lecture 1"])

        _ = navigator.receive(.action("sort"))

        #expect(titles(navigator) == ["Lecture 1", "Lecture 2", "Lecture 10"])
    }

    /// **Folders stay first in every order.** They are the shelves; a shelf sorted in among the
    /// files is a list you have to read in order to navigate.
    @Test func foldersLeadWhicheverWayTheFilesGo() {
        var content = Self.named(["Zebra", "Apple"])
        content.recordings.append(
            DialContent.Item(id: "folder-1", title: "Middle", duration: 0, children: [])
        )
        var navigator = DialNavigator(content: content, root: .library)
        _ = navigator.receive(.press)

        _ = navigator.receive(.action("sort"))
        #expect(titles(navigator) == ["Middle", "Apple", "Zebra"])

        _ = navigator.receive(.action("sort"))
        #expect(titles(navigator) == ["Middle", "Zebra", "Apple"], "still first, going the other way")
    }

    /// **The order belongs to the list, not to the reader.**
    ///
    /// It was one setting for the whole navigator, so sorting the library re-sorted every folder
    /// you opened afterwards — an order chosen for one list imposed on all the others. A folder of
    /// lectures wants A–Z and the library above it wants newest-first, and both are right.
    @Test func aFolderKeepsItsOwnOrderRatherThanInheritingTheOneAbove() {
        var content = DialContent()
        content.recordings = [
            DialContent.Item(id: "folder-1", title: "Lectures", duration: 0, children: [
                DialContent.Item(id: "rec-b", title: "Beta", duration: 60),
                DialContent.Item(id: "rec-a", title: "Alpha", duration: 60)
            ])
        ]
        var navigator = DialNavigator(content: content, root: .library)
        _ = navigator.receive(.press)
        _ = navigator.receive(.action("sort"))      // A–Z at the root

        _ = navigator.receive(.press)               // into the folder

        #expect(titles(navigator) == ["Beta", "Alpha"], "the order it was handed over in")
        #expect(navigator.level.sort == .newest)

        _ = navigator.receive(.action("sort"))
        #expect(titles(navigator) == ["Alpha", "Beta"], "and it sorts on its own")
    }

    /// And going back finds the order you left the level in — the highlight is not the only thing
    /// a level remembers.
    @Test func comingBackFindsTheOrderYouLeftBehind() {
        var content = DialContent()
        content.recordings = [
            DialContent.Item(id: "folder-1", title: "Lectures", duration: 0, children: []),
            DialContent.Item(id: "rec-z", title: "Zebra", duration: 60),
            DialContent.Item(id: "rec-a", title: "Apple", duration: 60)
        ]
        var navigator = DialNavigator(content: content, root: .library)
        _ = navigator.receive(.press)
        _ = navigator.receive(.action("sort"))      // A–Z
        _ = navigator.receive(.press)               // into the folder

        _ = navigator.receive(.action("back"))

        #expect(titles(navigator) == ["Lectures", "Apple", "Zebra"])
    }

    /// **What the hub opens has to be what the row says**, which is why the sort is applied in
    /// `items(atDepth:)` rather than in the projection: the press indexes the same ordered list the
    /// rows are drawn from.
    @Test func pressingAfterSortingOpensTheRowYouCanSee() {
        var navigator = Self.inLibrary(["Gamma", "Alpha", "Beta"])
        _ = navigator.receive(.action("sort"))      // Alpha, Beta, Gamma

        _ = navigator.receive(.tick(2))             // Gamma, now last

        #expect(DialSample.playedID(navigator.receive(.press)) == "rec-0")
    }

    /// A list with nothing to reorder refuses rather than cycling a setting with no visible effect.
    @Test func aListOfOneCannotBeSorted() {
        var navigator = Self.inLibrary(["Only"])

        #expect(navigator.receive(.action("sort")) == [.feedback(.limit)])
        #expect(navigator.level.sort == .newest)
    }

    @Test func theChipCarriesTheCurrentOrderAndSaysWhenItIsNotTheDefault() {
        var navigator = Self.inLibrary(["Gamma", "Alpha", "Beta"])

        let byDefault = navigator.screen.actions.first { $0.id == "sort" }
        #expect(byDefault?.label == "Newest first")
        #expect(byDefault?.emphasis == .plain)

        _ = navigator.receive(.action("sort"))

        let sorted = navigator.screen.actions.first { $0.id == "sort" }
        #expect(sorted?.label == "Sorted A to Z")
        #expect(sorted?.emphasis == .selected, "the fill is what says it is not the default")
    }
}
