import Foundation
import Testing

@testable import SonicPlayer

/// One answer to "how tall is this bar", shared by the dial's scrolling waveform and the recorder's
/// own (#75).
@Suite
struct MeterLevelTests {

    private let tolerance = 1e-9

    @Test func fullScaleIsFull() {
        #expect(abs(MeterLevel.fraction(ofPeak: 0) - 1) < tolerance)
    }

    @Test func theFloorIsSilence() {
        #expect(MeterLevel.fraction(ofPeak: MeterLevel.floor) == 0)
    }

    /// `AVAudioRecorder` reports down to −160 dBFS. Mapping that range linearly is what this type
    /// exists to avoid, but the far end still has to answer.
    @Test func belowTheFloorIsStillSilenceRatherThanNegative() {
        #expect(MeterLevel.fraction(ofPeak: -160) == 0)
    }

    @Test func halfwayToTheFloorIsHalfHeight() {
        #expect(abs(MeterLevel.fraction(ofPeak: MeterLevel.floor / 2) - 0.5) < tolerance)
    }

    /// The reading that made the floor worth choosing: ordinary speech has to be legible as a
    /// waveform, not pinned at the top of the bar.
    @Test func ordinarySpeechSitsWellInsideTheRange() {
        let speech = MeterLevel.fraction(ofPeak: -15)

        #expect(speech > 0.6)
        #expect(speech < 0.8)
    }

    @Test func aReadingAboveFullScaleIsClamped() {
        #expect(MeterLevel.fraction(ofPeak: 12) == 1)
    }
}
