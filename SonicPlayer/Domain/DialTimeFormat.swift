import Foundation

/// Times as the dial's UI receives them: already strings (#6).
///
/// `DialScreen` takes `elapsed`, `remaining` and `keeping` as text rather than seconds, and the
/// comment there says why — "the navigator owns the clock and the UI owns none of it". This is the
/// other end of that decision. It exists so there is exactly one answer to "what does 59.7 seconds
/// look like", instead of the four hand-rolled `String(format:)` calls the older screens each carry.
///
/// **Truncating rather than rounding is the rule, and it is not cosmetic.** A clock that rounds
/// reaches `01:00` while the audio is still in the fifty-ninth second, so the elapsed and remaining
/// halves of Now Playing disagree by a second at every boundary.
enum DialTimeFormat {

    /// `08:12`, or `1:02:03` once there is an hour to show.
    ///
    /// A negative, NaN or infinite input is the start. Positions arrive from a player that reports
    /// NaN before the asset loads and can report a small negative mid-seek; neither is a time, and
    /// the screen is not the place to discover that.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = wholeSeconds(seconds)
        let (hours, minutes, secs) = (total / 3600, (total % 3600) / 60, total % 60)

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    /// The same clock with a leading minus — `−25:11`.
    ///
    /// U+2212 MINUS SIGN rather than a hyphen, because it is being read as arithmetic at the same
    /// size as the digits beside it, and a hyphen sits too high and too short to match them.
    static func remaining(_ seconds: TimeInterval) -> String {
        "−" + clock(seconds)
    }

    /// The single tenths digit drawn smaller after the recording clock: `12:07` + `4`.
    ///
    /// Truncated for the same reason as `clock`, which also guarantees the answer stays one
    /// character: rounding 0.999 would carry to `10`, and the layout has room for one digit.
    static func tenths(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0" }
        return String(Int(seconds * 10) % 10)
    }

    private static func wholeSeconds(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(seconds)
    }
}
