import Foundation
import Synchronization  // Mutex — the trimmer closure is @Sendable
import Testing

@testable import SonicPlayer

/// What must survive a trim that goes wrong (#74).
///
/// These write real files, because the whole claim is about the file system: a mock that records
/// "copy was called" cannot tell you whether the recording is still on disk afterwards, which is
/// the only thing worth asserting here.
@Suite
struct TrimCommitTests {

    @Test func aSuccessfulTrimReplacesTheRecordingInPlace() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let recording = dir.appendingPathComponent("Lecture.m4a")
        try Data("original".utf8).write(to: recording)

        var trimmer = AudioTrimmerClient.test
        trimmer.trimAudio = { staged, _, _ in
            try Data("trimmed".utf8).write(to: staged)
            return staged
        }

        let result = try await TrimCommit.run(url: recording, start: 1, end: 2, trimmer: trimmer)

        #expect(result == recording, "The recording keeps its name — the caller has it already.")
        #expect(try Data(contentsOf: recording) == Data("trimmed".utf8))
    }

    /// The reason this type exists instead of calling `trimAudio` on the file directly: that call
    /// deletes its source before it has anywhere to put the result.
    @Test func aFailedTrimLeavesTheRecordingExactlyAsItWas() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let recording = dir.appendingPathComponent("Lecture.m4a")
        try Data("original".utf8).write(to: recording)

        var trimmer = AudioTrimmerClient.test
        trimmer.trimAudio = { _, _, _ in throw AudioTrimmerError.invalidTimeRange }

        await #expect(throws: AudioTrimmerError.self) {
            _ = try await TrimCommit.run(url: recording, start: 1, end: 2, trimmer: trimmer)
        }

        #expect(FileManager.default.fileExists(atPath: recording.path))
        #expect(try Data(contentsOf: recording) == Data("original".utf8))
    }

    @Test func aFailedTrimTakesItsStagedCopyWithIt() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let recording = dir.appendingPathComponent("Lecture.m4a")
        try Data("original".utf8).write(to: recording)

        let staged = Mutex<URL?>(nil)
        var trimmer = AudioTrimmerClient.test
        trimmer.trimAudio = { url, _, _ in
            staged.withLock { $0 = url }
            throw AudioTrimmerError.exportSessionCreationFailed
        }

        _ = try? await TrimCommit.run(url: recording, start: 1, end: 2, trimmer: trimmer)

        let leftBehind = staged.withLock { $0 }
        #expect(leftBehind != nil, "The trimmer must have been handed a copy, not the original.")
        #expect(leftBehind != recording, "The original is never what gets trimmed.")
        #expect(!FileManager.default.fileExists(atPath: leftBehind?.path ?? ""))
    }

    /// A recording that is not there cannot be staged, and the failure has to reach the caller
    /// rather than producing an empty file where the lecture was.
    @Test func aMissingRecordingThrowsRatherThanInventingOne() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let missing = dir.appendingPathComponent("Not There.m4a")

        await #expect(throws: (any Error).self) {
            _ = try await TrimCommit.run(url: missing, start: 1, end: 2, trimmer: .test)
        }

        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    // MARK: -

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrimCommitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
