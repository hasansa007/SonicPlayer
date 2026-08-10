import Foundation
import Testing

@testable import SonicPlayer

/// Turning the wheel over a list, and what the ends of it feel like (#6).
///
/// **The law under every test here: a tick that changes nothing reports `.limit`, and a tick that
/// changes anything reports `.detent`.** It holds for the highlight, for seeking, for volume, for
/// gain and for both trim handles, which is why it is worth stating once rather than per screen.
@Suite
struct DialHighlightTests {

    private func highlight(_ navigator: DialNavigator) -> Int? {
        guard case .list(let list) = navigator.screen.content else { return nil }
        return list.highlighted
    }

    // `#expect` captures its expression in a closure, so a `mutating` call written inside one fails
    // to compile against an immutable copy. Every result below is bound to a local first.

    @Test func oneTickMovesOneRow() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.tick(1))

        #expect(highlight(navigator) == 1)
        #expect(effects == [.feedback(.detent)])
    }

    /// `RotaryTracker` has already multiplied by its acceleration, so five means five rows.
    @Test func fiveTicksMoveFiveRowsNotFiveDegrees() {
        var navigator = DialSample.inRecordings()

        _ = navigator.receive(.tick(5))

        #expect(highlight(navigator) == 5)
    }

    @Test func turningBackwardsMovesBackwards() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.tick(5))

        _ = navigator.receive(.tick(-2))

        #expect(highlight(navigator) == 3)
    }

    @Test func aZeroTickDoesNothingAtAll() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.tick(0))

        #expect(effects.isEmpty)
    }

    // MARK: - The ends, which are no longer ends

    /// **The ring is the card, top to bottom — not just the list.**
    ///
    /// Three files inside the library is **seven** positions, in the order they are drawn:
    ///
    ///     -1  the pinned verb, above the list
    ///      0  1  2   the files
    ///      3  4  5   the chips: Back, New folder, Sort
    ///
    /// Every count in this section is that count, which is why they all move together every time a
    /// chip is added — the arithmetic is deliberately in one place so that is the only cost. A stop
    /// that is not a row reports `list.highlighted == -1`, because on it no *row* is highlighted;
    /// the clamp that used to hand the cursor back to the nearest row drew two selections at once.
    @Test func turningBackPastTheFirstRowLandsOnTheVerb() {
        var navigator = DialSample.inRecordings(recordingCount: 3)

        let effects = navigator.receive(.tick(-1))

        #expect(navigator.isPinnedActionHighlighted, "back off the first row is Import")
        #expect(highlight(navigator) == -1, "and no row wears the cursor")
        #expect(effects == [.feedback(.detent)], "a move is a detent, not a wall")
    }

    /// **The ring still wraps in both directions.** It clamped until `Delete` got a confirmation
    /// dialog — the whole argument for a wall was that overshooting the top of the actions menu
    /// would land a thumb on the destructive row. Guarded, that objection goes, and a wheel with no
    /// ends stops having to explain which end you are against through a pulse that means four other
    /// things. The stops are two more positions on that ring, not walls at the ends of it.
    @Test func turningBackPastTheVerbLandsOnTheLastChip() {
        var navigator = DialSample.inRecordings(recordingCount: 3)

        _ = navigator.receive(.tick(-2))

        #expect(navigator.highlightedChipID == "sort", "past the top is round to the last chip")
    }

    @Test func turningPastTheLastRowLandsOnBack() {
        var navigator = DialSample.inRecordings(recordingCount: 3)
        _ = navigator.receive(.tick(2))             // the last file, row 2

        let effects = navigator.receive(.tick(1))

        #expect(navigator.isBackHighlighted)
        #expect(highlight(navigator) == -1)
        #expect(effects == [.feedback(.detent)])
    }

    @Test func theChipsAreTheNextThreeStopsInDrawOrder() {
        var navigator = DialSample.inRecordings(recordingCount: 3)
        _ = navigator.receive(.tick(2))            // the last file

        _ = navigator.receive(.tick(1))
        #expect(navigator.highlightedChipID == "back")
        _ = navigator.receive(.tick(1))
        #expect(navigator.highlightedChipID == "newFolder")
        _ = navigator.receive(.tick(1))
        #expect(navigator.highlightedChipID == "sort")
        _ = navigator.receive(.tick(1))
        #expect(navigator.isPinnedActionHighlighted, "and round to the verb above the list")
    }

    @Test func aFullRevolutionComesBackToTheFirstRow() {
        var navigator = DialSample.inRecordings(recordingCount: 3)

        _ = navigator.receive(.tick(7))            // seven positions

        #expect(highlight(navigator) == 0)
    }

    /// A flick far larger than the list still lands somewhere sensible rather than running out of
    /// bounds — `detents` is reduced modulo the ring before it is applied.
    @Test func aFlickLongerThanTheListStillLands() {
        var navigator = DialSample.inRecordings(recordingCount: 3)   // 7 positions, highlight on 0

        let effects = navigator.receive(.tick(43))                   // 43 % 7 == 1

        #expect(highlight(navigator) == 1)
        #expect(effects == [.feedback(.detent)])
    }

    /// **The one honest limit left.** A spin of exactly a whole number of revolutions ends where it
    /// started, and a tick that changes nothing reports `.limit` — the law this suite opens with,
    /// which wrapping does not repeal.
    @Test func awholeNumberOfRevolutionsChangesNothing() {
        var navigator = DialSample.inRecordings(recordingCount: 3)   // 7 positions

        let effects = navigator.receive(.tick(42))                   // 42 % 7 == 0

        #expect(highlight(navigator) == 0)
        #expect(effects == [.feedback(.limit)])
    }

    // MARK: - Nothing to scroll

    /// **Nothing is immovable any more, and that is the point of the stops.**
    ///
    /// This asserted that an empty library has nothing to turn through — true while the list was
    /// the whole ring. An empty library still has its verb and its Back, so there are two positions
    /// and the wheel moves between them. A screen you can turn on is a screen you can operate
    /// without touching it, which is the whole of what these two changes were for.
    @Test func evenAnEmptyListHasItsTwoControlsToTurnBetween() {
        var navigator = DialSample.inRecordings(recordingCount: 0)
        #expect(navigator.isPinnedActionHighlighted, "and it opens on the verb, not on the way out")

        let effects = navigator.receive(.tick(1))

        #expect(effects == [.feedback(.detent)])
        #expect(navigator.isBackHighlighted)
    }

    /// One file is five positions: Import, the file, then the three chips.
    @Test func aSingleFileSitsAmongItsControls() {
        var navigator = DialSample.inRecordings(recordingCount: 1)

        #expect(navigator.receive(.tick(1)) == [.feedback(.detent)])
        #expect(navigator.isBackHighlighted)

        _ = navigator.receive(.tick(3))
        #expect(navigator.isPinnedActionHighlighted, "past the last chip and round")
    }

    // MARK: - The ring follows the highlight

    /// `Ticks.browse(thumb:)` exists to light the tick you are on, so it has to track the
    /// highlight — **measured along the whole ring, both stops included.** Counting only the files
    /// would leave the thumb still while the highlight moved onto a control, which reports the
    /// wheel as stuck exactly where it is not.
    @Test func theRingsThumbFollowsTheHighlight() {
        var navigator = DialSample.inRecordings(recordingCount: 5)

        _ = navigator.receive(.tick(2))

        guard case .browse(let thumb) = navigator.screen.ring.ticks else {
            Issue.record("expected browse ticks, got \(navigator.screen.ring.ticks)")
            return
        }
        // Import, five files, three chips — nine positions, and row 2 is the fourth of them.
        #expect(abs((thumb ?? .nan) - 0.375) < 1e-9)
    }

    @Test func theThumbSitsAtEachEndOnTheFirstAndLastStop() {
        var navigator = DialSample.inRecordings(recordingCount: 5)

        _ = navigator.receive(.tick(-1))
        #expect(navigator.screen.ring.ticks == .browse(thumb: 0), "Import is the top of the travel")

        _ = navigator.receive(.tick(-1))
        #expect(navigator.screen.ring.ticks == .browse(thumb: 1), "and the last chip is the bottom")
    }

    /// **There is no thumbless browse screen left.**
    ///
    /// This asserted that an empty library has no span to place a thumb along, which held while the
    /// list was the whole ring — no rows, nothing to point at. It has two controls now, so it has a
    /// span of two and the thumb sits at the top of it, on the verb the screen opens on.
    @Test func anEmptyListPlacesItsThumbOnTheVerbItOpensOn() {
        let navigator = DialSample.inRecordings(recordingCount: 0)

        #expect(navigator.isPinnedActionHighlighted)
        #expect(navigator.screen.ring.ticks == .browse(thumb: 0))
    }
}
