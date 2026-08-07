import Foundation
import Testing

@testable import SonicPlayer

/// Characterization tests for session persistence, restore backoff and recording filenames.
/// No TCA. `SessionCodec`'s output shape is a compatibility boundary — Slice 6 (#15) replaces
/// `@Shared(.fileStorage)` with a hand-rolled store writing the same JSON to the same path, so
/// these tests are what proves the swap did not orphan anyone's saved session.
@Suite
struct SessionDomainTests {

    private func url(_ p: String) -> URL { URL(fileURLWithPath: p) }

    // MARK: - SessionCodec: when to clear rather than save

    @Test func test_lastTrackPlayedToTheEnd_isFinished() {
        #expect(SessionCodec.isFinishedAtEndOfQueue(currentIndex: 2, queueCount: 3, currentTime: 99.6, duration: 100))
    }

    @Test func test_lastTrackStoppedPartway_isNotFinished() {
        #expect(!(SessionCodec.isFinishedAtEndOfQueue(currentIndex: 2, queueCount: 3, currentTime: 40, duration: 100)))
    }

    @Test func test_notTheLastTrack_isNeverFinished() {
        #expect(!(SessionCodec.isFinishedAtEndOfQueue(currentIndex: 0, queueCount: 3, currentTime: 99.9, duration: 100)), "Finishing a middle track must still save the session so the queue resumes.")
    }

    @Test func test_unknownDuration_isNotFinished() {
        #expect(!(SessionCodec.isFinishedAtEndOfQueue(currentIndex: 0, queueCount: 1, currentTime: 0, duration: 0)), "duration == 0 means not loaded yet, not 'finished'.")
    }

    @Test func test_exactlyOneSecondFromTheEnd_isNotFinished() {
        #expect(!(SessionCodec.isFinishedAtEndOfQueue(currentIndex: 0, queueCount: 1, currentTime: 99, duration: 100)))
    }

    // MARK: - SessionCodec: the persisted shape

    @Test func test_session_storesPathsNotURLs() {
        let session = SessionCodec.session(trackURL: url("/Docs/Podcasts/Ep1.mp3"),
            currentTime: 42,
            queueURLs: [url("/Docs/Podcasts/Ep1.mp3"), url("/Docs/Podcasts/Ep2.mp3")],
            playlistSource: .folder(url("/Docs/Podcasts")))

        #expect(session.fileURL == "/Docs/Podcasts/Ep1.mp3")
        #expect(session.currentTime == 42)
        #expect(session.queue.map(\.fileURL) == ["/Docs/Podcasts/Ep1.mp3", "/Docs/Podcasts/Ep2.mp3"])
        #expect(session.playlistSource == .folder(url("/Docs/Podcasts")))
    }

    @Test func test_emptySession_reportsItself() {
        #expect(PlaybackSession().isEmpty)
        #expect(!(PlaybackSession(fileURL: "/a.mp3").isEmpty))
    }

