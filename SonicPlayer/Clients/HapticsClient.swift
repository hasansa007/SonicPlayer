import CoreHaptics
import Foundation
import UIKit

/// The wheel's haptics (#6). A struct of closures with a `.live`, like the other five.
///
/// No new dependency — CoreHaptics ships with iOS. `.test` lives in the test target, which is where
/// every `.test` has lived since #20.
/// **The closures are `@MainActor`, and that is load-bearing.** `UIImpactFeedbackGenerator` is
/// main-actor isolated, so the fallback path reaches it through `MainActor.assumeIsolated` — which
/// does not check and fall back, it *traps*. As plain `@Sendable` closures the type invited calls
/// from anywhere and the assumption was enforced only by a comment. Typed this way the compiler
/// rejects an off-main call site outright, so the assertion is checked rather than believed.
///
/// It also keeps the pulse synchronous. Hopping to the main actor would make every detent arrive a
/// hop late, and a haptic that lands after the thumb has moved on reads as the wheel clicking at
/// the wrong moment.
struct HapticsClient {
    /// Called before the first pulse. Starting the engine lazily on the first detent costs a
    /// perceptible delay on exactly the pulse the user judges the whole feature by.
    var prepare: @MainActor @Sendable () -> Void = {}
    var fire: @MainActor @Sendable (DetentFeedback.Pulse) -> Void = { _ in }
    var stop: @MainActor @Sendable () -> Void = {}
}

extension HapticsClient {

    static let live: HapticsClient = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            // iPad, the simulator, and older phones. `UIImpactFeedbackGenerator` is a coarser
            // instrument — one fixed pulse shape, intensity only — but silence would make the
            // wheel feel broken rather than plain.
            let impact = ImpactBox()
            return Self(
                prepare: { impact.prepare() },
                fire: { pulse in impact.fire(intensity: pulse.intensity) },
                stop: {}
            )
        }

        let engine = HapticEngineBox()
        return Self(
            prepare: { engine.start() },
            fire: { pulse in engine.fire(pulse) },
            stop: { engine.stop() }
        )
    }()
}

/// The coarse fallback generator, boxed for the same reason `HapticEngineBox` is.
///
/// **`UIImpactFeedbackGenerator` is `@MainActor`-isolated and the client's closures are `@Sendable`
/// and nonisolated**, so calling it directly warns — and would eventually be an error.
///
/// `assumeIsolated` rather than a `Task { @MainActor in … }` hop, and it is safe because
/// `HapticsClient`'s closures are `@MainActor` — the compiler will not let anything call in from
/// off the main actor, so the assertion cannot be wrong. A hop would cost every detent a frame,
/// and a pulse that lands after the thumb has moved on is worse than none.
private final class ImpactBox: @unchecked Sendable {

    private let generator = UIImpactFeedbackGenerator(style: .rigid)

    func prepare() {
        MainActor.assumeIsolated { generator.prepare() }
    }

    func fire(intensity: Double) {
        MainActor.assumeIsolated { generator.impactOccurred(intensity: intensity) }
    }
}

/// Holds the engine and the two lifecycle facts that make CoreHaptics awkward in practice: it stops
/// when the app backgrounds, and it resets if the media server restarts. Both leave a handle that
/// looks fine and plays nothing, so both are handled rather than hoped about.
private final class HapticEngineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: CHHapticEngine?

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard engine == nil else { return }
        do {
            let created = try CHHapticEngine()
            created.stoppedHandler = { [weak self] _ in self?.clear() }
            created.resetHandler = { [weak self] in self?.restart() }
            try created.start()
            engine = created
        } catch {
            // A wheel that does not buzz is worse than one that does; a wheel that crashes is worse
            // than both. There is nothing the user can do about an engine that will not start.
            engine = nil
        }
    }

    func fire(_ pulse: DetentFeedback.Pulse) {
        lock.lock()
        var current = engine
        lock.unlock()

        // **Start on demand, not only at init.** `stoppedHandler` nils the engine, and CoreHaptics
        // stops for reasons that are entirely normal — the audio session going active for playback
        // is one of them. Starting once at launch therefore meant the first track silenced every
        // pulse for the rest of the session, and it failed the way this whole codebase keeps
        // failing: silently, with no error anywhere.
        if current == nil {
            start()
            lock.lock()
            current = engine
            lock.unlock()
        }
        guard let current else { return }

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(pulse.intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(pulse.sharpness))
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try current.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            // Same reasoning as `start`.
        }
    }

    func stop() {
        lock.lock()
        let current = engine
        engine = nil
        lock.unlock()
        current?.stop()
    }

    private func clear() {
        lock.lock()
        engine = nil
        lock.unlock()
    }

    private func restart() {
        lock.lock()
        let current = engine
        lock.unlock()
        try? current?.start()
    }
}
