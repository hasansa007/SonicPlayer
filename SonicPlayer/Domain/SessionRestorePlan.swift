import Foundation

/// What a saved session asks for, once you already know which of its files still exist.
///
/// Extracted from `PlayerViewModel.restoreSession` (#44), which decided this inline while also
/// probing the filesystem and coordinating against a concurrent open. Those three jobs had one
/// consequence: none of them could be tested without constructing a player with four clients.
///
/// Foundation only. No client, no view model, no `FileManager` — deciding *what* to restore is
/// separable from finding out what survived, and only the first half is a decision.
enum SessionRestorePlan {

    struct Resolved: Equatable {
        let track: AudioFile
        let queue: [AudioFile]
        let index: Int
    }

    /// `nil` means "restore nothing" — the caller clears the session.
    static func resolve(
        saved: PlaybackSession,
        current: AudioFile?,
        surviving: [AudioFile]
    ) -> Resolved? {
        guard !saved.isEmpty, let current else { return nil }

        return Resolved(
            track: current,
            queue: surviving,
            // The queue can be shorter than the one that was saved — entries are dropped as
            // their files vanish — so the saved index cannot be trusted and is re-derived here.
            index: surviving.firstIndex(of: current) ?? 0
        )
    }
}
