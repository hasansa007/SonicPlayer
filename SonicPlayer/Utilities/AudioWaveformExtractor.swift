import AVFoundation
import Foundation

enum AudioWaveformExtractor {
    /// Extract normalized amplitude samples (0...1) from an audio file.
    /// Returns `sampleCount` evenly-spaced peak amplitudes.
    static func extract(url: URL, sampleCount: Int = 60) async -> [Float] {
        await Task.detached(priority: .userInitiated) {
            guard let file = try? AVAudioFile(forReading: url) else {
                return Self.fallback(count: sampleCount)
            }
            let format = file.processingFormat
            let totalFrames = AVAudioFrameCount(file.length)
            guard totalFrames > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
                return Self.fallback(count: sampleCount)
            }
            do {
                try file.read(into: buffer)
            } catch {
                return Self.fallback(count: sampleCount)
            }

            guard let channelData = buffer.floatChannelData else {
                return Self.fallback(count: sampleCount)
            }

            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            guard frameCount > 0, channelCount > 0 else {
                return Self.fallback(count: sampleCount)
            }

            // Bucket samples into `sampleCount` peak amplitudes
            let samplesPerBucket = max(frameCount / sampleCount, 1)
            var peaks: [Float] = Array(repeating: 0, count: sampleCount)

            for bucketIndex in 0..<sampleCount {
                let start = bucketIndex * samplesPerBucket
                let end = min(start + samplesPerBucket, frameCount)
                guard start < end else { break }
                var peak: Float = 0
                for frame in start..<end {
                    var maxAmplitude: Float = 0
                    for ch in 0..<channelCount {
                        let sample = abs(channelData[ch][frame])
                        if sample > maxAmplitude { maxAmplitude = sample }
                    }
                    if maxAmplitude > peak { peak = maxAmplitude }
                }
                peaks[bucketIndex] = peak
            }

            // Normalize to 0...1
            let maxPeak = peaks.max() ?? 1
            if maxPeak > 0 {
                peaks = peaks.map { $0 / maxPeak }
            }
            return peaks
        }.value
    }

    private static func fallback(count: Int) -> [Float] {
        (0..<count).map { _ in Float.random(in: 0.2...0.8) }
    }
}
