import Foundation

/// Persists the playback session, replacing `@Shared(.fileStorage(...))` from swift-sharing (#15).
///
/// **The path and JSON shape are a compatibility boundary.** Users already have a `session.json`
/// written by the `@Shared` version; changing either orphans it and playback stops resuming after
/// an update. `SessionCodec`'s round-trip test (#11) is what guards the shape; this type guards
/// the location.
///
/// `@Shared` coalesced rapid writes. This does not — but the session is only written at three
/// discrete lifecycle points (clear, suspend, background), never per playback tick, so there is
/// nothing to coalesce.
struct SessionStore {

    private let url: URL

    init(url: URL = SessionStore.defaultURL) {
        self.url = url
    }

    /// `<tmp>/SonicPlayer/session.json` — unchanged from `PlayerFeature.State.sessionURL`.
    ///
    /// Note this is the temp directory, which iOS may purge. That is pre-existing behaviour and
    /// deliberately preserved here; moving it to Application Support is a real improvement and a
    /// separate decision, not something to smuggle into a behaviour-preserving migration.
    static var defaultURL: URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SonicPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.json")
    }

    /// Returns an empty session when the file is absent or unreadable — the same outcome
    /// `@Shared` produced from its default value, so a cold launch with no file behaves as before.
    func load() -> PlaybackSession {
        guard
            let data = try? Data(contentsOf: url),
            let session = try? JSONDecoder().decode(PlaybackSession.self, from: data)
        else { return PlaybackSession() }
        return session
    }

    func save(_ session: PlaybackSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// An in-memory store for tests, mirroring `$0.defaultFileStorage = .inMemory`.
    static func inMemory() -> SessionStore {
        SessionStore(
            url: FileManager.default.temporaryDirectory
                .appendingPathComponent("SonicPlayerTests-\(UUID().uuidString).json")
        )
    }
}
