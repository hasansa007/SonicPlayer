import AVFoundation
import Foundation

struct AudioRecorderClient {
    let checkPermissions: @Sendable () async -> Bool
    let requestPermissions: @Sendable () async -> Bool
    let startRecording: @Sendable (URL) async throws -> Void
    let stopRecording: @Sendable () async throws -> URL?
    let currentTime: @Sendable () async -> TimeInterval
    let peakPower: @Sendable () async -> Float
    let isRecording: @Sendable () async -> Bool
    let pauseRecording: @Sendable () async -> Void
    /// Whether the recorder took the file back. `AVAudioRecorder.record()` reports this, and a
    /// resume that silently failed would leave a running clock over a dead file.
    let resumeRecording: @Sendable () async -> Bool
    /// Whether this hardware has an input gain to set at all — false on most built-in iPhone mics,
    /// true for a fair number of USB and Lightning interfaces.
    ///
    /// Reported rather than assumed because the dial refuses the gain axis when the answer is no
    /// (#75). A wheel that turns freely against hardware with no gain is exactly the control that
    /// appears to work and does not.
    let isInputGainSettable: @Sendable () async -> Bool
    /// The gain the session is currently on, `0...1`. Read rather than assumed: it is a *system*
    /// setting, so another app may have moved it since this one last looked.
    let inputGain: @Sendable () async -> Float
    /// `0...1`, clamped. Returns whether it took.
    let setInputGain: @Sendable (Float) async -> Bool
}

extension AudioRecorderClient {
    static let live: AudioRecorderClient = {
        let recorder = RecorderActor()

        return Self(
            checkPermissions: {
                if #available(iOS 17.0, *) {
                    return AVAudioApplication.shared.recordPermission == .granted
                } else {
                    return AVAudioSession.sharedInstance().recordPermission == .granted
                }
            },
            requestPermissions: {
                if #available(iOS 17.0, *) {
                    return await withCheckedContinuation { continuation in
                        AVAudioApplication.requestRecordPermission { granted in
                            continuation.resume(returning: granted)
                        }
                    }
                } else {
                    return await withCheckedContinuation { continuation in
                        AVAudioSession.sharedInstance().requestRecordPermission { granted in
                            continuation.resume(returning: granted)
                        }
                    }
                }
            },
            startRecording: { url in
                try await recorder.startRecording(url: url)
            },
            stopRecording: {
                try await recorder.stopRecording()
            },
            currentTime: {
                await recorder.currentTime()
            },
            peakPower: {
                await recorder.peakPower()
            },
            isRecording: {
                await recorder.isRecording()
            },
            pauseRecording: {
                await recorder.pauseRecording()
            },
            resumeRecording: {
                await recorder.resumeRecording()
            },
            isInputGainSettable: {
                AVAudioSession.sharedInstance().isInputGainSettable
            },
            inputGain: {
                AVAudioSession.sharedInstance().inputGain
            },
            setInputGain: { gain in
                let session = AVAudioSession.sharedInstance()
                guard session.isInputGainSettable else { return false }
                do {
                    try session.setInputGain(min(max(0, gain), 1))
                    return true
                } catch {
                    return false
                }
            }
        )
    }()

}


// MARK: - Actor for Thread Safety

private actor RecorderActor {
    private var audioRecorder: AVAudioRecorder?

    func startRecording(url: URL) async throws {
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default)
        try audioSession.setActive(true)

        // Recording settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        // Create recorder
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw RecordingError.cannotStart
        }

        self.audioRecorder = recorder
    }

    func stopRecording() async throws -> URL? {
        guard let recorder = audioRecorder else {
            return nil
        }

        recorder.stop()

        // Deactivate audio session
        try AVAudioSession.sharedInstance().setActive(false)

        let url = recorder.url
        self.audioRecorder = nil

        return url
    }

    func currentTime() async -> TimeInterval {
        audioRecorder?.currentTime ?? 0
    }

    func peakPower() async -> Float {
        guard let recorder = audioRecorder else { return 0 }
        recorder.updateMeters()
        return recorder.peakPower(forChannel: 0)
    }

    func isRecording() async -> Bool {
        audioRecorder?.isRecording ?? false
    }

    /// Pausing keeps the file open and the session active — only `stopRecording()` closes it, which
    /// is what lets a resumed take continue into the same file rather than starting a second one.
    func pauseRecording() async {
        audioRecorder?.pause()
    }

    func resumeRecording() async -> Bool {
        audioRecorder?.record() ?? false
    }
}
