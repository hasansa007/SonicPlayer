import Foundation
import Observation

/// Replaces `HomeFeature` (#16), and is mostly deletion.
///
/// `HomeFeature.State` carried three properties — `lastPlayedTrack`, `isPlaying`,
/// `playbackProgress` — that were **copies** of player state, resynced by `AppFeature` on four
/// separate actions. That mirror existed only because TCA state is a value type split across
/// scoped stores: Home had no way to see the player except by being handed a copy.
///
/// `PlayerViewModel` is a reference type, so Home holds the same instance the rest of the app
/// does and reads it directly. The three properties and their four sync taps are **deleted, not
/// ported** — which is also why #15 and #16 had to land together: once the player leaves the
/// store, `AppFeature` can no longer observe its actions to maintain the mirror.
///
/// Ten of the twelve former actions were `return .none // Handled by parent`. They are closures
/// now, wired at the composition root.
@MainActor
@Observable
final class HomeViewModel {

    /// The same instance the player screen and mini player use. Reading through it is what
    /// replaces the mirror.
    let player: PlayerViewModel

    var allFiles: [AudioFile] = []

    // Formerly `.none // Handled by parent` cases in HomeFeature.
    var onFileTapped: (AudioFile) -> Void = { _ in }
    var onImportTapped: () -> Void = {}
    var onNewCollectionTapped: () -> Void = {}
    var onViewAllCollectionsTapped: () -> Void = {}
    var onRenameFile: (AudioFile) -> Void = { _ in }
    var onDeleteFile: (AudioFile) -> Void = { _ in }
    var onEditFile: (AudioFile) -> Void = { _ in }
    var onMoveFile: (AudioFile) -> Void = { _ in }

    private let fileManager: FileManagerClient

    /// Where the root is, so `CollectionLabel` can tell a file in a collection from one that is
    /// not. Read through the injected client rather than `FileManager.default`, which is what
    /// `MediaFileRowView` used to do from inside its own `body` (#48).
    var documentsURL: URL { fileManager.documentsDirectory() }

    init(player: PlayerViewModel, fileManager: FileManagerClient = .live) {
        self.player = player
        self.fileManager = fileManager
    }

    func loadAllFiles() {
        // Screenshot mode seeds demo data; loading real files would wipe it.
        if ScreenshotMode.isEnabled && !allFiles.isEmpty { return }

        Task { [weak self, fileManager] in
            guard let files = try? await Self.allAudioFiles(fileManager: fileManager) else { return }
            await MainActor.run { self?.allFiles = files }
        }
    }

    /// Tapping a recent file plays it, with the recents list as the queue.
    func fileTapped(_ file: AudioFile) {
        player.loadTrack(file, queue: allFiles, source: .singleFile)
        onFileTapped(file)
    }

    /// The Home strip's play button. Expands the player for a new track, matching
    /// `AppFeature.home(.playTrack)`.
    func playTrack(_ track: AudioFile) {
        player.isExpanded = true
        if player.currentTrack?.id != track.id {
            player.loadTrack(track, queue: [track], source: .singleFile)
        }
    }

    func togglePlayPause() {
        player.playPauseTapped()
    }
}

// MARK: - Recent files

private extension HomeViewModel {

    /// **Every audio file, newest first — the `prefix(3)` that used to end this is gone.**
    ///
    /// That cap was right when this fed a "Recently added" strip on a Home screen: three rows on a
    /// dashboard is a preview, and a preview is what it was. Home is now the dial, and the same
    /// property became the dial's entire library, the count on the Library card, and the queue a
    /// track is played into. None of those wanted three.
    ///
    /// So the library screen showed at most three recordings however many existed, the card's
    /// number was pinned at 3, and playing anything gave you a two-track queue. One property whose
    /// meaning did not survive the move it was carried through, and nothing failed — it just quietly
    /// answered a smaller question than it was being asked.
    static func allAudioFiles(fileManager: FileManagerClient) async throws -> [AudioFile] {
        var allFiles: [AudioFile] = []
        var seenNames: Set<String> = []
        try await collect(from: nil, into: &allFiles, seenNames: &seenNames, fileManager: fileManager)
        allFiles.sort { $0.creationDate > $1.creationDate }
        return allFiles
    }

    /// Deduplicates by filename, so the same recording surfaced in two collections appears once.
    static func collect(
        from directory: URL?,
        into files: inout [AudioFile],
        seenNames: inout Set<String>,
        fileManager: FileManagerClient
    ) async throws {
        let items = try await fileManager.listItems(directory)
        for item in items {
            switch item {
            case let .file(audioFile):
                let name = audioFile.url.lastPathComponent
                if !seenNames.contains(name) {
                    seenNames.insert(name)
                    files.append(audioFile)
                }
            case let .folder(folder):
                try await collect(
                    from: folder.url, into: &files, seenNames: &seenNames, fileManager: fileManager
                )
            }
        }
    }
}
