import Foundation

/// Generates the filename for a new recording.
///
/// Extracted from `RecordingFeature.startRecordingTapped`. The date is a parameter rather than
/// read from `Date()` inside, which is what makes the format testable — the reducer previously
/// called `Date()` directly, so nothing about the name could be asserted.
enum RecordingFilename {

    /// Dots rather than colons in the time: colons are legal in HFS+ paths but display as `/`
    /// in Finder and break round-tripping through some share sheets.
    static let dateFormat = "yyyy-MM-dd HH.mm.ss"

    static let fileExtension = "m4a"

    /// e.g. `Recording 2026-08-06 14.14.57.m4a`
    ///
    /// `locale` defaults to `.current`, matching the bare `DateFormatter` this replaced — tests
    /// pass `en_US_POSIX` for determinism. Do **not** hardcode POSIX here: on a device using a
    /// non-Western numbering system (this app ships ar, bn and hi) the current behaviour renders
    /// the digits in that system, and #11 is behaviour-preserving. See #23 for why that is worth
    /// changing deliberately rather than as a side effect of an extraction.
    static func make(
        at date: Date,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = locale
        return "Recording \(formatter.string(from: date)).\(fileExtension)"
    }
}
