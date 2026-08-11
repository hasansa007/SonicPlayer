import Foundation
import Testing

@testable import SonicPlayer

/// Command × focus → effects, exhaustively, with nothing rendered.
@Suite
struct WheelRouterTests {

    /// Seek deltas are compared with a tolerance rather than `==`.
    ///
    /// `3 * 0.1` is `0.30000000000000004`, so asserting the exact literal tests IEEE754 rather than
    /// the routing rule. The rule is "three detents is three tenths of a second forward", and the
    /// last bit of a double is not part of it. (`2 * 0.02` and `2 * 0.1` *are* exact — multiplying
    /// by two only moves the exponent — which is why the volume case below can use `==`.)
    private func seekDelta(_ effects: [ShellEffect]) -> TimeInterval? {
        guard case .seekBy(let delta)? = effects.first else {
            Issue.record("expected a seek effect first, got \(effects)")
            return nil
        }
        return delta
    }

    @Test func turningWhileSeekingSeeksBySecondsPerDetent() {
        let effects = WheelRouter.route(.tick(3), focus: .nowPlaying(.seek))

        #expect(effects.count == 2)
        #expect(abs((seekDelta(effects) ?? .nan) - 0.3) < 1e-9)
        #expect(effects.last == .feedback(.detent))
    }

    @Test func turningBackwardsSeeksBackwards() {
        let effects = WheelRouter.route(.tick(-2), focus: .nowPlaying(.seek))

        #expect(effects.count == 2)
        #expect(abs((seekDelta(effects) ?? .nan) + 0.2) < 1e-9)
        #expect(effects.last == .feedback(.detent))
    }

    @Test func aZeroTickDoesNothingAtAll() {
        #expect(WheelRouter.route(.tick(0), focus: .nowPlaying(.seek)).isEmpty)
    }

    @Test func turningWhileOnVolumeChangesVolume() {
        let effects = WheelRouter.route(.tick(2), focus: .nowPlaying(.volume))

        #expect(effects == [.volumeBy(0.04), .feedback(.detent)])
    }

    @Test func turningWhileOnSpeedStepsThePresets() {
        let effects = WheelRouter.route(.tick(1), focus: .nowPlaying(.speed))

        #expect(effects == [.speedBy(1), .feedback(.detent)])
    }

    @Test func theHubPlaysAndPauses() {
        let effects = WheelRouter.route(.select, focus: .nowPlaying(.seek))

        #expect(effects == [.playPause, .feedback(.commit)])
    }

    @Test func transportIsIndependentOfFocus() {
        for axis in [WheelFocus.Axis.seek, .volume, .speed] {
            let effects = WheelRouter.route(.transport(.next), focus: .nowPlaying(axis))
            #expect(effects == [.nextTrack, .feedback(.commit)], "axis \(axis)")
        }
    }

    /// Slice 1 has nothing to go back to. Both must be inert rather than crash or seek.
    @Test func backAndMenuAreInertInSliceOne() {
        #expect(WheelRouter.route(.back, focus: .nowPlaying(.seek)).isEmpty)
        #expect(WheelRouter.route(.menu, focus: .nowPlaying(.seek)).isEmpty)
    }
}
