import Foundation
import Testing

@testable import SonicPlayer

/// The navigator hands the UI finished strings, so the rules that make them are worth pinning (#6).
@Suite
struct DialTimeFormatTests {

    @Test func minutesAndSecondsArePadded() {
        #expect(DialTimeFormat.clock(492) == "08:12")
        #expect(DialTimeFormat.clock(1234) == "20:34")
    }

    @Test func anHourGrowsAThirdField() {
        #expect(DialTimeFormat.clock(3723) == "1:02:03")
    }

    /// The one that bites: 59.7s must read `00:59`, not `01:00`, or the clock reaches the next
    /// minute before the audio does.
    @Test func secondsTruncateRatherThanRound() {
        #expect(DialTimeFormat.clock(59.7) == "00:59")
    }

    /// Positions arrive from a player that can report a small negative while seeking, and NaN
    /// before the asset loads. Neither may reach the screen.
    @Test func nonsenseTimesReadAsTheStart() {
        #expect(DialTimeFormat.clock(-4) == "00:00")
        #expect(DialTimeFormat.clock(.nan) == "00:00")
        #expect(DialTimeFormat.clock(.infinity) == "00:00")
    }

    /// The contract's own example is `"−25:11"`, with a real minus sign rather than a hyphen.
    @Test func remainingCarriesItsSign() {
        #expect(DialTimeFormat.remaining(1511) == "−25:11")
    }

    @Test func nothingRemainingIsStillSigned() {
        #expect(DialTimeFormat.remaining(0) == "−00:00")
    }

    @Test func tenthsAreASingleDigit() {
        #expect(DialTimeFormat.tenths(727.4) == "4")
        #expect(DialTimeFormat.tenths(727.0) == "0")
    }

    /// 0.999 is nine tenths, not ten — a `9` that becomes a second digit would break the layout.
    @Test func tenthsNeverCarryIntoTheSeconds() {
        #expect(DialTimeFormat.tenths(0.999) == "9")
    }
}
