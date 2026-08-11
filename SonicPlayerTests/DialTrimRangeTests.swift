import Foundation
import Testing

@testable import SonicPlayer

/// The trim editor's one invariant: `in ≤ out − minimumLength`, and no route around it (#6).
///
/// Computed times are compared with a tolerance rather than `==` — a handle nudged three times by
/// `0.1` lands on `0.30000000000000004`, and the rule is "three detents is three tenths", not the
/// last bit of a double.
@Suite
struct DialTrimRangeTests {

    private let tolerance: TimeInterval = 1e-9

    // `#expect` captures its expression in a closure, so a `mutating` call written inside one fails
    // to compile against an immutable copy. Every result below is bound to a local first.

    @Test func nudgingAHandleMovesItByThatMuch() {
        var range = DialTrimRange(start: 10, end: 40, duration: 60)

        let moved = range.moveStart(by: 1.5)

        #expect(moved)
        #expect(abs(range.start - 11.5) < tolerance)
    }

    /// The whole reason this type exists rather than two `TimeInterval`s on the screen state.
    @Test func theStartCannotBeDraggedThroughTheEnd() {
        var range = DialTrimRange(start: 10, end: 40, duration: 60)

        _ = range.moveStart(by: 100)

        #expect(abs(range.start - (40 - DialTrimRange.minimumLength)) < tolerance)
        #expect(range.start < range.end)
    }

    @Test func theEndCannotBeDraggedThroughTheStart() {
        var range = DialTrimRange(start: 10, end: 40, duration: 60)

        _ = range.moveEnd(by: -100)

        #expect(abs(range.end - (10 + DialTrimRange.minimumLength)) < tolerance)
        #expect(range.start < range.end)
    }

    @Test func neitherHandleLeavesTheRecording() {
        var range = DialTrimRange(start: 10, end: 40, duration: 60)

        _ = range.moveStart(by: -100)
        _ = range.moveEnd(by: 100)

        #expect(range.start == 0)
        #expect(range.end == 60)
    }

    /// The signal the navigator turns into `.limit` feedback: a nudge that changed nothing.
    @Test func aNudgeThatChangesNothingSaysSo() {
        var range = DialTrimRange(start: 0, end: 60, duration: 60)

        let movedStart = range.moveStart(by: -1)
        let movedEnd = range.moveEnd(by: 1)

        #expect(!movedStart)
        #expect(!movedEnd)
    }

    /// Travel that is merely truncated still moved, so it is still a detent.
    @Test func aNudgeThatIsTruncatedStillCounts() {
        var range = DialTrimRange(start: 1, end: 60, duration: 60)

        let moved = range.moveStart(by: -10)

        #expect(moved)
        #expect(range.start == 0)
    }

    @Test func aCrossedRangeIsUncrossedOnTheWayIn() {
        let range = DialTrimRange(start: 50, end: 10, duration: 60)

        #expect(range.start <= range.end - DialTrimRange.minimumLength)
    }

    /// A recording shorter than the minimum keep has no valid trim, and must not answer with a
    /// range that runs past its own end.
    @Test func aRecordingShorterThanTheMinimumStillAnswersSanely() {
        let range = DialTrimRange(start: 0, end: 1, duration: 0.2)

        #expect(range.start == 0)
        #expect(range.end <= 0.2)
    }

    @Test func anUnloadedAssetIsAnEmptyRange() {
        let range = DialTrimRange(start: 3, end: 9, duration: 0)

        #expect(range.start == 0)
        #expect(range.end == 0)
        #expect(range.inFraction == 0)
        #expect(range.outFraction == 0)
    }

    @Test func fractionsAreTheHandlesOverTheDuration() {
        let range = DialTrimRange(start: 15, end: 45, duration: 60)

        #expect(abs(range.inFraction - 0.25) < tolerance)
        #expect(abs(range.outFraction - 0.75) < tolerance)
        #expect(abs(range.length - 30) < tolerance)
    }
}
