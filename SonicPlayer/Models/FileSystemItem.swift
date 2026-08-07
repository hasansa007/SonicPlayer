import Foundation

enum FileSystemItem: Identifiable, Equatable, Hashable, Sendable {
    case folder(CollectionItem)
    case file(AudioFile)

    var id: AnyHashable {
        switch self {
        case .folder(let folder): return folder.id
        case .file(let file): return file.id
        }
    }

    var name: String {
        switch self {
        case .folder(let folder): return folder.name
        case .file(let file): return file.title
        }
    }

    var url: URL {
        switch self {
        case .folder(let folder): return folder.url
        case .file(let file): return file.url
        }
    }

    var date: Date {
        switch self {
        case .folder(let folder): return folder.creationDate
        case .file(let file): return file.creationDate
        }
    }

    var size: Int64 {
        switch self {
        case .folder: return 0
        case .file(let file): return file.fileSize
        }
    }
}

struct CollectionItem: Identifiable, Equatable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let creationDate: Date
    var itemCount: Int = 0
    var subfolderCount: Int = 0
    var totalDuration: TimeInterval = 0

    var durationFormatted: String {
        let hours = Int(totalDuration) / 3600
        let minutes = Int(totalDuration) / 60 % 60
        let seconds = Int(totalDuration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
