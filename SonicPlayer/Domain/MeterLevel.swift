import Foundation

/// What a peak-power reading looks like as a bar (#75).
///
/// `AVAudioRecorder.peakPower(forChannel:)` reports decibels full scale, `-160` to `0`. Mapping
/// that range linearly is useless: ordinary speech sits around `-15`, which lands at 91% of full
/// height, so every bar is nearly full and the waveform carries no information at all.
///
/// **The floor is inherited, not derived.** `-50` is the number `RecordingWaveformView` has been
/// drawing with since the recorder shipped, and it reads correctly on a device — this type exists
/// so the dial's scrolling waveform and that view give the same answer to the same question, rather
/// than each carrying its own copy of the arithmetic. Re-tuning it is a device measurement, and the
/// point of having one constant is that such a measurement moves both consumers at once.
enum MeterLevel {

    /// Quieter than this is silence, as far as a bar is concerned.
    static let floor: Float = -50

    /// `0...1`, clamped. Anything at or below `floor` is 0; `0 dBFS` is 1.
    static func fraction(ofPeak decibels: Float) -> Double {
        let normalised = (decibels - floor) / -floor
        return Double(min(max(0, normalised), 1))
    }
}