    /// Guards the on-disk format against accidental change: a saved session must still decode.
    @Test func test_session_roundTripsThroughJSON() throws {
        let original = SessionCodec.session(trackURL: url("/Docs/A.mp3"), currentTime: 12.5,
            queueURLs: [url("/Docs/A.mp3")], playlistSource: .singleFile)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(PlaybackSession.self, from: data) == original)
    }

    // MARK: - SessionRestorePolicy

    @Test func test_backoffIs500msDoublingThreeTimes() {
        #expect(SessionRestorePolicy.delayMilliseconds(forAttempt: 0) == 500)
        #expect(SessionRestorePolicy.delayMilliseconds(forAttempt: 1) == 1000)
        #expect(SessionRestorePolicy.delayMilliseconds(forAttempt: 2) == 2000)
    }

    @Test func test_afterTheThirdAttempt_thereIsNoDelayBecauseThereIsNoRetry() {
        #expect(!(SessionRestorePolicy.shouldRetry(attemptNumber: 3)))
        #expect(SessionRestorePolicy.delayMilliseconds(forAttempt: 3) == nil)
    }

    @Test func test_retriesAllowedForTheFirstThreeAttempts() {
        #expect(SessionRestorePolicy.shouldRetry(attemptNumber: 0))
        #expect(SessionRestorePolicy.shouldRetry(attemptNumber: 2))
    }

    // MARK: - RecordingFilename

    @Test func test_filenameFormat() {
        let date = Date(timeIntervalSince1970: 1_770_386_097)  // 2026-02-06 established below
        let name = RecordingFilename.make(at: date, timeZone: TimeZone(secondsFromGMT: 0)!, locale: Locale(identifier: "en_US_POSIX"))
        #expect(name.hasPrefix("Recording "), "\(name)")
        #expect(name.hasSuffix(".m4a"), "\(name)")
    }

    @Test func test_filenameUsesDotsNotColons() {
        let name = RecordingFilename.make(at: Date(), timeZone: TimeZone(secondsFromGMT: 0)!, locale: Locale(identifier: "en_US_POSIX"))
        #expect(!(name.contains(":")), "Colons display as '/' in Finder: \(name)")
    }

    @Test func test_filenameIsStableForTheSameInstant() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let tz = TimeZone(secondsFromGMT: 0)!
        let posix = Locale(identifier: "en_US_POSIX")
        #expect(RecordingFilename.make(at: date, timeZone: tz, locale: posix) == RecordingFilename.make(at: date, timeZone: tz, locale: posix))
    }

    @Test func test_filenameIsExactForAKnownInstant() {
        // 2001-09-09 01:46:40 UTC
        let date = Date(timeIntervalSince1970: 1_000_000_000)
        #expect(RecordingFilename.make(at: date, timeZone: TimeZone(secondsFromGMT: 0)!, locale: Locale(identifier: "en_US_POSIX")) == "Recording 2001-09-09 01.46.40.m4a")
    }

    // MARK: - RecordingFilename does not follow the device (#23)

    private static let utc = TimeZone(secondsFromGMT: 0)!
    /// 2026-02-06 14:14:57 UTC
    private static let afternoon = Date(timeIntervalSince1970: 1_770_387_297)
    /// 2026-02-06 02:14:57 UTC — the same clock face under a 12-hour formatter.
    private static let morning = Date(timeIntervalSince1970: 1_770_344_097)

    @Test func test_defaultLocale_isPOSIXRatherThanTheDeviceLocale() {
        #expect(
            RecordingFilename.make(at: Self.afternoon, timeZone: Self.utc)
                == RecordingFilename.make(at: Self.afternoon, timeZone: Self.utc, locale: Locale(identifier: "en_US_POSIX"))
        )
    }

    @Test func test_defaultCalendar_isGregorianRatherThanTheDeviceCalendar() {
        #expect(
            RecordingFilename.make(at: Self.afternoon, timeZone: Self.utc)
                == RecordingFilename.make(at: Self.afternoon, calendar: Calendar(identifier: .gregorian), timeZone: Self.utc)
        )
    }

    /// The headline of #23: whatever the device is set to, the name is ASCII.
    @Test func test_digitsAreAlwaysASCII() {
        let name = RecordingFilename.make(at: Self.afternoon, timeZone: Self.utc)
        #expect(name.allSatisfy { !$0.isNumber || $0.isASCII }, "\(name)")
    }

    /// `HH` must mean 24-hour regardless of the user's 24-Hour Time setting — the QA1480 trap.
    @Test func test_hourIsTwentyFourHour() {
        #expect(RecordingFilename.make(at: Self.afternoon, timeZone: Self.utc) == "Recording 2026-02-06 14.14.57.m4a")
    }

    /// The regression this fix exists to prevent: two takes an hour-hand apart used to collide on
    /// one name and be silently deduped to "... 2.m4a", reading as a duplicate of the first.
    @Test func test_morningAndAfternoonTakesDoNotCollide() {
        let a = RecordingFilename.make(at: Self.morning, timeZone: Self.utc)
        let b = RecordingFilename.make(at: Self.afternoon, timeZone: Self.utc)
        #expect(a == "Recording 2026-02-06 02.14.57.m4a", "\(a)")
        #expect(b == "Recording 2026-02-06 14.14.57.m4a", "\(b)")
        #expect(a != b)
    }

    /// The defaults changed; the seams did not. A caller that genuinely wants a device-shaped
    /// name can still ask for one.
    @Test func test_anExplicitCalendarIsStillHonoured() {
        let hijri = RecordingFilename.make(
            at: Self.afternoon,
            calendar: Calendar(identifier: .islamicUmmAlQura),
            timeZone: Self.utc
        )
        #expect(!hijri.hasPrefix("Recording 2026-"), "\(hijri)")
    }
}
