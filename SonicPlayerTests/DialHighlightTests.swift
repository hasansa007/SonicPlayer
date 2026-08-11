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

    /// **The ring is the card, top to bottom.** Three files in the library is **nine** positions,
    /// in the order they are drawn:
    ///
    ///     0  1  2                the files
    ///     3 … 7                  the chips: Record, Import, New folder, Sort, Settings
    ///
    /// Nothing sits above the list any more — Record and Import were the last things pinned there
    /// and they are chips now, so the ring starts at row 0. **Back is not in the span at the root**,
    /// because it is not drawn there: a chip that cannot do anything is not a stop worth turning to.
    /// Every count in this section is that count, which is why they move together whenever the row
    /// changes; the arithmetic is deliberately in one place so that is the only cost.
    @Test func turningPastTheLastRowLandsOnTheFirstChip() {
        var navigator = DialSample.inRecordings(recordingCount: 3)
        _ = navigator.receive(.tick(2))             // the last file, row 2

        let effects = navigator.receive(.tick(1))

        #expect(navigator.highlightedChipID == "record")
        #expect(highlight(navigator) == -1, "and no row wears the cursor")
        #expect(effects == [.feedback(.detent)], "a move is a detent, not a wall")
    }

    /// **The ring wraps in both directions.** It clamped until `Delete` got a confirmation dialog —
    /// the whole argument for a wall was that overshooting the top of a menu would land a thumb on
    /// the destructive row. Guarded, that objection goes, and a wheel with no ends stops having to
    /// explain which end you are against through a pulse that means four other things.
    @Test func turningBackOffTheFirstRowLandsOnTheLastChip() {
        var navigator = DialSample.inRecordings(recordingCount: 3)

        _ = navigator.receive(.tick(-1))

        #expect(navigator.highlightedChipID == "settings", "the last chip, drawn rightmost")
    }

    @Test func aFullRevolutionComesBackToTheFirstRow() {
        var navigator = DialSample.inRecordings(recordingCount: 3)

        _ = navigator.receive(.tick(8))             // eight positions

        #expect(highlight(navigator) == 0)
    }

    /// A flick far larger than the list still lands somewhere sensible rather than running out of
    /// bounds — `detents` is reduced modulo the ring before it is applied.
    @Test func aFlickLongerThanTheListStillLands() {
        var navigator = DialSample.inRecordings(recordingCount: 3)   // 8 positions, highlight on 0

        let effects = navigator.receive(.tick(41))                   // 41 % 8 == 1

        #expect(highlight(navigator) == 1)
        #expect(effects == [.feedback(.detent)])
    }

    /// **The one honest limit left.** A spin of exactly a whole number of revolutions ends where it
    /// started, and a tick that changes nothing reports `.limit` — the law this suite opens with,
    /// which wrapping does not repeal.
    @Test func awholeNumberOfRevolutionsChangesNothing() {
        var navigator = DialSample.inRecordings(recordingCount: 3)   // 8 positions

        let effects = navigator.receive(.tick(40))                   // 40 % 8 == 0

        #expect(highlight(navigator) == 0)
        #expect(effects == [.feedback(.limit)])
    }

    // MARK: - Nothing to scroll

    /// **Nothing is immovable, and that is the point of the chips being stops.** An empty library
    /// has no rows at all and still six positions to turn between — a screen you can operate
    /// without touching it, which is the whole of what these changes were for.
    @Test func anEmptyListStillHasItsChipsToTurnBetween() {
        var navigator = DialSample.inRecordings(recordingCount: 0)

        let effects = navigator.receive(.tick(1))

        #expect(effects == [.feedback(.detent)])
        #expect(navigator.highlightedChipID != nil)
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
        // Five files and five chips — ten positions, and row 2 is the third of them.
        #expect(abs((thumb ?? .nan) - 2.0 / 9.0) < 1e-9)
    }

    @Test func theThumbSitsAtEachEndOnTheFirstAndLastStop() {
        var navigator = DialSample.inRecordings(recordingCount: 5)
        #expect(navigator.screen.ring.ticks == .browse(thumb: 0), "row 0 is the top of the travel")

        _ = navigator.receive(.tick(-1))
        #expect(navigator.screen.ring.ticks == .browse(thumb: 1), "and the last chip is the bottom")
    }

    /// **There is no thumbless browse screen left.**
    ///
    /// This asserted that an empty library has no span to place a thumb along, which held while the
    /// list was the whole ring — no rows, nothing to point at. Its five chips are stops, so it has a
    /// span of five and the thumb sits at the top of it, on the first thing there is to do.
    @Test func anEmptyListPlacesItsThumbOnTheFirstChip() {
        let navigator = DialSample.inRecordings(recordingCount: 0)

        #expect(navigator.highlightedChipID == "record")
        #expect(navigator.screen.ring.ticks == .browse(thumb: 0))
    }
}
