import Foundation

/// What gets persisted so playback can resume after a cold launch.
///
/// Moved out of `PlayerFeature.swift` unchanged. These types never referenced TCA — they only
/// happened to live in a file that imports it, which would have made every `Domain` type that
/// touches a session transitively dependent on the framework this epic removes.
///
/// `SessionStore` persists this, writing the same JSON to the same path that
/// `@Shared(.fileStorage(...))` used before #15 replaced it. The shape here is therefore a
/// compatibility boundary: change it and previously-saved sessions stop restoring.
struct QueueItem: Codable, Equatable {
    var fileURL: String
}

struct PlaybackSession: Codable, Equatable {
    var fileURL: String
    var currentTime: TimeInterval
    var queue: [QueueItem]
    var playlistSource: PlaylistSource?

    init(
        fileURL: String = "",
        currentTime: TimeInterval = 0,
        queue: [QueueItem] = [],
        playlistSource: PlaylistSource? = nil
    ) {
        self.fileURL = fileURL
        self.currentTime = currentTime
        self.queue = queue
        self.playlistSource = playlistSource
    }

    var isEmpty: Bool {
        fileURL.isEmpty
    }
}

enum PlaylistSource: Equatable, Codable {
    case folder(URL)
    case singleFile
}
