import AVFoundation
import Foundation

struct AudioTrimmerClient {
    var trimAudio: @Sendable (URL, TimeInterval, TimeInterval) async throws -> URL
    var deleteAudioRange: @Sendable (URL, TimeInterval, TimeInterval) async throws -> URL
}

extension AudioTrimmerClient {
    static let live: AudioTrimmerClient = {
        return Self(
            trimAudio: { sourceURL, startTime, endTime in
                let asset = AVURLAsset(url: sourceURL)

                // Validate times
                let assetDuration = try await asset.load(.duration).seconds
                guard startTime >= 0, endTime <= assetDuration, startTime < endTime else {
                    throw AudioTrimmerError.invalidTimeRange
                }

                // Create export session
                guard let exportSession = AVAssetExportSession(
                    asset: asset,
                    presetName: AVAssetExportPresetAppleM4A
                ) else {
                    throw AudioTrimmerError.exportSessionCreationFailed
                }

                // Generate output URL (same location, with "_trimmed" suffix)
                let outputURL = sourceURL
                    .deletingPathExtension()
                    .appendingPathExtension("trimmed.m4a")

                // Remove existing file if present
                try? FileManager.default.removeItem(at: outputURL)

                // Set time range
                let startCMTime = CMTime(seconds: startTime, preferredTimescale: 600)
                let endCMTime = CMTime(seconds: endTime, preferredTimescale: 600)
                let timeRange = CMTimeRange(start: startCMTime, end: endCMTime)
                exportSession.timeRange = timeRange

                do {
                    try await exportSession.export(to: outputURL, as: .m4a)

                    // Delete original file
                    try? FileManager.default.removeItem(at: sourceURL)

                    // Rename trimmed file to original name
                    let finalURL = sourceURL
                    try FileManager.default.moveItem(at: outputURL, to: finalURL)

                    return finalURL
                } catch is CancellationError {
                    throw AudioTrimmerError.exportCancelled
                } catch {
                    throw AudioTrimmerError.exportFailed(error)
                }
            }
            ,
            deleteAudioRange: { sourceURL, startTime, endTime in
                let asset = AVURLAsset(url: sourceURL)

                let assetDurationSeconds = try await asset.load(.duration).seconds
                guard assetDurationSeconds > 0 else {
                    throw AudioTrimmerError.invalidTimeRange
                }

                // Validate times
                guard startTime >= 0, endTime <= assetDurationSeconds, startTime < endTime else {
                    throw AudioTrimmerError.invalidTimeRange
                }

                // Ensure there is something left after deleting the range
                let remainingDuration = assetDurationSeconds - (endTime - startTime)
                guard remainingDuration > 0.05 else {
                    throw AudioTrimmerError.invalidTimeRange
                }

                // Build a composition containing everything *except* the selected range
                let composition = AVMutableComposition()
                guard
                    let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first,
                    let compositionTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                else {
                    throw AudioTrimmerError.exportSessionCreationFailed
                }

                let start = CMTime(seconds: startTime, preferredTimescale: 600)
                let end = CMTime(seconds: endTime, preferredTimescale: 600)
                let assetDuration = CMTime(seconds: assetDurationSeconds, preferredTimescale: 600)

                // Insert [0, start)
                if startTime > 0 {
                    let preRange = CMTimeRange(start: .zero, end: start)
                    try compositionTrack.insertTimeRange(preRange, of: sourceTrack, at: .zero)
                }

                // Insert (end, duration]
                if end < assetDuration {
                    let postRange = CMTimeRange(start: end, end: assetDuration)
                    let insertionPoint = composition.duration
                    try compositionTrack.insertTimeRange(postRange, of: sourceTrack, at: insertionPoint)
                }

                guard let exportSession = AVAssetExportSession(
                    asset: composition,
                    presetName: AVAssetExportPresetAppleM4A
                ) else {
                    throw AudioTrimmerError.exportSessionCreationFailed
                }

                let outputURL = sourceURL
                    .deletingPathExtension()
                    .appendingPathExtension("deleted.m4a")

                try? FileManager.default.removeItem(at: outputURL)

                do {
                    try await exportSession.export(to: outputURL, as: .m4a)

                    try? FileManager.default.removeItem(at: sourceURL)
                    let finalURL = sourceURL
                    try FileManager.default.moveItem(at: outputURL, to: finalURL)
                    return finalURL
                } catch is CancellationError {
                    throw AudioTrimmerError.exportCancelled
                } catch {
                    throw AudioTrimmerError.exportFailed(error)
                }
            }
        )
    }()

}


enum AudioTrimmerError: Error, LocalizedError {
    case invalidTimeRange
    case exportSessionCreationFailed
    case exportFailed(Error)
    case exportCancelled
    case unknownError

    var errorDescription: String? {
        switch self {
        case .invalidTimeRange:
            return "Invalid time range for trimming"
        case .exportSessionCreationFailed:
            return "Failed to create export session"
        case .exportFailed(let error):
            return "Export failed: \(error.localizedDescription)"
        case .exportCancelled:
            return "Export was cancelled"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}
