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
            throw NSError(domain: "AudioRecorderClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to start recording"])
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
}
