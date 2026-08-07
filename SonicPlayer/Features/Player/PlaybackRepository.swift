import Foundation

/// Resolving a saved session against the filesystem (#44).
///
/// This is the half of `PlayerViewModel.restoreSession` that does I/O. It was inline, and it
/// probed the filesystem through `FileManager.default` while the view model was holding an
/// injected `FileManagerClient` — so the one path deciding whether a user resumes where they
/// left off was the one path no test could control.
///
/// The decision itself is not here. `SessionRestorePlan` makes it, over values.
protocol PlaybackRepository: Sendable {
    func restore(_ saved: PlaybackSession) async -> SessionRestorePlan.Resolved?
}

struct LivePlaybackRepository: PlaybackRepository {

    private let files: FileManaging

    init(files: FileManaging) {
        self.files = files
    }

    func restore(_ saved: PlaybackSession) async -> SessionRestorePlan.Resolved? {
        // Repeated from `SessionRestorePlan`, and not redundant: that guard protects the
        // *decision*, this one protects the *I/O*. `URL(fileURLWithPath: "")` resolves to the
        // process's current directory, which exists and answers a metadata read — so an empty
        // session that reaches the filesystem comes back with a folder posing as a track (#33).
        guard !saved.isEmpty else { return nil }

        // A missing file is reported by the metadata read throwing. That is what replaced the
        // separate `FileManager.default.fileExists` probe: one call, through the injected
        // client, where a test can drive what is found.
        let current = try? await files.metadata(for: URL(fileURLWithPath: saved.fileURL))

        var surviving: [AudioFile] = []
        for item in saved.queue {
            if let file = try? await files.metadata(for: URL(fileURLWithPath: item.fileURL)) {
                surviving.append(file)
            }
        }

        return SessionRestorePlan.resolve(saved: saved, current: current, surviving: surviving)
    }
}
