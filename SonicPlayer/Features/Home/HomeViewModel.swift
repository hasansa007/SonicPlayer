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

    var recentFiles: [AudioFile] = []

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

    func loadRecentFiles() {
        // Screenshot mode seeds demo data; loading real files would wipe it.
        if ScreenshotMode.isEnabled && !recentFiles.isEmpty { return }

        Task { [weak self, fileManager] in
            guard let files = try? await Self.recentFiles(fileManager: fileManager) else { return }
            await MainActor.run { self?.recentFiles = files }
        }
    }

    /// Tapping a recent file plays it, with the recents list as the queue.
    func fileTapped(_ file: AudioFile) {
        player.loadTrack(file, queue: recentFiles, source: .singleFile)
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

    /// Unchanged from `HomeFeature.swift`, where it was already a free function taking the client
    /// as a plain parameter rather than through `@Dependency`.
    static func recentFiles(fileManager: FileManagerClient) async throws -> [AudioFile] {
        var allFiles: [AudioFile] = []
        var seenNames: Set<String> = []
        try await collect(from: nil, into: &allFiles, seenNames: &seenNames, fileManager: fileManager)
        allFiles.sort { $0.creationDate > $1.creationDate }
        return Array(allFiles.prefix(3))
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
