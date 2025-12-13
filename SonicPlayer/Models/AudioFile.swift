import Foundation

struct AudioFile: Identifiable, Equatable, Codable, Hashable {
    let id: UUID
    let url: URL
    let title: String
    let duration: TimeInterval
    let fileSize: Int64
    let format: AudioFormat

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        duration: TimeInterval,
        fileSize: Int64,
        format: AudioFormat
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.duration = duration
        self.fileSize = fileSize
        self.format = format
    }

    var durationFormatted: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var fileSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

enum AudioFormat: String, Codable, Hashable {
    case mp3 = "mp3"
    case m4a = "m4a"
    case wav = "wav"

    var displayName: String {
        switch self {
        case .mp3: return "MP3"
        case .m4a: return "M4A"
        case .wav: return "WAV"
        }
    }
}
