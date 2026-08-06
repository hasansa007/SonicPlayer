import Foundation
import Testing

@testable import SonicPlayer

/// Characterization tests for queue sequencing, lifted from PlayerFeature's reducer.
/// No TCA — these outlive the migration.
@Suite
struct QueueMathTests {

    private func file(_ name: String) -> AudioFile {
        AudioFile(url: URL(fileURLWithPath: "/Docs/\(name).mp3"),
            title: name,
            duration: 100,
            fileSize: 1,
            format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0))
    }

    // MARK: - End of track

    @Test func test_stillPlaying_returnsNilSoTheTickFallsThrough() {
        #expect(QueueMath.decideOnTrackEnd(isPlaying: true, duration: 100, currentTime: 40, repeatMode: .off, hasNextTrack: true, queueIsEmpty: false) == nil)
    }

    @Test func test_pausedAtTheEnd_doesNotTrigger() {
        #expect(QueueMath.decideOnTrackEnd(isPlaying: false, duration: 100, currentTime: 99.5, repeatMode: .off, hasNextTrack: true, queueIsEmpty: false) == nil)
    }

    @Test func test_unknownDuration_doesNotTrigger() {
        #expect(QueueMath.decideOnTrackEnd(isPlaying: true, duration: 0, currentTime: 0, repeatMode: .off, hasNextTrack: true, queueIsEmpty: false) == nil)
    }

    @Test func test_repeatOne_winsOverHavingANextTrack() {
        #expect(QueueMath.decideOnTrackEnd(isPlaying: true, duration: 100, currentTime: 99.5, repeatMode: .one, hasNextTrack: true, queueIsEmpty: false) == .repeatCurrent)
    }

    @Test func test_withANextTrack_advances() {
        #expect(QueueMath.decideOnTrackEnd(isPlaying: true, duration: 100, currentTime: 99.5, repeatMode: .off, hasNextTrack: true, queueIsEmpty: false) == .advance)
    }

    @Test func test_lastTrackWithRepeatAll_wrapsToStart() {
        #expect(QueueMath.decideOnTrackEnd(isPlaying: true, duration: 100, currentTime: 99.5, repeatMode: .all, hasNextTrack: false, queueIsEmpty: false) == .wrapToStart)
    }

    @Test func test_lastTrackWithRepeatAllButEmptyQueue_stops() {
        #expect(QueueMath.decideOnTrackEnd(isPlaying: true, duration: 100, currentTime: 99.5, repeatMode: .all, hasNextTrack: false, queueIsEmpty: true) == .stop)
    }

    @Test func test_lastTrackNoRepeat_stops() {
        #expect(QueueMath.decideOnTrackEnd(isPlaying: true, duration: 100, currentTime: 99.5, repeatMode: .off, hasNextTrack: false, queueIsEmpty: false) == .stop)
    }

    /// The boundary is strictly "less than one second remaining".
    @Test func test_exactlyOneSecondRemaining_doesNotTrigger() {
        #expect(QueueMath.decideOnTrackEnd(isPlaying: true, duration: 100, currentTime: 99, repeatMode: .off, hasNextTrack: true, queueIsEmpty: false) == nil)
    }

    // MARK: - Previous

    @Test func test_pastThreeSeconds_restartsInsteadOfSteppingBack() {
        #expect(QueueMath.decideOnPrevious(currentTime: 3.1, hasPreviousTrack: true, currentIndex: 4) == .restart)
    }

    @Test func test_withinThreeSeconds_stepsBack() {
        #expect(QueueMath.decideOnPrevious(currentTime: 2.9, hasPreviousTrack: true, currentIndex: 4) == .previous(index: 3))
    }

    @Test func test_onTheFirstTrack_restarts() {
        #expect(QueueMath.decideOnPrevious(currentTime: 0.5, hasPreviousTrack: false, currentIndex: 0) == .restart)
    }

    @Test func test_exactlyThreeSeconds_stepsBack() {
        #expect(QueueMath.decideOnPrevious(currentTime: 3, hasPreviousTrack: true, currentIndex: 1) == .previous(index: 0))
    }

    // MARK: - Repeat mode

    @Test func test_repeatModeCyclesOffAllOneOff() {
        #expect(QueueMath.nextRepeatMode(after: .off) == .all)
        #expect(QueueMath.nextRepeatMode(after: .all) == .one)
        #expect(QueueMath.nextRepeatMode(after: .one) == .off)
    }

    // MARK: - Shuffle

    @Test func test_shuffle_pinsTheCurrentTrackToTheFront() {
        let a = file("A"), b = file("B"), c = file("C")
        let result = QueueMath.shuffling([a, b, c], keeping: b, shuffle: { $0.reversed() })
        #expect(result?.queue == [b, c, a])
        #expect(result?.currentIndex == 0)
    }

    @Test func test_shuffle_keepsEveryTrackExactlyOnce() {
        let all = [file("A"), file("B"), file("C"), file("D")]
        let result = QueueMath.shuffling(all, keeping: all[2], shuffle: { $0 })
        #expect(Set(result?.queue ?? []) == Set(all))
        #expect(result?.queue.count == all.count)
    }

    @Test func test_shuffle_withNoCurrentTrack_doesNothing() {
        #expect(QueueMath.shuffling([file("A")], keeping: nil, shuffle: { $0 }) == nil)
    }
}
