import Foundation
import Testing

@testable import SonicPlayer

/// Characterization tests for the audio editor's scrub clamps, previously inlined one half at a
/// time in `RecordingFeature.skipForward` / `.skipBackward`. No TCA, no AVFoundation — these
/// must survive the migration of the recording feature (#17) unchanged.
@Suite
struct ScrubClampTests {

    @Test func test_interval_isFifteenSeconds() {
        #expect(ScrubClamp.interval == 15)
    }

    // MARK: - Forward

    @Test func test_forward_advancesByTheInterval() {
        #expect(ScrubClamp.forward(from: 0, duration: 100) == 15)
    }

    @Test func test_forward_stopsAtTheEnd() {
        #expect(ScrubClamp.forward(from: 90, duration: 100) == 100)
    }

    @Test func test_forward_atTheEnd_staysThere() {
        #expect(ScrubClamp.forward(from: 100, duration: 100) == 100)
    }

    /// A recording shorter than one step clamps to its own duration rather than overshooting.
    @Test func test_forward_inARecordingShorterThanOneStep_clampsToDuration() {
        #expect(ScrubClamp.forward(from: 0, duration: 5) == 5)
    }

    /// `AVPlayer` can report a position past the reported duration. The clamp is `min`, so from
    /// there "forward" moves the position *backwards* to the end. Pinned deliberately: it is the
    /// pre-existing behaviour, not a decision made during the extraction.
    @Test func test_forward_fromPastTheEnd_movesBackToTheEnd() {
        #expect(ScrubClamp.forward(from: 120, duration: 100) == 100)
    }

    /// Duration is zero before the asset loads; the clamp collapses everything to zero.
    @Test func test_forward_withNoDurationYet_yieldsZero() {
        #expect(ScrubClamp.forward(from: 0, duration: 0) == 0)
    }

    // MARK: - Backward

    @Test func test_backward_rewindsByTheInterval() {
        #expect(ScrubClamp.backward(from: 100) == 85)
    }

    @Test func test_backward_stopsAtZero() {
        #expect(ScrubClamp.backward(from: 10) == 0)
    }

    @Test func test_backward_atZero_staysThere() {
        #expect(ScrubClamp.backward(from: 0) == 0)
    }

    /// Backward takes no duration, so a position past the end rewinds by a full interval from
    /// wherever it actually is rather than from the end.
    @Test func test_backward_fromPastTheEnd_isNotBoundedByDuration() {
        #expect(ScrubClamp.backward(from: 120) == 105)
    }
}
