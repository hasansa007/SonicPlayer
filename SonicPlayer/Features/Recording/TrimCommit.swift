import Foundation

/// Applying the dial editor's trim to a saved recording (#74).
///
/// **The dial has no separate save step, so committing *is* the save** — pressing the hub on the
/// edit screen rewrites the file. That makes the failure path the whole design problem, and it is
/// why this exists rather than a direct `audioTrimmer.trimAudio(url, start, end)`:
///
/// `AudioTrimmerClient.trimAudio` deletes its source and then moves the export into that name. On
/// the temp copy `EditRecordingViewModel` hands it, that is fine — losing a scratch file costs
/// nothing. Pointed at the user's saved recording it is a delete followed by a move that might not
/// happen, and what it can lose is a lecture.
///
/// So the trim runs on a staged copy and the original is replaced only once there is something to
/// replace it with, through `replaceItemAt` rather than remove-then-move. A failure anywhere leaves
/// the recording exactly as it was.
///
/// Not in `Domain/`, for the same reason `OpenInImport` is not: once the ordering above is written
/// down there is no decision left, only I/O. The decision — where the handles may sit — is
/// `DialTrimRange`, and it has already been made by the time this runs.
enum TrimCommit {

    /// Returns the URL now holding the trimmed audio, which is the one that was passed in.
    ///
    /// Throws whatever the trimmer or the file system throws, having first put the staged copy
    /// back in the bin. The caller is expected to surface it.
    static func run(
        url: URL,
        start: TimeInterval,
        end: TimeInterval,
        trimmer: AudioTrimmerClient
    ) async throws -> URL {
        let staged = stagingURL(pathExtension: url.pathExtension)
        try FileManager.default.copyItem(at: url, to: staged)

        do {
            let trimmed = try await trimmer.trimAudio(staged, start, end)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: trimmed)
            return url
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
    }

    /// Its own directory beside `EditRecordingViewModel`'s `edit/`, not shared with it: that one
    /// holds files the user is still working on and may keep, this one holds files that are
    /// garbage the moment the call returns. A cleanup sweep over either must not have to tell them
    /// apart.
    private static func stagingURL(pathExtension: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SonicPlayer/commit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("commit-\(UUID().uuidString).\(pathExtension)")
    }
}
