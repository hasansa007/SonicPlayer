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

    // MARK: - The ends

    /// **Clamping, not wrapping** — and the wall has to be felt or it is not a wall.
    @Test func theTopOfTheListIsAWall() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.tick(-1))

        #expect(highlight(navigator) == 0)
        #expect(effects == [.feedback(.limit)])
    }

    @Test func theBottomOfTheListIsAWall() {
        var navigator = DialSample.inRecordings(recordingCount: 3)
        _ = navigator.receive(.tick(2))

        let effects = navigator.receive(.tick(1))

        #expect(highlight(navigator) == 2)
        #expect(effects == [.feedback(.limit)])
    }

    /// A spin that overshoots still lands, and landing is a detent. Only the *next* tick, which
    /// moves nothing, is the limit — which is exactly how a real detented wheel behaves.
    @Test func overshootingLandsOnTheEndAndStillClicks() {
        var navigator = DialSample.inRecordings(recordingCount: 3)

        let landing = navigator.receive(.tick(40))
        let afterwards = navigator.receive(.tick(40))

        #expect(highlight(navigator) == 2)
        #expect(landing == [.feedback(.detent)])
        #expect(afterwards == [.feedback(.limit)])
    }

    /// Wrapping would put the last row — `Delete`, on the actions screen — under a thumb that
    /// overshot the top. Clamping is the choice, and this is the case that decides it.
    @Test func theListDoesNotWrapAround() {
        var navigator = DialSample.inRecordings(recordingCount: 3)
        _ = navigator.receive(.tick(2))

        _ = navigator.receive(.tick(1))

        #expect(highlight(navigator) == 2)
    }

    // MARK: - Nothing to scroll

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

    @Test func aSingleRowHasNoThumbToPlace() {
        var navigator = DialSample.inRecordings(recordingCount: 1)

        _ = navigator.receive(.tick(1))

        #expect(navigator.screen.ring.ticks == .browse(thumb: nil))
    }
}
