import XCTest

@testable import SonicPlayer

/// Characterization tests for queue sequencing, lifted from PlayerFeature's reducer.
/// No TCA — these outlive the migration.
final class QueueMathTests: XCTestCase {

    private func file(_ name: String) -> AudioFile {
        AudioFile(
            url: URL(fileURLWithPath: "/Docs/\(name).mp3"),
            title: name,
            duration: 100,
            fileSize: 1,
            format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - End of track

    func test_stillPlaying_returnsNilSoTheTickFallsThrough() {
        XCTAssertNil(
            QueueMath.decideOnTrackEnd(
                isPlaying: true, duration: 100, currentTime: 40,
                repeatMode: .off, hasNextTrack: true, queueIsEmpty: false
            )
        )
    }

    func test_pausedAtTheEnd_doesNotTrigger() {
        XCTAssertNil(
            QueueMath.decideOnTrackEnd(
                isPlaying: false, duration: 100, currentTime: 99.5,
                repeatMode: .off, hasNextTrack: true, queueIsEmpty: false
            )
        )
    }

    func test_unknownDuration_doesNotTrigger() {
        XCTAssertNil(
            QueueMath.decideOnTrackEnd(
                isPlaying: true, duration: 0, currentTime: 0,
                repeatMode: .off, hasNextTrack: true, queueIsEmpty: false
            )
        )
    }

    func test_repeatOne_winsOverHavingANextTrack() {
        XCTAssertEqual(
            QueueMath.decideOnTrackEnd(
                isPlaying: true, duration: 100, currentTime: 99.5,
                repeatMode: .one, hasNextTrack: true, queueIsEmpty: false
            ),
            .repeatCurrent
        )
    }

    func test_withANextTrack_advances() {
        XCTAssertEqual(
            QueueMath.decideOnTrackEnd(
                isPlaying: true, duration: 100, currentTime: 99.5,
                repeatMode: .off, hasNextTrack: true, queueIsEmpty: false
            ),
            .advance
        )
    }

    func test_lastTrackWithRepeatAll_wrapsToStart() {
        XCTAssertEqual(
            QueueMath.decideOnTrackEnd(
                isPlaying: true, duration: 100, currentTime: 99.5,
                repeatMode: .all, hasNextTrack: false, queueIsEmpty: false
            ),
            .wrapToStart
        )
    }

    func test_lastTrackWithRepeatAllButEmptyQueue_stops() {
        XCTAssertEqual(
            QueueMath.decideOnTrackEnd(
                isPlaying: true, duration: 100, currentTime: 99.5,
                repeatMode: .all, hasNextTrack: false, queueIsEmpty: true
            ),
            .stop
        )
    }

    func test_lastTrackNoRepeat_stops() {
        XCTAssertEqual(
            QueueMath.decideOnTrackEnd(
                isPlaying: true, duration: 100, currentTime: 99.5,
                repeatMode: .off, hasNextTrack: false, queueIsEmpty: false
            ),
            .stop
        )
    }

    /// The boundary is strictly "less than one second remaining".
    func test_exactlyOneSecondRemaining_doesNotTrigger() {
        XCTAssertNil(
            QueueMath.decideOnTrackEnd(
                isPlaying: true, duration: 100, currentTime: 99,
                repeatMode: .off, hasNextTrack: true, queueIsEmpty: false
            )
        )
    }

    // MARK: - Previous

    func test_pastThreeSeconds_restartsInsteadOfSteppingBack() {
        XCTAssertEqual(
            QueueMath.decideOnPrevious(currentTime: 3.1, hasPreviousTrack: true, currentIndex: 4),
            .restart
        )
    }

    func test_withinThreeSeconds_stepsBack() {
        XCTAssertEqual(
            QueueMath.decideOnPrevious(currentTime: 2.9, hasPreviousTrack: true, currentIndex: 4),
            .previous(index: 3)
        )
    }

    func test_onTheFirstTrack_restarts() {
        XCTAssertEqual(
            QueueMath.decideOnPrevious(currentTime: 0.5, hasPreviousTrack: false, currentIndex: 0),
            .restart
        )
    }

    func test_exactlyThreeSeconds_stepsBack() {
        XCTAssertEqual(
            QueueMath.decideOnPrevious(currentTime: 3, hasPreviousTrack: true, currentIndex: 1),
            .previous(index: 0)
        )
    }

    // MARK: - Repeat mode

    func test_repeatModeCyclesOffAllOneOff() {
        XCTAssertEqual(QueueMath.nextRepeatMode(after: .off), .all)
        XCTAssertEqual(QueueMath.nextRepeatMode(after: .all), .one)
        XCTAssertEqual(QueueMath.nextRepeatMode(after: .one), .off)
    }

    // MARK: - Shuffle

    func test_shuffle_pinsTheCurrentTrackToTheFront() {
        let a = file("A"), b = file("B"), c = file("C")
        let result = QueueMath.shuffling([a, b, c], keeping: b, shuffle: { $0.reversed() })
        XCTAssertEqual(result?.queue, [b, c, a])
        XCTAssertEqual(result?.currentIndex, 0)
    }

    func test_shuffle_keepsEveryTrackExactlyOnce() {
        let all = [file("A"), file("B"), file("C"), file("D")]
        let result = QueueMath.shuffling(all, keeping: all[2], shuffle: { $0 })
        XCTAssertEqual(Set(result?.queue ?? []), Set(all))
        XCTAssertEqual(result?.queue.count, all.count)
    }

    func test_shuffle_withNoCurrentTrack_doesNothing() {
        XCTAssertNil(QueueMath.shuffling([file("A")], keeping: nil, shuffle: { $0 }))
    }
}
