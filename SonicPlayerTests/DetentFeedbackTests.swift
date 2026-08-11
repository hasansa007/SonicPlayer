import Foundation
import Testing

@testable import SonicPlayer

/// The haptic design, asserted without a device that can vibrate.
@Suite
struct DetentFeedbackTests {

    @Test func anOrdinaryDetentIsALightTick() {
        let pulse = DetentFeedback.pulse(for: .detent)

        #expect(pulse.intensity == 0.5)
        #expect(pulse.sharpness == 0.8)
    }

    /// Hitting the start or end of a track must feel different from turning through it, or you
    /// keep turning against a wall you cannot see.
    @Test func reachingALimitIsHeavierAndDuller() {
        let limit = DetentFeedback.pulse(for: .limit)
        let detent = DetentFeedback.pulse(for: .detent)

        #expect(limit.intensity > detent.intensity)
        #expect(limit.sharpness < detent.sharpness)
    }

    @Test func committingIsTheStrongestOfTheThree() {
        let commit = DetentFeedback.pulse(for: .commit)

        #expect(commit.intensity == 1.0)
    }

    @Test func everyPulseIsInsideCoreHapticsRange() {
        for event in DetentFeedback.Event.allCases {
            let pulse = DetentFeedback.pulse(for: event)
            #expect((0...1).contains(pulse.intensity), "\(event) intensity out of range")
            #expect((0...1).contains(pulse.sharpness), "\(event) sharpness out of range")
        }
    }
}
