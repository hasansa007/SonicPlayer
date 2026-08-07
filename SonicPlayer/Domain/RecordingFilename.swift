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
    /// **A filename is data, not UI, so it does not follow the device (#23).** `locale` and
    /// `calendar` default to POSIX and Gregorian rather than `.current`, which is Apple's
    /// documented remedy (QA1480) for a formatter driven by a fixed `dateFormat`. Following the
    /// device broke two ways:
    ///
    /// - **Digits.** This app ships `ar`, `bn` and `hi`; a device using a non-Western numbering
    ///   system produced `Recording ٢٠٢٦-٠٨-٠٦ ١٤.١٤.٥٧.m4a`, which sorts unpredictably and
    ///   round-trips through share sheets and desktop sync by luck.
    /// - **Collisions.** `DateFormatter` may honour the user's 24-Hour Time setting over the
    ///   pattern, so `HH` could render 12-hour: 14:14:57 and 02:14:57 both became `02.14.57`, and
    ///   the second take was silently deduped to `... 2.m4a` as though it were a duplicate.
    ///
    /// A non-Gregorian device calendar was the same class of bug and worse — a Hijri device would
    /// have written year 1447. Both parameters stay injectable; only the defaults changed.
    ///
    /// Existing recordings keep the names they were written with, so a device that has been
    /// recording in Arabic-Indic digits ends up with a mixed library. Accepted deliberately:
    /// renaming a user's files to tidy a format is more intrusive than the inconsistency.
    static func make(
        at date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = .current,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = locale
        return "Recording \(formatter.string(from: date)).\(fileExtension)"
    }
}
