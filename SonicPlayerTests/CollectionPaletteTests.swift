import Foundation
import Testing

@testable import SonicPlayer

/// Which gradient and glyph a collection card gets (#48).
///
/// Extracted from two `private static let` arrays on `CollectionsView` indexed by
/// `index % count`. The arrays are presentation, but *which card gets which look* is a decision,
/// and it has a property worth pinning: it must depend on the folder, not on where the folder
/// happens to sit in a filtered list.
@Suite
struct CollectionPaletteTests {

    @Test func test_theCatalogueIsNotEmpty() {
        #expect(!CollectionPalette.gradientCount.isMultiple(of: 0))
        #expect(CollectionPalette.gradientCount > 0)
        #expect(CollectionPalette.iconCount > 0)
    }

    @Test func test_slotsWrapAroundRatherThanRunningOffTheEnd() {
        let beyond = CollectionPalette.gradientCount * 3 + 2

        #expect(CollectionPalette.slot(forName: "x", at: beyond) < CollectionPalette.gradientCount)
        #expect(CollectionPalette.slot(forName: "x", at: -1) >= 0)
    }

    /// The behaviour change this extraction exists to make possible.
    ///
    /// The old code used the folder's **position in the filtered list**, so typing in the search
    /// box recoloured every card still on screen, and deleting the first folder recoloured all
    /// the rest. A folder's colour is now a function of its name, so it is stable.
    @Test func test_aFoldersLook_followsItsNameRatherThanItsPosition() {
        let first = CollectionPalette.slot(forName: "Term 1", at: 0)
        let moved = CollectionPalette.slot(forName: "Term 1", at: 4)

        #expect(first == moved, "Filtering a list must not recolour the cards that survive (#48).")
    }

    @Test func test_differentFolders_generallyGetDifferentSlots() {
        let names = ["Term 1", "Podcasts", "Interviews", "Lectures", "Voice Memos"]
        let slots = Set(names.map { CollectionPalette.slot(forName: $0, at: 0) })

        #expect(slots.count > 1, "A palette that gives every folder the same slot is not a palette.")
    }

    /// Same name, same slot, every launch — the hash must not be `Hasher`'s, which is seeded per
    /// process and would recolour the whole screen between runs.
    @Test func test_theSameName_resolvesToTheSameSlotEveryTime() {
        let once = CollectionPalette.slot(forName: "Ω Lectures — 2026", at: 0)

        #expect(CollectionPalette.slot(forName: "Ω Lectures — 2026", at: 0) == once)
        #expect(CollectionPalette.slot(forName: "Ω Lectures — 2026", at: 99) == once)
    }

    @Test func test_anEmptyName_isStillGivenSomethingToDraw() {
        let slot = CollectionPalette.slot(forName: "", at: 0)

        #expect(slot >= 0 && slot < CollectionPalette.gradientCount)
    }
}
