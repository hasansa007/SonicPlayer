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

    /// **The list wraps in both directions.** It clamped until `Delete` got a confirmation dialog —
    /// the whole argument for a wall was that overshooting the top of the actions menu would land a
    /// thumb on the destructive row. Guarded, that objection goes, and a wheel with no ends stops
    /// having to explain which end you are against through a pulse that means four other things.
    @Test func turningBackPastTheFirstRowLandsOnTheLast() {
        var navigator = DialSample.inRecordings(recordingCount: 3)

        let effects = navigator.receive(.tick(-1))

        #expect(highlight(navigator) == 2, "three recordings — round to the last")
        #expect(effects == [.feedback(.detent)], "a move is a detent, not a wall")
    }

    @Test func turningPastTheLastRowLandsOnTheFirst() {
        var navigator = DialSample.inRecordings(recordingCount: 3)
        _ = navigator.receive(.tick(2))             // the last recording

        let effects = navigator.receive(.tick(1))

        #expect(highlight(navigator) == 0)
        #expect(effects == [.feedback(.detent)])
    }

    /// A flick far larger than the list still lands somewhere sensible rather than running out of
    /// bounds — `detents` is reduced modulo the row count before it is applied.
    @Test func aFlickLongerThanTheListStillLands() {
        var navigator = DialSample.inRecordings(recordingCount: 3)   // 3 rows, highlight on 0

        let effects = navigator.receive(.tick(31))                   // 31 % 3 == 1

        #expect(highlight(navigator) == 1)
        #expect(effects == [.feedback(.detent)])
    }

    /// **The one honest limit left.** A spin of exactly a whole number of revolutions ends where it
    /// started, and a tick that changes nothing reports `.limit` — the law this suite opens with,
    /// which wrapping does not repeal.
    @Test func awholeNumberOfRevolutionsChangesNothing() {
        var navigator = DialSample.inRecordings(recordingCount: 3)   // 3 rows

        let effects = navigator.receive(.tick(30))                   // 30 % 3 == 0

        #expect(highlight(navigator) == 0)
        #expect(effects == [.feedback(.limit)])
    }

    // MARK: - Nothing to scroll

    /// An empty list has nothing to move, and a one-row list cannot wrap onto itself.
    @Test func anEmptyListHasNothingToMoveAndSaysSo() {
        var navigator = DialSample.navigator(recordingCount: 0)
        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)

        let effects = navigator.receive(.tick(1))

        #expect(effects == [.feedback(.limit)])
    }

    // MARK: - The ring follows the highlight

    /// `Ticks.browse(thumb:)` exists to light the tick you are on, so it has to track the row.
    @Test func theRingsThumbFollowsTheHighlight() {
        var navigator = DialSample.inRecordings(recordingCount: 5)

        _ = navigator.receive(.tick(2))

        guard case .browse(let thumb) = navigator.screen.ring.ticks else {
            Issue.record("expected browse ticks, got \(navigator.screen.ring.ticks)")
            return
        }
        #expect(abs((thumb ?? .nan) - 0.5) < 1e-9)
    }

    /// A one-row list has no span to place a thumb along.
    @Test func aSingleRowHasNoThumbToPlace() {
        var navigator = DialSample.inRecordings(recordingCount: 1)

        _ = navigator.receive(.tick(1))

        #expect(navigator.screen.ring.ticks == .browse(thumb: nil))
    }
}
