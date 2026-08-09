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

    // `inRecordings` lands on the first *recording*, which is row 1 — Import is row 0.

    @Test func oneTickMovesOneRow() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.tick(1))

        #expect(highlight(navigator) == 2)
        #expect(effects == [.feedback(.detent)])
    }

    /// `RotaryTracker` has already multiplied by its acceleration, so five means five rows.
    @Test func fiveTicksMoveFiveRowsNotFiveDegrees() {
        var navigator = DialSample.inRecordings()

        _ = navigator.receive(.tick(5))

        #expect(highlight(navigator) == 6)
    }

    @Test func turningBackwardsMovesBackwards() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.tick(5))

        _ = navigator.receive(.tick(-2))

        #expect(highlight(navigator) == 4)
    }

    @Test func aZeroTickDoesNothingAtAll() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.tick(0))

        #expect(effects.isEmpty)
    }

    // MARK: - The ends, which are no longer ends

    /// **The list wraps in both directions.** It clamped until `Delete` got a confirmation dialog —
    /// the whole argument for a wall was that overshooting the top of the actions menu would land a
    /// thumb on the destructive row. Guarded, that objection goes, and a wheel with no ends stops
    /// having to explain which end you are against through a pulse that means four other things.
    @Test func turningBackPastTheFirstRowLandsOnTheLast() {
        var navigator = DialSample.inRecordings(recordingCount: 3)
        _ = navigator.receive(.tick(-1))            // onto Import, row 0

        let effects = navigator.receive(.tick(-1))

        #expect(highlight(navigator) == 3, "Import plus three recordings — round to the last")
        #expect(effects == [.feedback(.detent)], "a move is a detent, not a wall")
    }

    @Test func turningPastTheLastRowLandsOnTheFirst() {
        var navigator = DialSample.inRecordings(recordingCount: 3)
        _ = navigator.receive(.tick(2))             // the last recording, row 3

        let effects = navigator.receive(.tick(1))

        #expect(highlight(navigator) == 0)
        #expect(effects == [.feedback(.detent)])
    }

    /// A flick far larger than the list still lands somewhere sensible rather than running out of
    /// bounds — `detents` is reduced modulo the row count before it is applied.
    @Test func aFlickLongerThanTheListStillLands() {
        var navigator = DialSample.inRecordings(recordingCount: 3)   // 4 rows, highlight on 1

        let effects = navigator.receive(.tick(41))                   // 41 % 4 == 1

        #expect(highlight(navigator) == 2)
        #expect(effects == [.feedback(.detent)])
    }

    /// **The one honest limit left.** A spin of exactly a whole number of revolutions ends where it
    /// started, and a tick that changes nothing reports `.limit` — the law this suite opens with,
    /// which wrapping does not repeal.
    @Test func awholeNumberOfRevolutionsChangesNothing() {
        var navigator = DialSample.inRecordings(recordingCount: 3)   // 4 rows

        let effects = navigator.receive(.tick(40))                   // 40 % 4 == 0

        #expect(highlight(navigator) == 1)
        #expect(effects == [.feedback(.limit)])
    }

    // MARK: - Nothing to scroll

    /// One row cannot wrap onto itself. An empty library is exactly that — the Import row alone.
    @Test func aSingleRowListHasNothingToMoveAndSaysSo() {
        var navigator = DialSample.navigator(recordingCount: 0)
        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)

        let effects = navigator.receive(.tick(1))

        #expect(effects == [.feedback(.limit)])
    }

    // MARK: - The ring follows the highlight

    /// `Ticks.browse(thumb:)` exists to light the tick you are on, so it has to track the row.
    @Test func theRingsThumbFollowsTheHighlight() {
        // Five recordings and the Import row is six, so the midpoint is row 3 — the highlight opens
        // on row 1 and two ticks reach it.
        var navigator = DialSample.inRecordings(recordingCount: 5)

        _ = navigator.receive(.tick(2))

        guard case .browse(let thumb) = navigator.screen.ring.ticks else {
            Issue.record("expected browse ticks, got \(navigator.screen.ring.ticks)")
            return
        }
        #expect(abs((thumb ?? .nan) - 0.6) < 1e-9)
    }

    /// A one-row list has no span to place a thumb along. Only the empty library is one row now —
    /// a single recording is two, because Import is always above it.
    @Test func aSingleRowHasNoThumbToPlace() {
        var navigator = DialSample.navigator(recordingCount: 0)
        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)

        #expect(navigator.screen.ring.ticks == .browse(thumb: nil))
    }
}
