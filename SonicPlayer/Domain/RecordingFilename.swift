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
    static func make(at date: Date, calendar: Calendar = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "Recording \(formatter.string(from: date)).\(fileExtension)"
    }
}
