import AVFoundation
import MediaPlayer
import UIKit

/// The device's media volume — the one the hardware buttons move (#6).
///
/// **This replaced a per-player gain, and the difference is the whole point.** `AVPlayer.volume` is
/// this app's own attenuation: turning it down makes the app quieter while the device's level, its
/// on-screen slider and the hardware buttons all sit untouched. That is a defensible control in
/// isolation and a confusing one in practice, because it produces two volumes that disagree —
/// press the buttons and the dial's arc does not move; turn the dial and the system slider does
/// not. A volume control on a media player is expected to mean the volume.
///
/// Reading is straightforward and fully documented: `AVAudioSession.outputVolume`, which is
/// key-value observable, so the hardware buttons push their changes here and the dial follows.
///
/// **Writing has no public setter, and this is the honest note about that.** There is no
/// `AVAudioSession.setOutputVolume`. The only way to move the system level from inside an app is
/// `MPVolumeView`'s embedded `UISlider` — a public class whose subview layout is not documented.
/// It is not private API and it is very widely shipped, but it is an implementation detail of a
/// UIKit control, so it can break in an OS release. `setLevel` degrades to doing nothing rather
/// than trapping if the slider is ever absent, and `level` keeps reporting the truth from
/// `outputVolume` either way — so the failure mode is "the dial stops moving volume", not a crash
/// and not a lie on screen.
///
/// The `MPVolumeView` here is also the one UIKit view in an app whose convention is SwiftUI-only.
/// It is never rendered: one point across, parked far off-screen, and present only because the
/// slider does not exist until the view does. A client wrapping a system framework is exactly where
/// that belongs — the same place `AVAudioSession` and `AVPlayer` already live.
struct SystemVolumeClient: Sendable {

    /// The current device media volume, `0...1`.
    var level: @MainActor @Sendable () -> Double = { 1 }

    /// Moves the device media volume. Silently does nothing if the slider cannot be found.
    var setLevel: @MainActor @Sendable (Double) -> Void = { _ in }

    /// Every change to the device volume, including the ones this app did not make — which is what
    /// makes the hardware buttons move the dial's arc.
    var changes: @Sendable () -> AsyncStream<Double> = { AsyncStream { $0.finish() } }
}

extension SystemVolumeClient {

    static let live = SystemVolumeClient(
        level: { Double(AVAudioSession.sharedInstance().outputVolume) },
        setLevel: { SystemVolumeBox.shared.set(Double($0)) },
        changes: {
            AsyncStream { continuation in
                let observation = AVAudioSession.sharedInstance().observe(
                    \.outputVolume, options: [.new]
                ) { _, change in
                    guard let value = change.newValue else { return }
                    continuation.yield(Double(value))
                }
                continuation.onTermination = { _ in observation.invalidate() }
            }
        }
    )

    /// Reports a fixed level and swallows writes. Volume is global device state, so a test that
    /// really moved it would change the machine it runs on.
    static let test = SystemVolumeClient(
        level: { 1 },
        setLevel: { _ in },
        changes: { AsyncStream { $0.finish() } }
    )
}

/// Owns the off-screen `MPVolumeView`, because the slider only exists once the view does.
///
/// A singleton for the same reason `AudioPlayerManager` is one: there is one device volume, and a
/// second view fighting over it would be a second opinion about a single global.
@MainActor
private final class SystemVolumeBox {

    static let shared = SystemVolumeBox()

    private let volumeView = MPVolumeView(
        frame: CGRect(x: -offscreen, y: -offscreen, width: 1, height: 1)
    )

    private init() {
        // Attached, but never seen. The slider ignores writes while its view is outside the
        // hierarchy, so parking it off-screen is not decoration — it is what makes `set` work at
        // all. `isHidden` would defeat it for the same reason.
        volumeView.alpha = 0.001
        volumeView.isUserInteractionEnabled = false
        keyWindow?.addSubview(volumeView)
    }

    func set(_ level: Double) {
        guard let slider else { return }
        // On the next runloop pass: setting `value` during the same turn as a gesture or a KVO
        // callback is the documented way to have UIKit quietly discard it.
        let clamped = Float(min(max(0, level), 1))
        DispatchQueue.main.async { slider.value = clamped }
    }

    private var slider: UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    /// Far enough out that no screen or rotation brings it back.
    private static let offscreen: CGFloat = 4000
}
